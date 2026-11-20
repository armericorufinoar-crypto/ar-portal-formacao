-- 007_areas_de_acesso.sql
-- Áreas de formação a que cada colaborador tem acesso (definidas na ficha do colaborador).
-- Sem nenhuma área marcada, o colaborador não vê sessões, materiais nem testes.
-- Esta migração: coluna av_staff.areas, função av_has_area() e verificação de área nos testes.
-- As políticas de sessões, materiais e ficheiros ficam para a migração 008.
-- Repetível sem erro. Corre numa só transacção.
begin;

alter table public.av_staff add column if not exists areas text[] not null default '{}';

-- Verdadeiro se o utilizador autenticado é colaborador activo com acesso à área indicada.
create or replace function public.av_has_area(p_area text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from public.av_profiles p
      join public.av_staff s on s.id = p.staff_id
     where p.user_id = auth.uid() and p.role = 'collaborator'
       and s.status is distinct from 'Inactivo'
       and p_area = any (s.areas));
$$;
revoke all on function public.av_has_area(text) from public, anon;
grant execute on function public.av_has_area(text) to authenticated;

create or replace function public.av_get_test(p_material uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_staff  uuid := public.av_test_caller_staff();
  m        public.av_session_materials%rowtype;
  a        public.av_test_attempts%rowtype;
begin
  select * into m from public.av_session_materials where id = p_material and kind = 'teste';
  if not found then raise exception 'Teste não encontrado.'; end if;
  if not exists (select 1 from public.av_sessions s
                  join public.av_staff st on st.id = v_staff
                 where s.id = m.session_id and s.area = any (st.areas)) then
    raise exception 'Sem acesso a este teste.';
  end if;

  select * into a from public.av_test_attempts
   where material_id = p_material and staff_id = v_staff;
  if found then
    return jsonb_build_object(
      'done', true, 'score', a.score, 'correct', a.correct, 'total', a.total,
      'review', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'statement', q.statement,
                 'kind', q.kind,
                 'options', q.options,
                 'answer', case when q.kind = 'mc' then to_jsonb(q.correct_index) else to_jsonb(q.answer) end,
                 'mine', a.answers -> (q.id::text)
               ) order by q.position), '[]'::jsonb)
          from public.av_test_questions q where q.material_id = p_material));
  end if;

  if m.opens_at is not null and now() < m.opens_at then
    raise exception 'Este teste ainda não está aberto.';
  end if;
  if m.closes_at is not null and now() >= m.closes_at then
    raise exception 'Este teste já está fechado.';
  end if;

  return jsonb_build_object('done', false, 'questions', (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', q.id, 'kind', q.kind, 'statement', q.statement, 'options', q.options
           ) order by q.position), '[]'::jsonb)
      from public.av_test_questions q where q.material_id = p_material));
end $$;

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
  if not exists (select 1 from public.av_sessions s
                  join public.av_staff st on st.id = v_staff
                 where s.id = m.session_id and s.area = any (st.areas)) then
    raise exception 'Sem acesso a este teste.';
  end if;
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

revoke all on function public.av_get_test(uuid)           from public, anon;
revoke all on function public.av_submit_test(uuid, jsonb) from public, anon;
grant execute on function public.av_get_test(uuid)           to authenticated;
grant execute on function public.av_submit_test(uuid, jsonb) to authenticated;

commit;
