-- ============================================================================
-- SISTEMA-OS: SCHEMA SEGURO COM WHITELIST E AUDITORIA
-- Execute este arquivo UMA VEZ no SQL Editor do projeto Supabase
-- ============================================================================

create extension if not exists pgcrypto;

-- ============================================================================
-- 1. TABELA DE EMAILS PERMITIDOS (WHITELIST)
-- ============================================================================
create table if not exists public.allowed_emails (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  role text not null default 'viewer' check (role in ('viewer', 'editor')),
  can_manage_users boolean default false,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  notes text
);
alter table public.allowed_emails enable row level security;

-- ============================================================================
-- 2. TABELAS DE PERFIL E ORDENS (MELHORADAS)
-- ============================================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  role text not null default 'viewer' check (role in ('viewer', 'editor')),
  is_master boolean default false,
  must_change_password boolean not null default false,
  last_login timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles add column if not exists must_change_password boolean not null default false;

create table if not exists public.ordens (
  id uuid primary key default gen_random_uuid(),
  os_numero text not null unique,
  status text not null default '',
  data jsonb not null default '{}'::jsonb,
  fotos jsonb not null default '[]'::jsonb,
  sig_entrada_url text,
  sig_saida_url text,
  sig_tecnico_url text,
  user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ordens add column if not exists user_id uuid references auth.users(id);
alter table public.ordens add column if not exists fotos jsonb not null default '[]'::jsonb;
alter table public.ordens add column if not exists sig_entrada_url text;
alter table public.ordens add column if not exists sig_saida_url text;
alter table public.ordens add column if not exists sig_tecnico_url text;

-- Converte instalações antigas, nas quais fotos era text[], para o formato
-- JSON usado para separar imagens de check-in e check-out. É seguro executar
-- novamente quando a coluna já estiver em jsonb.
alter table public.ordens alter column fotos drop default;
alter table public.ordens alter column fotos type jsonb
using (
  case
    when fotos is null then jsonb_build_object('entrada', '[]'::jsonb, 'saida', '[]'::jsonb)
    when jsonb_typeof(to_jsonb(fotos)) = 'array'
      then jsonb_build_object('entrada', to_jsonb(fotos), 'saida', '[]'::jsonb)
    else to_jsonb(fotos)
  end
);
alter table public.ordens alter column fotos
set default jsonb_build_object('entrada', '[]'::jsonb, 'saida', '[]'::jsonb);

-- ============================================================================
-- 3. TABELA DE AUDITORIA
-- ============================================================================
create table if not exists public.audit_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  action text not null,
  table_name text,
  record_id text,
  changes jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);
alter table public.audit_log enable row level security;

-- ============================================================================
-- 4. FUNCTIONS PARA SEGURANÇA
-- ============================================================================

-- Verificar se email está na whitelist
create or replace function public.email_is_allowed(email text)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(
    select 1 from public.allowed_emails 
    where allowed_emails.email = $1 and approved_at is not null
  ) or 
  exists(
    select 1 from public.profiles 
    where profiles.email = $1 and profiles.is_master
  )
$$;

-- Verificar se é editor
create or replace function public.is_editor()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(
    select 1 from public.profiles 
    where id = auth.uid() and role = 'editor' and not must_change_password
  )
$$;

-- Verificar se é master
create or replace function public.is_master()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(
    select 1 from public.profiles 
    where id = auth.uid() and is_master = true
  )
$$;

-- Registrar auditoria
create or replace function public.log_audit(
  p_action text,
  p_table_name text,
  p_record_id text,
  p_changes jsonb
)
returns void language plpgsql security definer set search_path = public
as $$
begin
  insert into public.audit_log (user_id, action, table_name, record_id, changes)
  values (auth.uid(), p_action, p_table_name, p_record_id, p_changes);
end;
$$;

-- Verificar se a sessão ainda possui um perfil autorizado. Todas as leituras
-- sensíveis usam esta função para que a revogação tenha efeito imediato.
create or replace function public.is_authorized()
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(select 1 from public.profiles where id = auth.uid() and not must_change_password)
$$;

