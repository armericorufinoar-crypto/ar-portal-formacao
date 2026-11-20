-- 030_treino_liga_promocao.sql · Treino gamificado: ligas Bronze/Prata/Ouro com promoção e despromoção
-- + fuso único Africa/Luanda em todo o Treino + ranking só com pseudónimo.
-- Não toca na pauta nem em av_train_answer / av_train_state.
-- Regra: no fecho de cada semana (dom–sáb), por turma, entre quem fez XP: o terço de cima sobe, o terço de baixo desce
-- (floor(n/3); com menos de 3 pessoas ninguém muda). Bronze=1, Prata=2, Ouro=3. Liquidação feita sem agendador:
-- na 1.ª abertura da liga da turma na semana seguinte (idempotente).

create table if not exists public.av_train_tier(
  user_id uuid primary key, tier int not null default 1 check (tier between 1 and 3), updated_at timestamptz not null default now());
create table if not exists public.av_train_tier_week(
  cohort_id uuid not null, week_start date not null, settled_at timestamptz not null default now(), primary key(cohort_id,week_start));
create table if not exists public.av_train_tier_log(
  user_id uuid not null, week_start date not null, from_tier int not null, to_tier int not null, rank int, primary key(user_id,week_start));
alter table public.av_train_tier enable row level security;
alter table public.av_train_tier_week enable row level security;
alter table public.av_train_tier_log enable row level security;
drop policy if exists tier_own on public.av_train_tier;
create policy tier_own on public.av_train_tier for select using (user_id=auth.uid());
drop policy if exists tierlog_own on public.av_train_tier_log;
create policy tierlog_own on public.av_train_tier_log for select using (user_id=auth.uid());

-- Liquida a semana wk_prev (domingo) de uma turma. Só chamada por funções definer.
create or replace function public.av_train_tier_settle(p_cohort uuid, wk_prev date)
returns void language plpgsql security definer set search_path=public as $$
declare ins int; n int; k int;
begin
  insert into av_train_tier_week(cohort_id,week_start) values(p_cohort,wk_prev) on conflict do nothing;
  get diagnostics ins=row_count;
  if ins=0 then return; end if;
  create temp table _tw on commit drop as
    select p.user_id, coalesce(t.tier,1) as tier, sum(d.xp)::int xp, count(*) filter (where d.xp>0)::int days,
           row_number() over(order by sum(d.xp) desc, count(*) filter (where d.xp>0) desc, p.user_id) rn
    from av_profiles p join av_staff s on s.id=p.staff_id
    join av_train_xp_day d on d.user_id=p.user_id and d.day>=wk_prev and d.day<wk_prev+7 and d.xp>0
    left join av_train_tier t on t.user_id=p.user_id
    where s.cohort_id=p_cohort and p.role='collaborator'
    group by p.user_id,t.tier;
  select count(*) into n from _tw; k:=n/3;
  insert into av_train_tier_log(user_id,week_start,from_tier,to_tier,rank)
    select user_id,wk_prev,tier,
      case when rn<=k then least(3,tier+1) when rn>n-k then greatest(1,tier-1) else tier end, rn from _tw
    on conflict do nothing;
  insert into av_train_tier(user_id,tier)
    select user_id,to_tier from av_train_tier_log where week_start=wk_prev and user_id in (select user_id from _tw)
    on conflict(user_id) do update set tier=excluded.tier, updated_at=now();
  drop table if exists _tw;
end $$;
revoke all on function public.av_train_tier_settle(uuid,date) from public;

-- Liga do formando (agora volátil: pode liquidar a semana anterior). Só pseudónimo.
create or replace function public.av_train_league()
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Africa/Luanda')::date;
  wk date; coh uuid; res jsonb; mynick text; mytier int; mv jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  wk:=today-extract(dow from today)::int;
  select s.cohort_id into coh from av_profiles p join av_staff s on s.id=p.staff_id where p.user_id=uid;
  select nick into mynick from av_train_nick where user_id=uid;
  if coh is null then return jsonb_build_object('week_start',wk,'rows','[]'::jsonb,'nick',mynick,'tier',1,'moved',null); end if;
  perform av_train_tier_settle(coh,wk-7);
  select coalesce(tier,1) into mytier from av_train_tier where user_id=uid; mytier:=coalesce(mytier,1);
  select jsonb_build_object('from',from_tier,'to',to_tier,'rank',rank,'week_start',week_start) into mv
    from av_train_tier_log where user_id=uid and week_start=wk-7;
  with mem as (
    select p.user_id from av_profiles p join av_staff s on s.id=p.staff_id
    where s.cohort_id=coh and p.role='collaborator'),
  agg as (
    select m.user_id,coalesce(sum(d.xp),0)::int xp,count(*) filter (where d.xp>0)::int days
    from mem m left join av_train_xp_day d on d.user_id=m.user_id and d.day>=wk and d.day<wk+7
    group by m.user_id),
  ranked as (
    select a.*,n.nick,coalesce(t.tier,1) tier,rank() over(order by a.xp desc,a.days desc) rk from agg a
    left join av_train_nick n on n.user_id=a.user_id
    left join av_train_tier t on t.user_id=a.user_id
    where a.xp>0 or a.user_id=uid)
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank',rk,'xp',xp,'days',days,'me',(user_id=uid),'tier',tier,
    'name',coalesce(nick,'Formando '||upper(substr(md5(user_id::text),1,4)))) order by rk,user_id),'[]'::jsonb)
  into res from ranked;
  return jsonb_build_object('week_start',wk,'rows',res,'nick',mynick,'tier',mytier,'moved',mv);
