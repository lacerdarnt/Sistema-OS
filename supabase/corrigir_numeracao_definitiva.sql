-- Execute após os demais scripts no SQL Editor do Supabase.
begin;
lock table public.ordens in access exclusive mode;

do $$
declare v_pk text; v_is_number boolean;
begin
  if not exists (select 1 from pg_constraint where conrelid='public.ordens'::regclass and conname='ordens_id_unique') then
    alter table public.ordens add constraint ordens_id_unique unique (id);
  end if;
  select c.conname, c.conkey = array[a.attnum]::smallint[] into v_pk, v_is_number
    from pg_constraint c join pg_attribute a on a.attrelid=c.conrelid and a.attname='os_numero'
    where c.conrelid='public.ordens'::regclass and c.contype='p';
  if not coalesce(v_is_number,false) then
    -- Sem CASCADE: dependências inesperadas abortam sem apagar dados.
    if v_pk is not null then execute format('alter table public.ordens drop constraint %I',v_pk); end if;
    alter table public.ordens add constraint ordens_pkey primary key (os_numero);
  end if;
end $$;

create table if not exists public.os_number_counter (
  singleton boolean primary key default true check (singleton),
  last_number bigint not null check (last_number >= 0)
);
alter table public.os_number_counter enable row level security;
revoke all on public.os_number_counter from public, anon, authenticated;
insert into public.os_number_counter(singleton,last_number)
select true,coalesce(max(nullif(regexp_replace(os_numero,'[^0-9]','','g'),'')::bigint),0) from public.ordens
on conflict (singleton) do update set last_number=greatest(public.os_number_counter.last_number,excluded.last_number);

create or replace function public.preview_os_number()
returns text language plpgsql security definer set search_path=public
as $$
declare v_next bigint;
begin
  if not public.has_permission('create') then
    raise exception 'Usuário sem permissão para incluir OS.' using errcode='42501';
  end if;
  select last_number+1 into v_next from public.os_number_counter where singleton=true;
  return 'OS-' || lpad(v_next::text,greatest(6,length(v_next::text)),'0');
end $$;
revoke all on function public.preview_os_number() from public,anon;
grant execute on function public.preview_os_number() to authenticated;

-- Clientes antigos também deixam de consumir números ao abrir o formulário.
create or replace function public.next_os_number()
returns text language sql security invoker set search_path=public
as $$ select public.preview_os_number(); $$;
revoke all on function public.next_os_number() from public,anon;
grant execute on function public.next_os_number() to authenticated;

create or replace function public.assign_os_number_on_insert()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_number bigint;
begin
  -- O bloqueio da linha serializa inserções; rollback desfaz o contador.
  update public.os_number_counter set last_number=last_number+1
    where singleton=true returning last_number into v_number;
  if v_number is null then raise exception 'Contador de OS não configurado.'; end if;
  new.os_numero := 'OS-' || lpad(v_number::text,greatest(6,length(v_number::text)),'0');
  new.data := jsonb_set(coalesce(new.data,'{}'::jsonb),'{osNumero}',to_jsonb(new.os_numero),true);
  return new;
end $$;
revoke all on function public.assign_os_number_on_insert() from public,anon,authenticated;
drop trigger if exists assign_os_number on public.ordens;
create trigger assign_os_number before insert on public.ordens
for each row execute function public.assign_os_number_on_insert();

create or replace function public.protect_os_number_on_update()
returns trigger language plpgsql set search_path=public
as $$
begin
  if new.os_numero is distinct from old.os_numero then
    raise exception 'O número de uma OS salva não pode ser alterado.';
  end if;
  new.data := jsonb_set(coalesce(new.data,'{}'::jsonb),'{osNumero}',to_jsonb(new.os_numero),true);
  return new;
end $$;
revoke all on function public.protect_os_number_on_update() from public,anon,authenticated;
drop trigger if exists protect_os_number on public.ordens;
create trigger protect_os_number before update on public.ordens
for each row execute function public.protect_os_number_on_update();
notify pgrst, 'reload schema';
commit;
