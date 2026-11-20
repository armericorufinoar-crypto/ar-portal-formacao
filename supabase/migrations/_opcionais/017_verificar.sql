-- =====================================================================
-- 017_verificar.sql  ·  Verificação da fase 2 (corre DEPOIS de executar a 017)
-- Não deixa nada na base de dados: cria dados de teste, corre os passos e REVERTE TUDO.
-- O SQL Editor vai mostrar um ERRO no fim. É intencional: é assim que o relatório sai e que
-- a transacção é desfeita. Lê a mensagem: cada linha é «OK» ou «FALHOU».
-- Se o editor deixar a transacção aberta, corre «rollback;» sozinho numa execução à parte.
--
-- Usa o primeiro formando activo com perfil de entrada preenchido (escolha automática).
-- Corre de preferência num dia que não seja sábado (no sábado só testa o dia de descanso).
-- Simula «amanhã» deslocando para trás os registos de teste; nunca altera a hora do servidor.
-- Não toca em av_test_*: compara uma impressão digital dessas tabelas antes e depois.
-- =====================================================================
begin;

create temp table zz_res (n serial, passo text, ok boolean, info text);
create temp table zz_snap as
select (select count(*) from public.av_test_attempts) as a_n,
       (select md5(coalesce(string_agg(t::text, '' order by t::text), '')) from public.av_test_attempts t) as a_h,
       (select md5(coalesce(string_agg(t::text, '' order by t::text), '')) from public.av_test_questions t) as q_h;

-- Resposta certa (ou deliberadamente errada) para um item de teste.
create function pg_temp.zz_ans(p_q uuid, p_wrong boolean) returns jsonb
language plpgsql as $$
declare q public.av_train_questions%rowtype;
begin
  select * into q from public.av_train_questions where id = p_q;
  if q.kind = 'vf' then
    return to_jsonb(case when p_wrong then not q.answer_bool else q.answer_bool end);
  elsif q.kind in ('mc','case') then
    return to_jsonb(case when p_wrong then (q.correct_index + 1) % jsonb_array_length(q.options) else q.correct_index end);
  elsif q.kind = 'num' then
    return to_jsonb(case when p_wrong then q.expected_value + 1000 else q.expected_value end);
  else
    return to_jsonb(case when p_wrong
      then (select array_agg(t.x order by t.ord desc) from unnest(q.correct_order) with ordinality as t(x, ord))
      else q.correct_order end);
  end if;
end $$;

-- Desloca para trás n dias tudo o que é do formando (simula a passagem dos dias).
-- Dois passos para não bater nas chaves únicas.
create function pg_temp.zz_shift(p_staff uuid, p_n int) returns void
language plpgsql as $$
begin
  update public.av_train_items set day = day - 10000 where staff_id = p_staff;
  update public.av_train_items set day = day + (10000 - p_n) where staff_id = p_staff;
  update public.av_train_days  set day = day - 10000 where staff_id = p_staff;
  update public.av_train_days  set day = day + (10000 - p_n) where staff_id = p_staff;
  update public.av_train_progress set next_due = next_due - p_n where staff_id = p_staff and next_due is not null;
end $$;

-- Um dia de treino feito como formando (role authenticated). p_wrong_pos = posição (1..n) a errar; 0 = nenhuma.
create function pg_temp.zz_day(p_user uuid, p_wrong_pos int) returns jsonb
language plpgsql as $$
declare v_s jsonb; v_it jsonb; v_a jsonb; v_wrong uuid;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', p_user::text, true);
  set local role authenticated;
  v_s := public.av_train_session();
  reset role;
  if p_wrong_pos > 0 then v_wrong := (v_s->'items'->(p_wrong_pos - 1)->>'id')::uuid; end if;
  for v_it in select e from jsonb_array_elements(v_s->'items') e loop
    continue when (v_it->>'answered')::boolean;
    v_a := pg_temp.zz_ans((v_it->>'id')::uuid, (v_it->>'id')::uuid is not distinct from v_wrong);
    set local role authenticated;
    perform public.av_train_answer((v_it->>'id')::uuid, v_a);
    reset role;
  end loop;
  return jsonb_build_object('session', v_s, 'wrong_id', v_wrong);
