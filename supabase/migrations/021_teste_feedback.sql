-- =====================================================================
-- 021_teste_feedback.sql · Verde/vermelho a cada pergunta nos testes (sem revelar a resposta certa)
-- ESTADO: RASCUNHO PARA REVISÃO. Não altera av_get_test, av_start_test nem av_submit_test.
-- Cria apenas: tabela av_test_checks (1.ª resposta de cada pergunta, bloqueada) e a função
-- av_check_test_answer(material, pergunta, resposta) → {"correct": true|false|null}.
--  · Só funciona com o teste aberto (tentativa iniciada, não abandonada, não submetida).
--  · A 1.ª resposta fica bloqueada: voltar a perguntar devolve sempre o mesmo veredicto.
--  · Nunca devolve a resposta certa. Perguntas 'sd' (autodeclaradas) devolvem correct = null.
-- Re-executável.
-- =====================================================================
begin;

do $$
begin
  if to_regprocedure('public.av_train_staff_id()') is null then
    raise exception 'Falta av_train_staff_id(): execute primeiro a 015_treino_niveis.sql';
  end if;
  if to_regclass('public.av_test_questions') is null or to_regclass('public.av_test_starts') is null
     or to_regclass('public.av_test_attempts') is null then
    raise exception 'Faltam as tabelas dos testes (av_test_questions / av_test_starts / av_test_attempts)';
  end if;
end $$;

create table if not exists public.av_test_checks (
  material_id text        not null,
  staff_id    uuid        not null,
  question_id text        not null,
  answer      jsonb       not null,
  correct     boolean,
  created_at  timestamptz not null default now(),
  primary key (material_id, staff_id, question_id)
);
alter table public.av_test_checks enable row level security;   -- sem políticas: só a função acede
revoke all on public.av_test_checks from anon, authenticated;

create or replace function public.av_check_test_answer(p_material text, p_question text, p_answer jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_staff uuid := public.av_train_staff_id();
  q       record;
  v_prev  record;
  v_ok    boolean;
begin
  if v_staff is null then raise exception 'Sem perfil de formando'; end if;
  if p_answer is null or jsonb_typeof(p_answer) = 'null' then raise exception 'Resposta em falta'; end if;

  -- só com tentativa aberta: iniciada, não abandonada e ainda sem submissão
  if not exists (select 1 from public.av_test_starts s
                  where s.material_id::text = p_material and s.staff_id = v_staff and s.abandoned_at is null)
     or exists (select 1 from public.av_test_attempts a
                  where a.material_id::text = p_material and a.staff_id = v_staff) then
    raise exception 'Teste não está aberto para si';
  end if;

  select * into q from public.av_test_questions t
   where t.id::text = p_question and t.material_id::text = p_material;
  if not found then raise exception 'Pergunta inválida'; end if;

  select * into v_prev from public.av_test_checks c
   where c.material_id = p_material and c.staff_id = v_staff and c.question_id = p_question;
  if found then return jsonb_build_object('correct', v_prev.correct); end if;   -- 1.ª resposta bloqueada

  if q.kind = 'sd' then
    v_ok := null;
  elsif q.kind = 'mc' then
    v_ok := (p_answer #>> '{}')::int = q.correct_index;
  else
    v_ok := (p_answer #>> '{}')::boolean = (q.answer is true);
  end if;

  insert into public.av_test_checks (material_id, staff_id, question_id, answer, correct)
  values (p_material, v_staff, p_question, p_answer, v_ok);
  return jsonb_build_object('correct', v_ok);
end $$;

revoke all on function public.av_check_test_answer(text, text, jsonb) from public, anon;
grant execute on function public.av_check_test_answer(text, text, jsonb) to authenticated;

commit;