-- Libera a conta depois que o próprio usuário troca a senha temporária.
create or replace function public.complete_password_change()
returns void language plpgsql security definer set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Sessão inválida'; end if;
  update public.profiles
  set must_change_password = false, updated_at = now()
  where id = auth.uid();
end;
$$;

revoke all on function public.email_is_allowed(text) from public, anon, authenticated;
revoke all on function public.log_audit(text, text, text, jsonb) from public, anon;
grant execute on function public.log_audit(text, text, text, jsonb) to authenticated;

-- Trigger para validar novo usuário
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
declare
  v_role text;
  v_allowed boolean;
begin
  -- Verificar whitelist
  v_allowed := public.email_is_allowed(lower(new.email));
  if not v_allowed then
    raise exception 'Email não autorizado. Entre em contato com o administrador.';
  end if;
  
  -- Obter role da whitelist
  select role into v_role from public.allowed_emails 
  where lower(email) = lower(new.email) and approved_at is not null;
  
  if v_role is null then
    v_role := 'viewer';
  end if;
  
  -- Criar perfil
  insert into public.profiles (id, email, role, must_change_password) 
  values (new.id, new.email, v_role, true)
  on conflict (id) do update set email = excluded.email, role = excluded.role, must_change_password = true, updated_at = now();
  
  -- Log auditoria
  -- auth.uid() pode ser nulo quando a conta é criada pelo Dashboard.
  insert into public.audit_log (user_id, action, table_name, record_id, changes)
  values (new.id, 'user_created', 'auth.users', new.id::text, jsonb_build_object('email', new.email));
  
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Não existe evento de "login" confiável em auth.users. Removemos o trigger
-- anterior, que executava em qualquer atualização da conta.
drop trigger if exists on_auth_user_login on auth.users;
drop function if exists public.update_last_login();

-- ============================================================================
-- 5. ROW LEVEL SECURITY (RLS) - POLICIES
-- ============================================================================

alter table public.profiles enable row level security;
alter table public.ordens enable row level security;

revoke all on function public.is_editor() from public, anon;
revoke all on function public.is_master() from public, anon;
revoke all on function public.is_authorized() from public, anon;
revoke all on function public.complete_password_change() from public, anon;
grant execute on function public.is_editor() to authenticated;
grant execute on function public.is_master() to authenticated;
grant execute on function public.is_authorized() to authenticated;
grant execute on function public.complete_password_change() to authenticated;

-- PROFILES: Cada usuário vê apenas seu perfil, Master vê todos
drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles for select to authenticated
using (
  id = auth.uid() or public.is_master()
);

-- PROFILES: Usuários não podem se modificar
drop policy if exists "profiles_update" on public.profiles;
create policy "profiles_update" on public.profiles for update to authenticated
using (public.is_master())
with check (public.is_master());

drop policy if exists "profiles_insert" on public.profiles;
create policy "profiles_insert" on public.profiles for insert to authenticated
with check (false); -- Auto-criado pelo trigger

-- ORDENS: Todos autenticados leem, só editors criam/editam
drop policy if exists "ordens_read" on public.ordens;
create policy "ordens_read" on public.ordens for select to authenticated
using (public.is_authorized());

drop policy if exists "ordens_insert" on public.ordens;
create policy "ordens_insert" on public.ordens for insert to authenticated
with check (
  public.is_editor() and 
  user_id = auth.uid()
);

drop policy if exists "ordens_update" on public.ordens;
create policy "ordens_update" on public.ordens for update to authenticated
using (public.is_editor() and status <> 'Entregue' and (user_id = auth.uid() or public.is_master()))
with check (public.is_editor() and (user_id = auth.uid() or public.is_master()));

drop policy if exists "ordens_delete" on public.ordens;
create policy "ordens_delete" on public.ordens for delete to authenticated
using (public.is_editor() and status <> 'Entregue' and (user_id = auth.uid() or public.is_master()));

-- ALLOWED_EMAILS: Apenas Master pode gerenciar
drop policy if exists "allowed_emails_read" on public.allowed_emails;
create policy "allowed_emails_read" on public.allowed_emails for select to authenticated
using (public.is_master());

