-- 015_perguntas_autodeclaradas_diagnostico.sql
-- Acrescenta perguntas autodeclaradas apenas em diagnósticos sem nota.
-- Não executar automaticamente: rever e aplicar primeiro em ambiente de teste.
begin;

alter table public.av_session_materials
  add column if not exists test_purpose text not null default 'tematico';

alter table public.av_session_materials drop constraint if exists av_session_materials_test_purpose_check;
alter table public.av_session_materials add constraint av_session_materials_test_purpose_check
  check (test_purpose in ('tematico','diagnostico'));

alter table public.av_test_attempts alter column score drop not null;

alter table public.av_test_questions drop constraint if exists av_test_questions_kind_check;
alter table public.av_test_questions add constraint av_test_questions_kind_check check (kind in ('vf','mc','sd'));
alter table public.av_test_questions drop constraint if exists av_test_questions_shape;
alter table public.av_test_questions add constraint av_test_questions_shape check (
  (kind = 'vf' and answer is not null and options is null and correct_index is null)
  or (kind = 'mc' and answer is null and jsonb_typeof(options) = 'array'
      and jsonb_array_length(options) between 2 and 6 and correct_index is not null
      and correct_index >= 0 and correct_index < jsonb_array_length(options))
  or (kind = 'sd' and answer is null and jsonb_typeof(options) = 'array'
      and jsonb_array_length(options) between 2 and 10 and correct_index is null)
);

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
      'review',case when v_closed then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'statement',q.statement,'kind',q.kind,'options',q.options,
          'answer',case when q.kind='mc' then to_jsonb(q.correct_index) when q.kind='vf' then to_jsonb(q.answer) else null end,
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

create or replace function public.av_submit_test(p_material uuid, p_answers jsonb)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_staff uuid := public.av_test_caller_staff();
  m public.av_session_materials%rowtype;
  q record;
  v_a jsonb;
  v_clean jsonb := '{}'::jsonb;
  v_total integer := 0;
  v_correct integer := 0;
  v_score numeric(5,2);
  v_idx integer;
  v_has_sd boolean := false;
