-- 034_treino_bonus_rever_erros.sql · +5 XP ao acertar uma pergunta do banco de erros (revisão). Idempotente.
-- Mantém tudo o resto de av_train_answer_xp (030). Não altera av_train_answer. Aplica-se uma vez por pergunta e dia,
-- dentro do limite diário de 300 XP.
create or replace function public.av_train_answer_xp(p_question uuid, p_answer jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid:=auth.uid(); d jsonb; ok boolean; dep int; base int; mult numeric; gain int:=0;
  today date:=(now() at time zone 'Africa/Luanda')::date;
  cap constant int:=300; rev boolean:=false; staff uuid; cur_xp int; cur_combo int; newc int; ins int; bonus int:=0; tot int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  -- pergunta do banco de erros (ainda por rever) e ainda não respondida hoje?
  select p.staff_id into staff from public.av_profiles p where p.user_id=uid and p.role='collaborator';
  select exists(select 1 from public.av_train_progress pr
      join public.av_train_items it on it.staff_id=pr.staff_id and it.question_id=pr.question_id and it.day=today
     where pr.staff_id=staff and pr.question_id=p_question and pr.next_due is not null and it.answered_at is null) into rev;
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
  if ins=1 and ok and rev then bonus:=bonus+5; end if;           -- bónus por rever um erro
  tot:=least(gain+bonus,greatest(0,cap-cur_xp));                 -- limite diário
  update public.av_train_xp_day set xp=xp+tot,combo=newc,best_combo=greatest(best_combo,newc)
    where user_id=uid and day=today returning xp into cur_xp;
  update public.av_train_xp_log set xp=gain where user_id=uid and day=today and question_id=p_question and ins=1;
  return d||jsonb_build_object('xp_gain',least(gain,tot),'xp_bonus',greatest(0,tot-least(gain,tot)),
    'xp_review',(ins=1 and ok and rev),'xp_today',cur_xp,'combo',newc,'mult',mult,'xp_cap',cap,'xp_capped',(cur_xp>=cap));
end $$;
revoke all on function public.av_train_answer_xp(uuid,jsonb) from public;
grant execute on function public.av_train_answer_xp(uuid,jsonb) to authenticated;