end $$;

-- Sequência com dias artificiais em 2020 (5 jan 2020 = domingo; 11 e 18 jan = sábados).
create function pg_temp.zz_streak(p_staff uuid, p_q uuid, p_days date[], p_today date) returns int
language plpgsql as $$
begin
  delete from public.av_train_days  where staff_id = p_staff and day < date '2021-01-01';
  delete from public.av_train_items where staff_id = p_staff and day < date '2021-01-01';
  insert into public.av_train_items (staff_id, day, position, question_id, source)
  values (p_staff, date '2020-01-05', 1, p_q, 'tema');
  insert into public.av_train_days (staff_id, day, answered, correct, completed)
  select p_staff, d, 1, 1, true from unnest(p_days) d;
  return public.av_train_streak(p_staff, p_today);
end $$;

do $$
declare
  v_user uuid; v_staff uuid; v_lvl text; v_coh uuid; v_qa uuid; v_other uuid;
  v_today date := public.av_train_today();
  v_dow int := extract(dow from public.av_train_today())::int;
  v_cfg public.av_train_settings%rowtype;
  v_out jsonb; v_s jsonb; v_r jsonb; v_wrong uuid; v_exp date; v_size int;
  v_prog public.av_train_progress%rowtype; v_day public.av_train_days%rowtype;
  v_cnt bigint; v_fail boolean; v_msg text; v_a jsonb;
  v_qh text; v_ah text; v_an bigint;
