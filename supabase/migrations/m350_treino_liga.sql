-- 027_treino_liga.sql · Treino gamificado, fase 4: liga semanal por turma (separada da pauta).
-- Semana = domingo a sábado (hora de Lisboa). Só mostra colegas da mesma turma.
create table if not exists public.av_train_nick(
  user_id uuid primary key,
  nick text not null check (char_length(nick) between 2 and 20)
);
alter table public.av_train_nick enable row level security;
drop policy if exists nick_own on public.av_train_nick;
create policy nick_own on public.av_train_nick for select using (user_id=auth.uid());

create or replace function public.av_train_set_nick(p_nick text)
returns void language plpgsql security definer set search_path=public as $$
declare n text:=nullif(btrim(coalesce(p_nick,'')),'');
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if n is null then delete from av_train_nick where user_id=auth.uid(); return; end if;
  if char_length(n) not between 2 and 20 then raise exception 'alcunha com 2 a 20 caracteres'; end if;
  insert into av_train_nick(user_id,nick) values(auth.uid(),n)
    on conflict(user_id) do update set nick=excluded.nick;
end $$;
revoke all on function public.av_train_set_nick(text) from public;
grant execute on function public.av_train_set_nick(text) to authenticated;

create or replace function public.av_train_league()
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Europe/Lisbon')::date;
  wk date; coh uuid; res jsonb; mynick text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  wk:=today-extract(dow from today)::int;
  select s.cohort_id into coh from av_profiles p join av_staff s on s.id=p.staff_id where p.user_id=uid;
  select nick into mynick from av_train_nick where user_id=uid;
  if coh is null then return jsonb_build_object('week_start',wk,'rows','[]'::jsonb,'nick',mynick); end if;
  with mem as (
    select p.user_id,s.full_name from av_profiles p join av_staff s on s.id=p.staff_id
    where s.cohort_id=coh and p.role='collaborator'),
  agg as (
    select m.user_id,m.full_name,coalesce(sum(d.xp),0)::int xp,count(*) filter (where d.xp>0)::int days
    from mem m left join av_train_xp_day d on d.user_id=m.user_id and d.day>=wk and d.day<wk+7
    group by m.user_id,m.full_name),
  ranked as (
    select a.*,n.nick,rank() over(order by a.xp desc,a.days desc) rk from agg a
    left join av_train_nick n on n.user_id=a.user_id
    where a.xp>0 or a.user_id=uid)
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank',rk,'xp',xp,'days',days,'me',(user_id=uid),
    'name',coalesce(nick,split_part(btrim(full_name),' ',1)||case when position(' ' in btrim(full_name))>0
       then ' '||left(regexp_replace(btrim(full_name),'^.*\s',''),1)||'.' else '' end)) order by rk,full_name),'[]'::jsonb)
  into res from ranked;
  return jsonb_build_object('week_start',wk,'rows',res,'nick',mynick);
end $$;
revoke all on function public.av_train_league() from public;
grant execute on function public.av_train_league() to authenticated;
