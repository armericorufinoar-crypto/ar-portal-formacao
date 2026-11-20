-- 020_treino_profundidade_cadencia.sql
-- Repetível: pode ser executada mais do que uma vez sem erro.
-- 1) Profundidade (1 a 4) de cada pergunta do banco de treino.
-- 2) Cadência (1 a 4 aulas presenciais) de cada turma.
-- Não mexe em políticas RLS: as colunas novas herdam as políticas das tabelas.

alter table public.av_train_questions
  add column if not exists depth smallint;

alter table public.av_cohorts
  add column if not exists lessons_count smallint;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'av_train_questions_depth_chk') then
    alter table public.av_train_questions
      add constraint av_train_questions_depth_chk
      check (depth is null or depth between 1 and 4);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'av_cohorts_lessons_count_chk') then
    alter table public.av_cohorts
      add constraint av_cohorts_lessons_count_chk
      check (lessons_count is null or lessons_count between 1 and 4);
  end if;
end $$;

-- Para a API (PostgREST) reconhecer as colunas novas de imediato.
notify pgrst, 'reload schema';

-- Verificação (deve devolver 2 linhas):
-- select table_name, column_name from information_schema.columns
--  where table_schema = 'public'
--    and ((table_name = 'av_train_questions' and column_name = 'depth')
--      or (table_name = 'av_cohorts' and column_name = 'lessons_count'));