end $$;
revoke all on function public.av_train_league() from public;
grant execute on function public.av_train_league() to authenticated;

-- Liga para o formador/admin: pseudónimo em 'name'; 'real' (primeiro nome + inicial) só aqui, para a cerimónia.
create or replace function public.av_train_league_cohort(p_cohort uuid, p_back int default 0)
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Africa/Luanda')::date; wk date; res jsonb;
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
    select a.*,n.nick,coalesce(t.tier,1) tier,rank() over(order by a.xp desc,a.days desc) rk from agg a
    left join av_train_nick n on n.user_id=a.user_id
    left join av_train_tier t on t.user_id=a.user_id where a.xp>0)
  select coalesce(jsonb_agg(jsonb_build_object('rank',rk,'xp',xp,'days',days,'tier',tier,
     'name',coalesce(nick,'Formando '||upper(substr(md5(user_id::text),1,4))),
     'real',split_part(btrim(full_name),' ',1)||case when position(' ' in btrim(full_name))>0
       then ' '||left(regexp_replace(btrim(full_name),'^.*\s',''),1)||'.' else '' end) order by rk,full_name),'[]'::jsonb)
  into res from ranked;
  return jsonb_build_object('week_start',wk,'rows',res);
end $$;
revoke all on function public.av_train_league_cohort(uuid,int) from public;
grant execute on function public.av_train_league_cohort(uuid,int) to authenticated;

