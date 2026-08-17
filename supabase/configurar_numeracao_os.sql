-- SISTEMA-OS: numeração central compartilhada entre todos os dispositivos
-- Execute todo este arquivo no SQL Editor do Supabase uma única vez.

create sequence if not exists public.os_numero_seq;

-- Posiciona a sequência depois do maior número já existente, sem fazê-la
-- retroceder caso este script seja executado novamente.
do $$
declare
  v_last bigint;
  v_called boolean;
  v_max bigint;
  v_target bigint;
begin
  select last_value, is_called into v_last, v_called from public.os_numero_seq;
  select coalesce(max(nullif(regexp_replace(os_numero, '[^0-9]', '', 'g'), '')::bigint), 0)
    into v_max
  from public.ordens;

  if not v_called and v_max = 0 then
    perform setval('public.os_numero_seq', 1, false);
  else
    v_target := greatest(case when v_called then v_last else 0 end, v_max, 1);
    perform setval('public.os_numero_seq', v_target, true);
  end if;
end
$$;

create or replace function public.next_os_number()
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_editor() then
    raise exception 'Usuário sem permissão para criar OS.' using errcode = '42501';
  end if;

  return 'OS-' || lpad(nextval('public.os_numero_seq')::text, 6, '0');
end;
$$;

revoke all on function public.next_os_number() from public, anon;
grant execute on function public.next_os_number() to authenticated;

