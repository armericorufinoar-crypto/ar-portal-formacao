-- F4-1 · Etapa opcional nos materiais (Antes da aula / Explorar / Aprofundar)
-- Idempotente: pode ser executado mais do que uma vez.

alter table public.av_session_materials
  add column if not exists stage text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'av_session_materials_stage_chk'
      and conrelid = 'public.av_session_materials'::regclass
  ) then
    alter table public.av_session_materials
      add constraint av_session_materials_stage_chk
      check (stage is null or stage in ('antes','explorar','aprofundar'));
  end if;
end $$;

comment on column public.av_session_materials.stage is
  'Etapa opcional na aula: antes (Inspire-se), explorar (Explore), aprofundar (Saiba mais). Vazio = regra por tipo.';

notify pgrst, 'reload schema';
