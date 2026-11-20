-- 035_treino_bau_diario.sql · Baú diário do Treino. Idempotente.
-- Regra: 1 baú por dia, aberto depois de concluir a sessão do dia (fuso Africa/Luanda).
-- Prémio sorteado no servidor: XP (45%), Moedas de Desconto (30%), proteção da sequência (15%), Playbook (10%).
-- Se o formando já tem 2 proteções guardadas, a proteção sai do sorteio e os outros três prémios mantêm as mesmas proporções entre si.
-- XP do baú soma ao XP do dia, fora do limite diário das respostas (como as missões). 20 XP por baú.
-- Moedas de Desconto: 10 por baú; só se acumulam (ainda sem uso). Playbook: fica registado (conteúdo por definir).
-- Não toca em av_train_answer nem na pauta. Redefine av_train_streak_calc (033) só para somar as proteções ganhas no baú.

create table if not exists public.av_train_chest(
  user_id uuid not null,
  day date not null,
  kind text not null check (kind in ('xp','coins','freeze','playbook')),
  amount int not null default 1,
  opened_at timestamptz not null default now(),
  primary key(user_id,day));
alter table public.av_train_chest enable row level security;
drop policy if exists chest_own on public.av_train_chest;
create policy chest_own on public.av_train_chest for select using (user_id=auth.uid());

-- cópia da 033 com uma única diferença: as proteções ganhas no baú entram no stock no dia em que saíram
create or replace function public.av_train_streak_calc(p_staff uuid, p_today date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_first date; v_done date[]; v_bonus date[]; v_n int:=0; v_last date; d date; i int;
  c int:=0; stock int:=0; used date[]:='{}';
begin
  select min(day) into v_first from public.av_train_items where staff_id=p_staff and day<=p_today;
  if v_first is null then return jsonb_build_object('streak',0,'stock',0,'used','[]'::jsonb,'done',0); end if;
  select coalesce(array_agg(day),'{}') into v_done
    from public.av_train_days where staff_id=p_staff and completed and day<=p_today;
  select coalesce(array_agg(c2.day),'{}') into v_bonus
    from public.av_train_chest c2 join public.av_profiles p on p.user_id=c2.user_id
    where p.staff_id=p_staff and c2.kind='freeze' and c2.day<=p_today;
  for i in 0 .. (p_today-v_first-1) loop
    d:=v_first+i;
    if d=any(v_bonus) then stock:=least(2,stock+1); end if;   -- proteção ganha no baú
    if extract(dow from d)=6 then continue; end if;
    if d=any(v_done) then
      v_n:=v_n+1; c:=c+1;
      if c%7=0 then stock:=least(2,stock+1); end if;
    elsif stock>0 then
      stock:=stock-1; used:=used||d;                       -- dia protegido
    else
      if v_last is not null and (d-v_last)<7 then v_n:=0; end if;
      v_last:=d;
    end if;
  end loop;
  if p_today=any(v_bonus) then stock:=least(2,stock+1); end if;
  if p_today=any(v_done) then v_n:=v_n+1; c:=c+1; if c%7=0 then stock:=least(2,stock+1); end if; end if;
  return jsonb_build_object('streak',v_n,'stock',stock,'used',to_jsonb(used),'done',c);
end $$;
revoke all on function public.av_train_streak_calc(uuid,date) from public;

-- estado do baú do formando: disponível hoje? o que saiu? total de moedas e de Playbooks
create or replace function public.av_train_chest_state()
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Africa/Luanda')::date;
  st uuid; done boolean:=false; o record;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select staff_id into st from av_profiles where user_id=uid and role='collaborator';
  if st is not null then
    select coalesce(bool_or(completed),false) into done from av_train_days where staff_id=st and day=today;
  end if;
  select kind,amount into o from av_train_chest where user_id=uid and day=today;
  return jsonb_build_object(
    'available',(done and o.kind is null),
    'opened',case when o.kind is null then null else jsonb_build_object('kind',o.kind,'amount',o.amount) end,
    'coins',coalesce((select sum(amount) from av_train_chest where user_id=uid and kind='coins'),0)::int,
    'playbooks',coalesce((select count(*) from av_train_chest where user_id=uid and kind='playbook'),0)::int);
end $$;
revoke all on function public.av_train_chest_state() from public;
grant execute on function public.av_train_chest_state() to authenticated;

-- abre o baú de hoje (uma vez por dia, só depois de concluir a sessão)
create or replace function public.av_train_chest_open()
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  uid uuid:=auth.uid(); today date:=(now() at time zone 'Africa/Luanda')::date;
  st uuid; done boolean:=false; stock int:=0; r numeric; k text; amt int:=1; ins int; xpn int:=null; coins int; pbs int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select staff_id into st from av_profiles where user_id=uid and role='collaborator';
  if st is null then return jsonb_build_object('opened',false,'reason','só para formandos'); end if;
  select coalesce(bool_or(completed),false) into done from av_train_days where staff_id=st and day=today;
  if not done then return jsonb_build_object('opened',false,'reason','conclui primeiro a sessão de hoje'); end if;
  stock:=coalesce((public.av_train_streak_calc(st,today)->>'stock')::int,0);
  r:=random()*(case when stock>=2 then 85 else 100 end);
  if r<45 then k:='xp'; amt:=20;
  elsif r<75 then k:='coins'; amt:=10;
  elsif r<90 and stock<2 then k:='freeze'; amt:=1;
  else k:='playbook'; amt:=1; end if;
  insert into av_train_chest(user_id,day,kind,amount) values(uid,today,k,amt) on conflict do nothing;
  get diagnostics ins=row_count;
  if ins=0 then return jsonb_build_object('opened',false,'reason','já abriste o baú de hoje'); end if;
  if k='xp' then
    insert into av_train_xp_day(user_id,day,xp) values(uid,today,amt)
      on conflict(user_id,day) do update set xp=av_train_xp_day.xp+amt returning xp into xpn;
  end if;
  select coalesce(sum(amount),0)::int into coins from av_train_chest where user_id=uid and kind='coins';
  select count(*)::int into pbs from av_train_chest where user_id=uid and kind='playbook';
  return jsonb_build_object('opened',true,'kind',k,'amount',amt,'xp_today',xpn,'coins',coins,'playbooks',pbs);
end $$;
revoke all on function public.av_train_chest_open() from public;
grant execute on function public.av_train_chest_open() to authenticated;
