-- AR Formação · Nota 0–20 em av_assessments
-- Executar no Supabase: SQL Editor > New query > Run

-- 1) Ver o estado actual (opcional): valores fora de 0–20 e restrições existentes
-- select id, staff_id, score from public.av_assessments where score < 0 or score > 20;
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--   where conrelid = 'public.av_assessments'::regclass and contype = 'c';

-- 2) (Opcional) Converter notas antigas da escala 0–100 para 0–20.
--    Só correr se TODAS as notas existentes estiverem na escala antiga.
--    Se houver mistura, converta apenas as acima de 20:
-- update public.av_assessments set score = round((score / 5.0)::numeric, 2) where score > 20;

-- 3) Remover restrições CHECK antigas que envolvam a coluna score (ex.: 0–100)
do $$
declare r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    where c.conrelid = 'public.av_assessments'::regclass
      and c.contype = 'c'
      and pg_get_constraintdef(c.oid) ilike '%score%'
  loop
    execute format('alter table public.av_assessments drop constraint %I', r.conname);
  end loop;
end $$;

-- 4) Garantir o tipo numérico com 2 casas decimais
alter table public.av_assessments
  alter column score type numeric(5,2) using score::numeric(5,2);

-- 5) Nova restrição: nota entre 0 e 20
--    (falha se ainda existirem notas fora do intervalo: corrija-as primeiro, passo 2)
alter table public.av_assessments
  add constraint av_assessments_score_0_20 check (score >= 0 and score <= 20);
