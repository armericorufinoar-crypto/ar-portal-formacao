-- 006_nota_inteira.sql
-- A nota do teste passa a ser sempre um número inteiro de 0 a 20
-- (certas ÷ total × 20, arredondado ao inteiro mais próximo; 12,5 sobe para 13).
-- Substitui av_submit_test e arredonda as tentativas já guardadas. Repetível sem erro.
begin;

create or replace function public.av_submit_test(p_material uuid, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_staff   uuid := public.av_test_caller_staff();
  m         public.av_session_materials%rowtype;
  q         record;
  v_a       jsonb;
  v_clean   jsonb := '{}'::jsonb;
  v_total   int := 0;
  v_correct int := 0;
  v_idx     int;
  v_score   numeric(5,2);
begin
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then
    raise exception 'Respostas inválidas.';
  end if;
  select * into m from public.av_session_materials where id = p_material and kind = 'teste';
  if not found then raise exception 'Teste não encontrado.'; end if;
  if m.opens_at is not null and now() < m.opens_at then
    raise exception 'Este teste ainda não está aberto.';
  end if;
  if m.closes_at is not null and now() >= m.closes_at then
    raise exception 'Este teste já está fechado.';
  end if;
  if exists (select 1 from public.av_test_attempts
              where material_id = p_material and staff_id = v_staff) then
    raise exception 'Já submeteu este teste.';
  end if;

  for q in select * from public.av_test_questions
            where material_id = p_material order by position
  loop
    v_total := v_total + 1;
    v_a := p_answers -> (q.id::text);
    if q.kind = 'mc' then
      if v_a is null or jsonb_typeof(v_a) <> 'number' or (v_a #>> '{}') !~ '^[0-9]{1,2}$' then
        raise exception 'Responda a todas as perguntas.';
      end if;
      v_idx := (v_a #>> '{}')::int;
      if v_idx >= jsonb_array_length(q.options) then raise exception 'Resposta inválida.'; end if;
      if v_idx = q.correct_index then v_correct := v_correct + 1; end if;
    else
      if v_a is null or jsonb_typeof(v_a) <> 'boolean' then
        raise exception 'Responda a todas as perguntas.';
      end if;
      if (v_a #>> '{}')::boolean = q.answer then v_correct := v_correct + 1; end if;
    end if;
    v_clean := v_clean || jsonb_build_object(q.id::text, v_a);
  end loop;

  if v_total = 0 then raise exception 'Este teste ainda não tem perguntas.'; end if;
  v_score := round(v_correct::numeric / v_total * 20);

  begin
    insert into public.av_test_attempts (material_id, user_id, staff_id, answers, correct, total, score)
    values (p_material, auth.uid(), v_staff, v_clean, v_correct, v_total, v_score);
  exception when unique_violation then
    raise exception 'Já submeteu este teste.';
  end;

  return jsonb_build_object('score', v_score, 'correct', v_correct, 'total', v_total);
end $$;

revoke all on function public.av_submit_test(uuid, jsonb) from public, anon;
grant execute on function public.av_submit_test(uuid, jsonb) to authenticated;

update public.av_test_attempts set score = round(score) where score <> round(score);

commit;