drop policy if exists "allowed_emails_insert" on public.allowed_emails;
create policy "allowed_emails_insert" on public.allowed_emails for insert to authenticated
with check (public.is_master());

drop policy if exists "allowed_emails_update" on public.allowed_emails;
create policy "allowed_emails_update" on public.allowed_emails for update to authenticated
using (public.is_master())
with check (public.is_master());

drop policy if exists "allowed_emails_delete" on public.allowed_emails;
create policy "allowed_emails_delete" on public.allowed_emails for delete to authenticated
using (public.is_master());

-- AUDIT_LOG: Autenticados veem seu log, Master vê tudo
drop policy if exists "audit_log_read" on public.audit_log;
create policy "audit_log_read" on public.audit_log for select to authenticated
using (
  user_id = auth.uid() or public.is_master()
);

-- ============================================================================
-- 6. STORAGE - POLICIES
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('os-data', 'os-data', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "os_data_read" on storage.objects;
drop policy if exists "os_data_upload" on storage.objects;
drop policy if exists "os_data_update" on storage.objects;
drop policy if exists "os_data_delete" on storage.objects;

create policy "os_data_read" on storage.objects for select to authenticated
using (bucket_id = 'os-data' and public.is_authorized());

create policy "os_data_upload" on storage.objects for insert to authenticated
with check (
  bucket_id = 'os-data' and 
  public.is_editor() and
  (storage.foldername(name))[1] = auth.uid()::text
);

create policy "os_data_update" on storage.objects for update to authenticated
using (bucket_id = 'os-data' and public.is_editor() and ((storage.foldername(name))[1] = auth.uid()::text or public.is_master()))
with check (bucket_id = 'os-data' and public.is_editor() and ((storage.foldername(name))[1] = auth.uid()::text or public.is_master()));

create policy "os_data_delete" on storage.objects for delete to authenticated
using (bucket_id = 'os-data' and public.is_editor() and ((storage.foldername(name))[1] = auth.uid()::text or public.is_master()));

-- ============================================================================
-- 7. DADOS INICIAIS
-- ============================================================================

-- Remove apenas o exemplo inseguro deixado por versões anteriores, se ele não
-- corresponder a uma conta real.
delete from public.allowed_emails ae
where lower(ae.email) = 'admin@seudominio.com'
  and not exists (select 1 from auth.users u where lower(u.email) = lower(ae.email));

-- Migra contas existentes que já estejam na whitelist.
insert into public.profiles (id, email, role, is_master)
select u.id, lower(u.email), ae.role, coalesce(ae.can_manage_users, false)
from auth.users u
join public.allowed_emails ae on lower(ae.email) = lower(u.email)
where ae.approved_at is not null
on conflict (id) do update
set email = excluded.email,
    role = excluded.role,
    is_master = public.profiles.is_master or excluded.is_master,
    updated_at = now();

-- ============================================================================
-- 8. INSTRUÇÕES FINAIS
-- ============================================================================

-- O usuário master já deve existir em Authentication. Execute UMA VEZ no SQL
-- Editor, substituindo o email nas duas ocorrências:
--
-- insert into public.allowed_emails (email, role, can_manage_users, approved_at)
-- values (lower('SEU_EMAIL_MASTER'), 'editor', true, now())
-- on conflict (email) do update set role='editor', can_manage_users=true, approved_at=now();
--
-- insert into public.profiles (id, email, role, is_master)
-- select id, lower(email), 'editor', true from auth.users
-- where lower(email)=lower('SEU_EMAIL_MASTER')
-- on conflict (id) do update set email=excluded.email, role='editor', is_master=true, must_change_password=false, updated_at=now();
--
-- 3. Para adicionar novos usuários (apenas Master pode fazer):
--    INSERT INTO public.allowed_emails (email, role, approved_at)
--    VALUES ('novo@email.com', 'editor', now());
--
-- 4. Para desabilitar signup na interface, veja o arquivo Sistema-OS.html
--    Remova o botão "Cadastrar" ou restrinja via JavaScript
