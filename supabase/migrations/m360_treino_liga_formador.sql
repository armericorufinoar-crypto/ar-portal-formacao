-- 028_treino_liga_formador.sql · Liga por turma para o formador/admin (cerimónia de sábado).
-- p_back: 0 = esta semana, 1 = semana passada. Só admin e formador.
create or replace function public.av_train_league_cohort(p_cohort uuid, p_back int default 0)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Europe/Lisbon')::date; wk date; res jsonb;
begin
  if uid is null or not exists(select 1 from av_profiles where user_id=uid and role in ('admin','trainer')) then
    raise exception 'sem permissão';
  end if;
  wk:=today-extract(dow from today)::int-7*greatest(0,least(coalesce(p_back,0),12));
  with mem as (
    select p.user_id,s.full_name from av_profiles p join av_staff s on s.id=p.staff_id
    where s.cohort_id=p_cohort and p.role='collaborator'),
  agg as (
    select m.user_id,m.full_name,coalesce(sum(d.xp),0)::int xp,count(*) filter (where d.xp>0)::int days
    from mem m left join av_train_xp_day d on d.user_id=m.user_id and d.day>=wk and d.day<wk+7
    group by m.user_id,m.full_name),
  ranked as (
    select a.*,n.nick,rank() over(order by a.xp desc,a.days desc) rk from agg a
    left join av_train_nick n on n.user_id=a.user_id where a.xp>0)
  select coalesce(jsonb_agg(jsonb_build_object('rank',rk,'xp',xp,'days',days,
     'name',coalesce(nick,split_part(btrim(full_name),' ',1)||case when position(' ' in btrim(full_name))>0
       then ' '||left(regexp_replace(btrim(full_name),'^.*\s',''),1)||'.' else '' end)) order by rk,full_name),'[]'::jsonb)
  into res from ranked;
  return jsonb_build_object('week_start',wk,'rows',res);
end $$;
revoke all on function public.av_train_league_cohort(uuid,int) from public;
grant execute on function public.av_train_league_cohort(uuid,int) to authenticated;