begin
  select p.user_id, p.staff_id, sp.level_final into v_user, v_staff, v_lvl
    from public.av_profiles p
    join public.av_student_profile sp on sp.staff_id = p.staff_id
    join public.av_staff s on s.id = p.staff_id
   where p.role = 'collaborator' and s.status = 'Activo'
   limit 1;
  if v_user is null then
    insert into zz_res(passo, ok, info) values ('Formando de teste', false, 'não há formando activo com perfil de entrada preenchido');
  else
    select * into v_cfg from public.av_train_settings where id = 1;
    v_size := (v_cfg.session_sizes -> v_lvl ->> 'questions')::int;
    insert into zz_res(passo, ok, info) values ('Formando de teste', true, 'nível ' || v_lvl || ', hoje ' || v_today || ' (dow ' || v_dow || ')');

    -- Dados de teste: turma, tema e perguntas dos 5 tipos (mais 40 mc de enchimento)
    insert into public.av_cohorts (name, levels, current_theme, active)
    values ('ZZ-TESTE', array[v_lvl], 'zz_tema', true) returning id into v_coh;
    update public.av_staff set cohort_id = v_coh where id = v_staff;

    insert into public.av_train_questions (area, theme, levels, kind, statement, answer_bool, explanation)
    values ('zz', 'zz_tema', array[v_lvl], 'vf', 'ZZ vf 1', true, 'ZZEXPL');
    insert into public.av_train_questions (area, theme, levels, kind, statement, options, correct_index, explanation)
    values ('zz', 'zz_tema', array[v_lvl], 'mc', 'ZZ mc A', '["a","b","c"]'::jsonb, 1, 'ZZEXPL');
    insert into public.av_train_questions (area, theme, levels, kind, statement, expected_value, tolerance, explanation)
    values ('zz', 'zz_tema', array[v_lvl], 'num', 'ZZ num 1', 125.5, 0.5, 'ZZEXPL');
    insert into public.av_train_questions (area, theme, levels, kind, statement, options, correct_order, explanation)
    values ('zz', 'zz_tema', array[v_lvl], 'order', 'ZZ order 1', '["passo A","passo B","passo C","passo D"]'::jsonb, '{0,1,2,3}', 'ZZEXPL');
    insert into public.av_train_questions (area, theme, levels, kind, statement, case_context, options, correct_index, explanation)
    values ('zz', 'zz_tema', array[v_lvl], 'case', 'ZZ case 1', 'ZZ contexto', '["x","y","z"]'::jsonb, 2, 'ZZEXPL');
    insert into public.av_train_questions (area, theme, levels, kind, statement, options, correct_index, explanation)
    select 'zz', 'zz_tema', array[v_lvl], 'mc', 'ZZ mc ' || g, '["a","b","c"]'::jsonb, g % 3, 'ZZEXPL'
      from generate_series(1, 40) g;
    select id into v_qa from public.av_train_questions where theme = 'zz_tema' limit 1;

    -- ===== A. Sequência (independente do dia da semana) =====
    v_cnt := pg_temp.zz_streak(v_staff, v_qa,
      array['2020-01-05','2020-01-06','2020-01-07','2020-01-08','2020-01-09','2020-01-10','2020-01-12','2020-01-13']::date[], date '2020-01-14');
    insert into zz_res(passo, ok, info) values ('Sequência sem falhas, sábado neutro (esperado 8)', v_cnt = 8, 'obtido ' || v_cnt);
    v_cnt := pg_temp.zz_streak(v_staff, v_qa,
      array['2020-01-05','2020-01-06','2020-01-08','2020-01-09','2020-01-10','2020-01-12','2020-01-13']::date[], date '2020-01-14');
    insert into zz_res(passo, ok, info) values ('Um dia falhado é tolerado (esperado 7)', v_cnt = 7, 'obtido ' || v_cnt);
    v_cnt := pg_temp.zz_streak(v_staff, v_qa,
      array['2020-01-05','2020-01-06','2020-01-08','2020-01-10','2020-01-12','2020-01-13']::date[], date '2020-01-14');
    insert into zz_res(passo, ok, info) values ('Segundo falhado na mesma janela volta a zero (esperado 3)', v_cnt = 3, 'obtido ' || v_cnt);
    v_cnt := pg_temp.zz_streak(v_staff, v_qa,
      array['2020-01-05','2020-01-07','2020-01-08','2020-01-09','2020-01-10','2020-01-12','2020-01-13','2020-01-15','2020-01-16','2020-01-17']::date[], date '2020-01-19');
    insert into zz_res(passo, ok, info) values ('Dois falhados com 8 dias de distância: ambos tolerados (esperado 10)', v_cnt = 10, 'obtido ' || v_cnt);
    v_cnt := pg_temp.zz_streak(v_staff, v_qa,
      array['2020-01-05','2020-01-06','2020-01-07','2020-01-08','2020-01-09','2020-01-10','2020-01-12','2020-01-13','2020-01-14']::date[], date '2020-01-14');
    insert into zz_res(passo, ok, info) values ('Hoje concluído conta (esperado 9)', v_cnt = 9, 'obtido ' || v_cnt);
    delete from public.av_train_days  where staff_id = v_staff and day < date '2021-01-01';
    delete from public.av_train_items where staff_id = v_staff and day < date '2021-01-01';

    -- ===== B. Sessão e banco de erros =====
    if v_dow = 6 then
      perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', v_user::text, true);
      set local role authenticated;
      v_s := public.av_train_session();
      reset role;
      insert into zz_res(passo, ok, info) values ('Sábado: sem sessão (rest = true)', coalesce((v_s->>'rest')::boolean, false), 'passos do banco de erros não testados hoje; volta a correr noutro dia');
    else
      -- Dia 1: errar a 1.ª pergunta servida
      v_out := pg_temp.zz_day(v_user, 1);
      v_s := v_out->'session'; v_wrong := (v_out->>'wrong_id')::uuid;
      insert into zz_res(passo, ok, info) values ('Dia 1: nº de perguntas = tamanho do nível',
        jsonb_array_length(v_s->'items') = v_size, 'servidas ' || jsonb_array_length(v_s->'items') || ', esperadas ' || v_size);
      insert into zz_res(passo, ok, info) values ('Dia 1: a resposta certa NÃO vem no payload da sessão',
        v_s::text !~* '(correct_index|answer_bool|expected_value|correct_order|explanation|scoring_key|tolerance|ZZEXPL)', null);
      insert into zz_res(passo, ok, info) values ('Dia 1: perguntas «order» chegam com {i,t} baralhado',
        not exists (select 1 from jsonb_array_elements(v_s->'items') e
                     where e->>'kind' = 'order' and (e->'options'->0->'i') is null), null);

      perform set_config('request.jwt.claims', json_build_object('sub', v_user, 'role', 'authenticated')::text, true);
      perform set_config('request.jwt.claim.sub', v_user::text, true);

      set local role authenticated;
      select count(*) into v_cnt from public.av_train_questions;
      reset role;
      insert into zz_res(passo, ok, info) values ('Formando não lê av_train_questions (RLS)', v_cnt = 0, 'linhas visíveis ' || v_cnt);

      v_fail := false;
      set local role authenticated;
      begin
        insert into public.av_train_progress (staff_id, question_id, streak) values (v_staff, v_qa, 9);
      exception when others then v_fail := true;
      end;
      reset role;
      insert into zz_res(passo, ok, info) values ('Formando não escreve em av_train_progress', v_fail, null);

      v_fail := false; v_cnt := 0;
      set local role authenticated;
      begin
        update public.av_train_days set completed = true where staff_id = v_staff;
        get diagnostics v_cnt = row_count;
      exception when others then v_fail := true;
      end;
      reset role;
      insert into zz_res(passo, ok, info) values ('Formando não altera av_train_days', v_fail or v_cnt = 0, 'linhas alteradas ' || v_cnt);

      select * into v_prog from public.av_train_progress where staff_id = v_staff and question_id = v_wrong;
      v_exp := v_today + (v_cfg.ladder ->> 0)::int;
      insert into zz_res(passo, ok, info) values ('Dia 1: erro entra no banco com revisão no dia seguinte',
        v_prog.streak = 0 and v_prog.next_due = v_exp and v_prog.last_result = false, 'next_due ' || v_prog.next_due || ', esperado ' || v_exp);
      select * into v_day from public.av_train_days where staff_id = v_staff and day = v_today;
      insert into zz_res(passo, ok, info) values ('Dia 1: sessão concluída quando todas respondidas',
        v_day.completed and v_day.answered = v_size, 'respondidas ' || coalesce(v_day.answered, 0));

      -- repetir resposta não conta duas vezes
      v_a := pg_temp.zz_ans(v_wrong, false);
      set local role authenticated;
      v_r := public.av_train_answer(v_wrong, v_a);
      reset role;
      select * into v_prog from public.av_train_progress where staff_id = v_staff and question_id = v_wrong;
      insert into zz_res(passo, ok, info) values ('Responder de novo não altera nada (repeat)',
        (v_r->>'repeat')::boolean and (v_r->>'correct')::boolean = false and v_prog.next_due = v_exp, null);

      -- pergunta que não foi servida hoje
      select id into v_other from public.av_train_questions
       where theme = 'zz_tema' and id not in (select question_id from public.av_train_items where staff_id = v_staff and day = v_today) limit 1;
      v_msg := null;
      set local role authenticated;
      begin
        perform public.av_train_answer(v_other, to_jsonb(true));
      exception when others then v_msg := sqlerrm;
      end;
      reset role;
      insert into zz_res(passo, ok, info) values ('Pergunta não servida é recusada', coalesce(v_msg, '') like '%pergunta_nao_servida%', v_msg);

      -- estado e meta de turma (como formando)
      set local role authenticated;
      v_r := public.av_train_state();
      reset role;
      insert into zz_res(passo, ok, info) values ('av_train_state: sessão concluída e sequência >= 1',
        (v_r->'session'->>'completed')::boolean and (v_r->>'streak')::int >= 1, 'streak ' || (v_r->>'streak'));
      set local role authenticated;
      v_r := public.av_cohort_week(null);
      reset role;
      insert into zz_res(passo, ok, info) values ('av_cohort_week: só contagens, sem nomes',
        (v_r->>'total')::int >= 1 and (select count(*) from jsonb_object_keys(v_r)) = 7, v_r::text);

      -- Dia 2 (amanhã): o erro reaparece em 1.º lugar e sobe um degrau
      perform pg_temp.zz_shift(v_staff, 1);
      v_out := pg_temp.zz_day(v_user, 0);
      v_s := v_out->'session';
      insert into zz_res(passo, ok, info) values ('Dia 2: o erro reaparece no dia seguinte, como «erro»',
        exists (select 1 from jsonb_array_elements(v_s->'items') e where e->>'id' = v_wrong::text and e->>'source' = 'erro'), null);
      select * into v_prog from public.av_train_progress where staff_id = v_staff and question_id = v_wrong;
      v_exp := v_today + (v_cfg.ladder ->> 1)::int;
      insert into zz_res(passo, ok, info) values ('Dia 2: 1.º acerto sobe para o degrau seguinte',
        v_prog.streak = 1 and v_prog.next_due = v_exp, 'streak ' || v_prog.streak || ', next_due ' || v_prog.next_due || ', esperado ' || v_exp);

      -- Dia 3 (+3 dias): 2.º acerto seguido
      perform pg_temp.zz_shift(v_staff, 3);
      v_out := pg_temp.zz_day(v_user, 0);
      v_s := v_out->'session';
      insert into zz_res(passo, ok, info) values ('Dia 3: o erro reaparece no degrau de 3 dias',
        exists (select 1 from jsonb_array_elements(v_s->'items') e where e->>'id' = v_wrong::text and e->>'source' = 'erro'), null);
      select * into v_prog from public.av_train_progress where staff_id = v_staff and question_id = v_wrong;
      if v_cfg.exit_streak = 2 then
        insert into zz_res(passo, ok, info) values ('Dia 3: dois acertos seguidos retiram a pergunta do banco',
          v_prog.streak = 2 and v_prog.next_due is null, 'streak ' || v_prog.streak || ', next_due ' || coalesce(v_prog.next_due::text, 'null'));
        perform pg_temp.zz_shift(v_staff, 1);
        v_out := pg_temp.zz_day(v_user, 0);
        v_s := v_out->'session';
        insert into zz_res(passo, ok, info) values ('Dia 4: já não volta como «erro»',
          not exists (select 1 from jsonb_array_elements(v_s->'items') e where e->>'id' = v_wrong::text and e->>'source' = 'erro'), null);
      else
        v_exp := v_today + (v_cfg.ladder ->> 2)::int;
        insert into zz_res(passo, ok, info) values ('Dia 3 (exit_streak = 3): sobe para o degrau seguinte',
          v_prog.streak = 2 and v_prog.next_due = v_exp, 'next_due ' || coalesce(v_prog.next_due::text, 'null') || ', esperado ' || v_exp);
      end if;
    end if;

    -- ===== C. Isolamento: pauta e testes ficam exactamente iguais =====
    select count(*), md5(coalesce(string_agg(t::text, '' order by t::text), '')) into v_an, v_ah from public.av_test_attempts t;
    select md5(coalesce(string_agg(t::text, '' order by t::text), '')) into v_qh from public.av_test_questions t;
    insert into zz_res(passo, ok, info)
    select 'av_test_attempts e av_test_questions intactas', (v_an = a_n and v_ah = a_h and v_qh = q_h), null from zz_snap;
  end if;

  select string_agg(case when ok then 'OK     ' else 'FALHOU ' end || passo || coalesce(' — ' || info, ''), E'\n' order by n)
    into v_msg from zz_res;
  raise exception E'VERIFICAÇÃO 017 (tudo revertido; este erro é intencional)\n%\n\nFalhas: %',
    v_msg, (select count(*) from zz_res where not ok);
end $$;

-- Se por algum motivo o bloco acima não abortar, desfaz tudo na mesma.
rollback;
