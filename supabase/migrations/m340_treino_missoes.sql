-- 026_treino_missoes.sql · Treino gamificado, fase 3: missões diárias e medalhas.
-- Tudo calculado no servidor a partir das tabelas de XP da migração 025. Só leitura.
create or replace function public.av_train_quests()
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Europe/Lisbon')::date;
  t_xp int; t_ans int; t_combo int; tot_xp int; tot_days int; tot_ans int; best int; cap_days int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select coalesce(xp,0),coalesce(best_combo,0) into t_xp,t_combo from av_train_xp_day where user_id=uid and day=today;
  t_xp:=coalesce(t_xp,0); t_combo:=coalesce(t_combo,0);
  select count(*) into t_ans from av_train_xp_log where user_id=uid and day=today;
  select coalesce(sum(xp),0),count(*) filter (where xp>0),coalesce(max(best_combo),0),count(*) filter (where xp>=300)
    into tot_xp,tot_days,best,cap_days from av_train_xp_day where user_id=uid;
  select count(*) into tot_ans from av_train_xp_log where user_id=uid;
  return jsonb_build_object(
   'quests',jsonb_build_array(
     jsonb_build_object('id','ans10','title','Responder 10 perguntas','cur',least(t_ans,10),'goal',10,'bonus',0),
     jsonb_build_object('id','combo5','title','Acertar 5 seguidas','cur',least(t_combo,5),'goal',5,'bonus',0),
     jsonb_build_object('id','xp100','title','Ganhar 100 XP hoje','cur',least(t_xp,100),'goal',100,'bonus',0)),
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
revoke all on function public.av_train_quests() from public;
grant execute on function public.av_train_quests() to authenticated;
