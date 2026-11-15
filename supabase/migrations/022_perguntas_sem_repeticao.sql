-- =====================================================================
-- 022_perguntas_sem_repeticao.sql · Perguntas de teste e de treino nunca iguais
-- Rede de segurança no servidor (o portal já avisa antes). Só actua em perguntas
-- NOVAS ou quando o enunciado muda; não mexe nas que já existem.
--  · av_train_questions: recusa enunciado igual ao de uma pergunta de teste (não 'sd').
--  · av_test_questions : recusa enunciado igual ao de uma pergunta do banco de treino.
--  · Ignora linhas do banco copiadas de testes (source_question_id preenchido).
-- Re-executável.
-- =====================================================================
begin;

create or replace function public.av_norm_txt(t text) returns text
language sql immutable as $$
  select regexp_replace(
    translate(lower(btrim(coalesce(t,''))),
      'áàâãäéèêëíìîïóòôõöúùûüç','aaaaaeeeeiiiiooooouuuuc'),
    '\s+',' ','g')
$$;

create or replace function public.av_train_q_no_test_dup() returns trigger
language plpgsql as $$
begin
  if new.source_question_id is null and exists (
      select 1 from public.av_test_questions t
       where t.kind <> 'sd' and public.av_norm_txt(t.statement) = public.av_norm_txt(new.statement)) then
    raise exception 'Pergunta igual à de um teste de sessão: "%"', left(new.statement, 80);
  end if;
  return new;
end $$;

create or replace function public.av_test_q_no_train_dup() returns trigger
language plpgsql as $$
begin
  if new.kind <> 'sd' and exists (
      select 1 from public.av_train_questions b
       where b.source_question_id is null
         and public.av_norm_txt(b.statement) = public.av_norm_txt(new.statement)) then
    raise exception 'Pergunta igual à do banco de treino: "%"', left(new.statement, 80);
  end if;
  return new;
end $$;

drop trigger if exists av_train_q_no_test_dup on public.av_train_questions;
create trigger av_train_q_no_test_dup before insert or update of statement
  on public.av_train_questions for each row execute function public.av_train_q_no_test_dup();

drop trigger if exists av_test_q_no_train_dup on public.av_test_questions;
create trigger av_test_q_no_train_dup before insert or update of statement
  on public.av_test_questions for each row execute function public.av_test_q_no_train_dup();

commit;
