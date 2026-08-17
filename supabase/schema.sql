-- Execute este arquivo uma vez no SQL Editor do projeto Supabase.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  role text not null default 'viewer' check (role in ('viewer', 'editor')),
  created_at timestamptz not null default now()
);

create table if not exists public.ordens (
  id uuid primary key default gen_random_uuid(),
  os_numero text not null unique,
  status text not null default '',
  data jsonb not null default '{}'::jsonb,
  fotos jsonb not null default '[]'::jsonb,
  sig_entrada_url text,
  sig_saida_url text,
  sig_tecnico_url text,
  user_id uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.ordens add column if not exists user_id uuid references auth.users(id);
alter table public.ordens add column if not exists fotos jsonb not null default '[]'::jsonb;
alter table public.ordens add column if not exists sig_entrada_url text;
alter table public.ordens add column if not exists sig_saida_url text;
alter table public.ordens add column if not exists sig_tecnico_url text;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email)
  on conflict (id) do update set email = excluded.email;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert or update of email on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.ordens enable row level security;

drop policy if exists "profiles_select_own" on public.profiles;
create policy "profiles_select_own" on public.profiles for select to authenticated
using (id = auth.uid());
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles for insert to authenticated
with check (id = auth.uid() and role = 'viewer');
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid() and role = 'viewer');

create or replace function public.is_editor()
returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'editor') $$;

drop policy if exists "ordens_read_authenticated" on public.ordens;
create policy "ordens_read_authenticated" on public.ordens for select to authenticated using (true);
drop policy if exists "ordens_insert_editor" on public.ordens;
create policy "ordens_insert_editor" on public.ordens for insert to authenticated
with check (public.is_editor() and user_id = auth.uid());
drop policy if exists "ordens_update_editor" on public.ordens;
create policy "ordens_update_editor" on public.ordens for update to authenticated
using (public.is_editor()) with check (public.is_editor());
drop policy if exists "ordens_delete_editor" on public.ordens;
create policy "ordens_delete_editor" on public.ordens for delete to authenticated
using (public.is_editor());

insert into storage.buckets (id, name, public)
values ('os-data', 'os-data', false)
on conflict (id) do update set public = excluded.public;

drop policy if exists "os_data_upload_editor" on storage.objects;
drop policy if exists "os_data_read_authenticated" on storage.objects;
create policy "os_data_read_authenticated" on storage.objects for select to authenticated
using (bucket_id = 'os-data');
create policy "os_data_upload_editor" on storage.objects for insert to authenticated
with check (bucket_id = 'os-data' and public.is_editor());
drop policy if exists "os_data_update_editor" on storage.objects;
create policy "os_data_update_editor" on storage.objects for update to authenticated
using (bucket_id = 'os-data' and public.is_editor())
with check (bucket_id = 'os-data' and public.is_editor());
drop policy if exists "os_data_delete_editor" on storage.objects;
create policy "os_data_delete_editor" on storage.objects for delete to authenticated
using (bucket_id = 'os-data' and public.is_editor());

-- Depois do primeiro cadastro, conceda acesso de edição ao responsável:
-- update public.profiles set role = 'editor' where email = 'SEU_EMAIL_AQUI';
