-- 018_treino_trilha.sql
-- Trilha de evolução do Treino: devolve ao formando as aulas da sua turma e os dias de treino já feitos.
-- Pressupostos (confirme nos esquemas 015 a 017 antes de executar):
--   av_profiles(user_id, staff_id)            -- como lido em boot()
--   av_staff(id, cohort_id)
--   av_cohort_aulas(cohort_id, lesson_no, theme, lesson_date)
--   av_train_days(staff_id, day date, answered int, correct int, completed boolean)
-- Se algum nome for diferente, ajuste só as colunas indicadas abaixo.

create or replace function public.av_train_trail()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_staff uuid;
  v_coh   uuid;
begin
  select p.staff_id into v_staff from av_profiles p where p.user_id = auth.uid();
  if v_staff is null then
    return jsonb_build_object('aulas', '[]'::jsonb, 'days', '[]'::jsonb);
  end if;

  select s.cohort_id into v_coh from av_staff s where s.id = v_staff;

  return jsonb_build_object(
    'aulas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'lesson_no', a.lesson_no,
               'theme', a.theme,
               'lesson_date', a.lesson_date) order by a.lesson_no)
      from av_cohort_aulas a
      where a.cohort_id = v_coh), '[]'::jsonb),
    'days', coalesce((
      select jsonb_agg(jsonb_build_object(
               'day', d.day,
               'answered', d.answered,
               'correct', d.correct,
               'completed', d.completed) order by d.day)
      from av_train_days d
      where d.staff_id = v_staff), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.av_train_trail() from public;
grant execute on function public.av_train_trail() to authenticated;
