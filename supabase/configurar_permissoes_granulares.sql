-- SISTEMA-OS: permissões independentes por usuário.
-- Execute todo este arquivo uma vez no SQL Editor do Supabase.

alter table public.allowed_emails
  add column if not exists can_view boolean not null default true,
  add column if not exists can_create boolean not null default false,
  add column if not exists can_edit boolean not null default false,
  add column if not exists can_delete boolean not null default false;

alter table public.profiles
  add column if not exists can_view boolean not null default true,
  add column if not exists can_create boolean not null default false,
  add column if not exists can_edit boolean not null default false,
  add column if not exists can_delete boolean not null default false;

-- Compatibilidade com os papéis anteriores.
update public.allowed_emails
set can_view = true,
    can_create = (role = 'editor'),
    can_edit = (role = 'editor'),
    can_delete = (role = 'editor');

update public.profiles
set can_view = true,
    can_create = (role = 'editor') or is_master,
    can_edit = (role = 'editor') or is_master,
    can_delete = (role = 'editor') or is_master;

create or replace function public.has_permission(p_permission text)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid()
      and not must_change_password
      and (
        is_master or
        case p_permission
          when 'view' then can_view
          when 'create' then can_create
          when 'edit' then can_edit
          when 'delete' then can_delete
          else false
        end
      )
  )
$$;

create or replace function public.is_editor()
returns boolean language sql stable security definer set search_path = public
as $$ select public.has_permission('create') or public.has_permission('edit') $$;

revoke all on function public.has_permission(text) from public, anon;
grant execute on function public.has_permission(text) to authenticated;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_allowed public.allowed_emails%rowtype;
begin
  select * into v_allowed from public.allowed_emails
  where lower(email)=lower(new.email) and approved_at is not null;
  if not found then raise exception 'Email não autorizado. Entre em contato com o administrador.'; end if;
  insert into public.profiles (id,email,role,can_view,can_create,can_edit,can_delete,must_change_password)
  values (new.id,lower(new.email),v_allowed.role,v_allowed.can_view,v_allowed.can_create,v_allowed.can_edit,v_allowed.can_delete,true)
  on conflict (id) do update set email=excluded.email,role=excluded.role,can_view=excluded.can_view,
    can_create=excluded.can_create,can_edit=excluded.can_edit,can_delete=excluded.can_delete,
    must_change_password=true,updated_at=now();
  insert into public.audit_log (user_id,action,table_name,record_id,changes)
  values (new.id,'user_created','auth.users',new.id::text,jsonb_build_object('email',new.email));
  return new;
end;
$$;

drop policy if exists "ordens_read" on public.ordens;
create policy "ordens_read" on public.ordens for select to authenticated
using (public.has_permission('view'));

drop policy if exists "ordens_insert" on public.ordens;
create policy "ordens_insert" on public.ordens for insert to authenticated
with check (public.has_permission('create') and user_id = auth.uid());

drop policy if exists "ordens_update" on public.ordens;
create policy "ordens_update" on public.ordens for update to authenticated
using (public.has_permission('edit') and status <> 'Entregue' and (user_id = auth.uid() or public.is_master()))
with check (public.has_permission('edit') and (user_id = auth.uid() or public.is_master()));

drop policy if exists "ordens_delete" on public.ordens;
create policy "ordens_delete" on public.ordens for delete to authenticated
using (public.has_permission('delete') and status <> 'Entregue' and (user_id = auth.uid() or public.is_master()));

drop policy if exists "os_data_read" on storage.objects;
create policy "os_data_read" on storage.objects for select to authenticated
using (bucket_id = 'os-data' and public.has_permission('view'));

drop policy if exists "os_data_upload" on storage.objects;
create policy "os_data_upload" on storage.objects for insert to authenticated
with check (bucket_id = 'os-data' and (public.has_permission('create') or public.has_permission('edit')) and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "os_data_update" on storage.objects;
create policy "os_data_update" on storage.objects for update to authenticated
using (bucket_id = 'os-data' and public.has_permission('edit') and ((storage.foldername(name))[1] = auth.uid()::text or public.is_master()))
with check (bucket_id = 'os-data' and public.has_permission('edit') and ((storage.foldername(name))[1] = auth.uid()::text or public.is_master()));

drop policy if exists "os_data_delete" on storage.objects;
create policy "os_data_delete" on storage.objects for delete to authenticated
using (bucket_id = 'os-data' and public.has_permission('delete') and ((storage.foldername(name))[1] = auth.uid()::text or public.is_master()));

create or replace function public.next_os_number()
returns text language plpgsql security definer set search_path = public
as $$
begin
  if not public.has_permission('create') then
    raise exception 'Usuário sem permissão para incluir OS.' using errcode = '42501';
  end if;
  return 'OS-' || lpad(nextval('public.os_numero_seq')::text, 6, '0');
end;
$$;

revoke all on function public.next_os_number() from public, anon;
grant execute on function public.next_os_number() to authenticated;
