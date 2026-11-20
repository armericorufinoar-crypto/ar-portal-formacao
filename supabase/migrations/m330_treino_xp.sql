-- 025_treino_xp.sql · Treino gamificado, fase 1: XP calculado no servidor.
-- Não altera av_train_answer nem a pauta. Cria um invólucro av_train_answer_xp
-- que chama a função existente e atribui XP a partir do resultado dela.

create table if not exists public.av_train_xp_day(
  user_id uuid not null,
  day date not null,
  xp int not null default 0,
  combo int not null default 0,
  best_combo int not null default 0,
  primary key(user_id,day)
);
create table if not exists public.av_train_xp_log(
  user_id uuid not null,
  day date not null,
  question_id uuid not null,
  xp int not null default 0,
  created_at timestamptz not null default now(),
  primary key(user_id,day,question_id)
);
alter table public.av_train_xp_day enable row level security;
alter table public.av_train_xp_log enable row level security;
drop policy if exists xp_day_own on public.av_train_xp_day;
create policy xp_day_own on public.av_train_xp_day for select using (user_id=auth.uid());
drop policy if exists xp_log_own on public.av_train_xp_log;
create policy xp_log_own on public.av_train_xp_log for select using (user_id=auth.uid());

create or replace function public.av_train_answer_xp(p_question uuid, p_answer jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid:=auth.uid(); d jsonb; ok boolean; dep int; base int; mult numeric; gain int:=0;
  today date:=(now() at time zone 'Europe/Lisbon')::date;
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
    'today',coalesce((select xp from av_train_xp_day where user_id=auth.uid() and day=(now() at time zone 'Europe/Lisbon')::date),0),
    'total',coalesce((select sum(xp) from av_train_xp_day where user_id=auth.uid()),0),
    'cap',300)
$$;
grant execute on function public.av_train_xp_me() to authenticated;
