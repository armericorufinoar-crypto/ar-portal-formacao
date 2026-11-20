-- 029_treino_missoes_xp.sql · XP extra por cumprir missões diárias (reclamar 1 vez por missão e por dia).
-- O XP das missões soma ao XP do dia, fora do limite diário das respostas (limite próprio: 3 missões, 35 XP).
create table if not exists public.av_train_quest_claim(
  user_id uuid not null, day date not null, quest_id text not null, xp int not null,
  primary key(user_id,day,quest_id));
alter table public.av_train_quest_claim enable row level security;
drop policy if exists qc_own on public.av_train_quest_claim;
create policy qc_own on public.av_train_quest_claim for select using (user_id=auth.uid());

create or replace function public.av_train_quest_claim(p_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Europe/Lisbon')::date;
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
revoke all on function public.av_train_quest_claim(text) from public;
grant execute on function public.av_train_quest_claim(text) to authenticated;

-- av_train_quests passa a devolver o bónus e se já foi recebido
create or replace function public.av_train_quests()
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Europe/Lisbon')::date;
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
