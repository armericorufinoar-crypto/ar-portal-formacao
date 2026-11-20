-- 005_correccao_imediata.sql
-- A correcção (resposta do colaborador vs. resposta certa) passa a ser devolvida
-- logo depois de submeter, sem esperar pela data de fecho do teste.
-- Substitui apenas a função av_get_test. Repetível sem erro.
begin;

create or replace function public.av_get_test(p_material uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_staff  uuid := public.av_test_caller_staff();
  m        public.av_session_materials%rowtype;
  a        public.av_test_attempts%rowtype;
begin
  select * into m from public.av_session_materials where id = p_material and kind = 'teste';
  if not found then raise exception 'Teste não encontrado.'; end if;

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

revoke all on function public.av_get_test(uuid) from public, anon;
grant execute on function public.av_get_test(uuid) to authenticated;

commit;
