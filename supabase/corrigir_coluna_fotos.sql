-- SISTEMA-OS: correção do erro 22P02 ao salvar fotos
-- Execute todo este arquivo no SQL Editor do Supabase.

begin;

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

commit;

-- Deve retornar data_type = jsonb.
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'ordens'
  and column_name = 'fotos';