-- Fuso Africa/Luanda nas restantes funções do Treino (cópias das migrações 025 e 029, só muda o fuso)
create or replace function public.av_train_answer_xp(p_question uuid, p_answer jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid:=auth.uid(); d jsonb; ok boolean; dep int; base int; mult numeric; gain int:=0;
  today date:=(now() at time zone 'Africa/Luanda')::date;
  cap constant int:=300; cur_xp int; cur_combo int; newc int; ins int; bonus int:=0; tot int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  d:=public.av_train_answer(p_question,p_answer);
  ok:=coalesce((d->>'correct')::boolean,false);
  insert into public.av_train_xp_day(user_id,day) values(uid,today) on conflict do nothing;
  select xp,combo into cur_xp,cur_combo from public.av_train_xp_day where user_id=uid and day=today for update;
  newc:=case when ok then cur_combo+1 else 0 end;
  mult:=case when newc>=5 then 1.5 when newc>=3 then 1.2 else 1 end;
  if ok then
    select coalesce(depth,1) into dep from public.av_train_questions where id=p_question;
    base:=case coalesce(dep,1) when 1 then 10 when 2 then 12 when 3 then 15 else 20 end;
    gain:=round(base*mult);
  end if;
  insert into public.av_train_xp_log(user_id,day,question_id,xp) values(uid,today,p_question,0)
    on conflict do nothing;
  get diagnostics ins=row_count;
  if ins=0 then gain:=0; newc:=cur_combo; mult:=1; end if;       -- pergunta já pontuada hoje
  if ins=1 and coalesce((d->>'completed')::boolean,false) then
    bonus:=10+case when (d->>'correct_total')=(d->>'answered') then 5 else 0 end;
  end if;
  tot:=least(gain+bonus,greatest(0,cap-cur_xp));                 -- limite diário
  update public.av_train_xp_day set xp=xp+tot,combo=newc,best_combo=greatest(best_combo,newc)
    where user_id=uid and day=today returning xp into cur_xp;
  update public.av_train_xp_log set xp=gain where user_id=uid and day=today and question_id=p_question and ins=1;
  return d||jsonb_build_object('xp_gain',least(gain,tot),'xp_bonus',greatest(0,tot-least(gain,tot)),
    'xp_today',cur_xp,'combo',newc,'mult',mult,'xp_cap',cap,'xp_capped',(cur_xp>=cap));
end $$;
revoke all on function public.av_train_answer_xp(uuid,jsonb) from public;
grant execute on function public.av_train_answer_xp(uuid,jsonb) to authenticated;

create or replace function public.av_train_xp_me()
returns jsonb language sql security definer set search_path=public stable as $$
  select jsonb_build_object(
    'today',coalesce((select xp from av_train_xp_day where user_id=auth.uid() and day=(now() at time zone 'Africa/Luanda')::date),0),
    'total',coalesce((select sum(xp) from av_train_xp_day where user_id=auth.uid()),0),
    'cap',300)
$$;
grant execute on function public.av_train_xp_me() to authenticated;

create or replace function public.av_train_quest_claim(p_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Africa/Luanda')::date;
  t_xp int:=0; t_ans int:=0; t_combo int:=0; ok boolean:=false; b int; ins int; xpn int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select coalesce(xp,0),coalesce(best_combo,0) into t_xp,t_combo from av_train_xp_day where user_id=uid and day=today;
  t_xp:=coalesce(t_xp,0); t_combo:=coalesce(t_combo,0);
  select count(*) into t_ans from av_train_xp_log where user_id=uid and day=today;
  if p_id='ans10' then ok:=t_ans>=10; b:=10;
  elsif p_id='combo5' then ok:=t_combo>=5; b:=10;
  elsif p_id='xp100' then ok:=t_xp>=100; b:=15;
  else raise exception 'missão desconhecida'; end if;
  if not ok then return jsonb_build_object('claimed',false,'reason','missão por cumprir'); end if;
  insert into av_train_quest_claim(user_id,day,quest_id,xp) values(uid,today,p_id,b) on conflict do nothing;
  get diagnostics ins=row_count;
  if ins=0 then return jsonb_build_object('claimed',false,'reason','já recebido'); end if;
  insert into av_train_xp_day(user_id,day,xp) values(uid,today,b)
    on conflict(user_id,day) do update set xp=av_train_xp_day.xp+b returning xp into xpn;
  return jsonb_build_object('claimed',true,'xp',b,'xp_today',xpn);
end $$;

create or replace function public.av_train_quests()
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Africa/Luanda')::date;
  t_xp int; t_ans int; t_combo int; tot_xp int; tot_days int; tot_ans int; best int; cap_days int;
  cl text[];
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select coalesce(xp,0),coalesce(best_combo,0) into t_xp,t_combo from av_train_xp_day where user_id=uid and day=today;
  t_xp:=coalesce(t_xp,0); t_combo:=coalesce(t_combo,0);
  select count(*) into t_ans from av_train_xp_log where user_id=uid and day=today;
  select coalesce(sum(xp),0),count(*) filter (where xp>0),coalesce(max(best_combo),0),count(*) filter (where xp>=300)
    into tot_xp,tot_days,best,cap_days from av_train_xp_day where user_id=uid;
  select count(*) into tot_ans from av_train_xp_log where user_id=uid;
  select coalesce(array_agg(quest_id),'{}') into cl from av_train_quest_claim where user_id=uid and day=today;
  return jsonb_build_object(
   'quests',jsonb_build_array(
     jsonb_build_object('id','ans10','title','Responder 10 perguntas','cur',least(t_ans,10),'goal',10,'bonus',10,'claimed','ans10'=any(cl)),
     jsonb_build_object('id','combo5','title','Acertar 5 seguidas','cur',least(t_combo,5),'goal',5,'bonus',10,'claimed','combo5'=any(cl)),
     jsonb_build_object('id','xp100','title','Ganhar 100 XP hoje','cur',least(t_xp,100),'goal',100,'bonus',15,'claimed','xp100'=any(cl))),
   'badges',jsonb_build_array(
     jsonb_build_object('id','first','title','Primeiro passo','desc','Responder à primeira pergunta','ok',tot_ans>=1),
     jsonb_build_object('id','xp100','title','100 XP','desc','Somar 100 XP','ok',tot_xp>=100),
     jsonb_build_object('id','xp500','title','500 XP','desc','Somar 500 XP','ok',tot_xp>=500),
     jsonb_build_object('id','xp1000','title','1000 XP','desc','Somar 1000 XP','ok',tot_xp>=1000),
     jsonb_build_object('id','combo10','title','Imparável','desc','10 certas seguidas num dia','ok',best>=10),
     jsonb_build_object('id','days7','title','Constante','desc','7 dias com XP','ok',tot_days>=7),
     jsonb_build_object('id','cap','title','Dia cheio','desc','Atingir o limite diário de XP','ok',cap_days>=1)),
   'stats',jsonb_build_object('xp_total',tot_xp,'days',tot_days,'answers',tot_ans));
end $$;

grant execute on function public.av_train_quest_claim(text) to authenticated;
grant execute on function public.av_train_quests() to authenticated;
