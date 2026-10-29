-- 016: o formando vê as suas respostas logo após submeter um diagnóstico inicial (sem nota).
-- A chave certa (V/F e escolha múltipla) só é devolvida depois da data de fecho, como nos outros testes.
-- Só redefine av_get_test; não altera tabelas, notas, políticas RLS nem a ponderação 60/40.
-- Pré-requisito: 015_perguntas_autodeclaradas_diagnostico.sql (coluna test_purpose).
begin;

create or replace function public.av_get_test(p_material uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_staff uuid := public.av_test_caller_staff();
  m public.av_session_materials%rowtype;
  a public.av_test_attempts%rowtype;
  v_closed boolean;
begin
  select * into m from public.av_session_materials where id=p_material and kind='teste';
  if not found then raise exception 'Teste não encontrado.'; end if;
  v_closed := m.closes_at is not null and now() >= m.closes_at;
  select * into a from public.av_test_attempts where material_id=p_material and staff_id=v_staff;
  if found then
    return jsonb_build_object('done',true,'score',a.score,'correct',a.correct,'total',a.total,'purpose',m.test_purpose,
      'review',case when v_closed or m.test_purpose='diagnostico' then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'statement',q.statement,'kind',q.kind,'options',q.options,
          'answer',case when not v_closed then null when q.kind='mc' then to_jsonb(q.correct_index) when q.kind='vf' then to_jsonb(q.answer) else null end,
          'mine',a.answers->(q.id::text)
        ) order by q.position),'[]'::jsonb) from public.av_test_questions q where q.material_id=p_material
      ) end);
  end if;
  if m.opens_at is not null and now()<m.opens_at then raise exception 'Este teste ainda não está aberto.'; end if;
  if v_closed then raise exception 'Este teste já está fechado.'; end if;
  return jsonb_build_object('done',false,'purpose',m.test_purpose,'questions',(
    select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'kind',q.kind,'statement',q.statement,'options',q.options) order by q.position),'[]'::jsonb)
    from public.av_test_questions q where q.material_id=p_material
  ));
end $$;

commit;