begin
  if p_answers is null or jsonb_typeof(p_answers)<>'object' then raise exception 'Respostas inválidas.'; end if;
  select * into m from public.av_session_materials where id=p_material and kind='teste';
  if not found then raise exception 'Teste não encontrado.'; end if;
  if m.opens_at is not null and now()<m.opens_at then raise exception 'Este teste ainda não está aberto.'; end if;
  if m.closes_at is not null and now()>=m.closes_at then raise exception 'Este teste já está fechado.'; end if;
  if exists(select 1 from public.av_test_attempts where material_id=p_material and staff_id=v_staff) then raise exception 'Já submeteu este teste.'; end if;
  select exists(select 1 from public.av_test_questions where material_id=p_material and kind='sd') into v_has_sd;
  if v_has_sd and m.test_purpose<>'diagnostico' then raise exception 'Perguntas autodeclaradas só são permitidas no diagnóstico inicial.'; end if;
  if m.test_purpose='diagnostico' then v_score:=null; end if;
  for q in select * from public.av_test_questions where material_id=p_material order by position loop
    v_a:=p_answers->(q.id::text);
    if v_a is null then raise exception 'Responda a todas as perguntas.'; end if;
    if q.kind='mc' then
      if jsonb_typeof(v_a)<>'number' or (v_a#>>'{}') !~ '^[0-9]{1,2}$' then raise exception 'Resposta inválida.'; end if;
      v_idx:=(v_a#>>'{}')::integer;
      if v_idx<0 or v_idx>=jsonb_array_length(q.options) then raise exception 'Resposta inválida.'; end if;
      v_total:=v_total+1; if v_idx=q.correct_index then v_correct:=v_correct+1; end if;
    elsif q.kind='vf' then
      if jsonb_typeof(v_a)<>'boolean' then raise exception 'Resposta inválida.'; end if;
      v_total:=v_total+1; if (v_a#>>'{}')::boolean=q.answer then v_correct:=v_correct+1; end if;
    elsif q.kind='sd' then
      if jsonb_typeof(v_a)<>'string' or not exists(select 1 from jsonb_array_elements_text(q.options) o(value) where o.value=v_a#>>'{}') then
        raise exception 'Seleccione uma das opções apresentadas.';
      end if;
    else raise exception 'Tipo de pergunta não suportado.';
    end if;
    v_clean:=v_clean||jsonb_build_object(q.id::text,v_a);
  end loop;
  if not exists(select 1 from public.av_test_questions where material_id=p_material) then raise exception 'Este teste ainda não tem perguntas.'; end if;
  if m.test_purpose='tematico' then
    if v_total=0 then raise exception 'O teste temático precisa de perguntas com classificação automática.'; end if;
    v_score:=round(v_correct::numeric/v_total*20,2);
  else
    v_score:=null;
  end if;
  begin
    insert into public.av_test_attempts(material_id,user_id,staff_id,answers,correct,total,score)
    values(p_material,auth.uid(),v_staff,v_clean,v_correct,v_total,v_score);
  exception when unique_violation then raise exception 'Já submeteu este teste.';
  end;
  return jsonb_build_object('score',v_score,'correct',v_correct,'total',v_total,'purpose',m.test_purpose);
end $$;

-- Autodeclaradas não entram na métrica de acerto/erro de competências.
-- O diagnóstico continua a usar apenas perguntas objectivas associadas a competências.
create or replace function public.av_get_competency_diagnosis(p_material uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_staff uuid; v_role text; v_attempt public.av_test_attempts%rowtype; c record;
  v_answered integer; v_correct integer; v_total integer; v_pct numeric(5,2); v_level text;
  v_result jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'Sessão inválida.'; end if;
  select role,staff_id into v_role,v_staff from public.av_profiles where user_id=auth.uid();
  if v_role='collaborator' then
    if v_staff is null or v_staff<>public.av_test_caller_staff() then raise exception 'Sem acesso ao diagnóstico.'; end if;
  elsif v_role in ('admin','trainer') then
    select staff_id into v_staff from public.av_test_attempts where material_id=p_material order by submitted_at desc limit 1;
  else raise exception 'Sem acesso ao diagnóstico.'; end if;
  select * into v_attempt from public.av_test_attempts where material_id=p_material and staff_id=v_staff;
  if not found then raise exception 'Ainda não existe tentativa submetida para este teste.'; end if;
  for c in select co.id,co.code,co.name,co.reinforcement,count(q.id) filter(where q.kind in ('vf','mc'))::integer as mapped_total
    from public.av_competencies co left join public.av_test_questions q on q.competency_id=co.id and q.material_id=p_material
    where co.active=true group by co.id,co.code,co.name,co.reinforcement,co.position order by co.position,co.code loop
    select count(*)::integer,count(*) filter(where case when q.kind='mc' then v_attempt.answers->(q.id::text)=to_jsonb(q.correct_index) else v_attempt.answers->(q.id::text)=to_jsonb(q.answer) end)::integer
      into v_answered,v_correct from public.av_test_questions q where q.material_id=p_material and q.competency_id=c.id and q.kind in ('vf','mc') and v_attempt.answers ? (q.id::text);
    v_total:=coalesce(c.mapped_total,0);
    if v_answered>0 then v_pct:=round(v_correct::numeric/v_answered*100,2); v_level:=case when v_pct>=80 then 'Domínio demonstrado' when v_pct>=60 then 'Em consolidação' else 'Precisa de reforço' end;
    else v_pct:=null; v_level:='Ainda sem evidência'; end if;
    insert into public.av_competency_diagnostics(attempt_id,material_id,staff_id,competency_id,answered,correct,total_mapped,percentage,level,recommendation,calculated_at)
    values(v_attempt.id,p_material,v_staff,c.id,coalesce(v_answered,0),coalesce(v_correct,0),v_total,v_pct,v_level,c.reinforcement,now())
    on conflict(attempt_id,competency_id) do update set answered=excluded.answered,correct=excluded.correct,total_mapped=excluded.total_mapped,percentage=excluded.percentage,level=excluded.level,recommendation=excluded.recommendation,calculated_at=now();
    v_result:=v_result||jsonb_build_array(jsonb_build_object('code',c.code,'name',c.name,'answered',coalesce(v_answered,0),'correct',coalesce(v_correct,0),'total_mapped',v_total,'percentage',v_pct,'level',v_level,'recommendation',c.reinforcement));
  end loop;
  return jsonb_build_object('material_id',p_material,'attempt_id',v_attempt.id,'competencies',v_result,'certification_note_unchanged',true);
end $$;

commit;
