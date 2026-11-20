-- 033_treino_protecao_sequencia.sql · Dias de proteção da sequência (streak freeze). Idempotente.
-- Regra: ganha-se 1 proteção por cada 7 sessões completas (máx. 2 guardadas). Uma proteção absorve
-- automaticamente 1 dia útil falhado (não conta como dia feito, mas não quebra a sequência nem gasta
-- a tolerância já existente). Sábado continua a ser descanso. Cálculo puro, sem tabelas novas.
-- NOTA: altera só a leitura da sequência; av_train_answer e a pauta ficam como estão. Quem já tem
-- >=7 sessões completas passa a ter proteções retroactivas, pelo que sequências antigas só podem subir.
create or replace function public.av_train_streak_calc(p_staff uuid, p_today date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_first date; v_done date[]; v_n int:=0; v_last date; d date; i int;
  c int:=0; stock int:=0; used date[]:='{}';
begin
  select min(day) into v_first from public.av_train_items where staff_id=p_staff and day<=p_today;
  if v_first is null then return jsonb_build_object('streak',0,'stock',0,'used','[]'::jsonb,'done',0); end if;
  select coalesce(array_agg(day),'{}') into v_done
    from public.av_train_days where staff_id=p_staff and completed and day<=p_today;
  for i in 0 .. (p_today-v_first-1) loop
    d:=v_first+i;
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
  if p_today=any(v_done) then v_n:=v_n+1; c:=c+1; if c%7=0 then stock:=least(2,stock+1); end if; end if;
  return jsonb_build_object('streak',v_n,'stock',stock,'used',to_jsonb(used),'done',c);
end $$;
revoke all on function public.av_train_streak_calc(uuid,date) from public;

-- mesma assinatura e resultado de antes, agora com proteção
create or replace function public.av_train_streak(p_staff uuid, p_today date)
returns integer language sql stable security definer set search_path=public as $$
  select (public.av_train_streak_calc(p_staff,p_today)->>'streak')::int $$;

-- av_train_xp_me passa a devolver também as proteções (freeze) do formando
create or replace function public.av_train_xp_me()
returns jsonb language plpgsql security definer set search_path=public stable as $$
declare uid uuid:=auth.uid(); st uuid; fz jsonb:=null; k jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select staff_id into st from av_profiles where user_id=uid and role='collaborator';
  if st is not null then
    k:=public.av_train_streak_calc(st,(now() at time zone 'Africa/Luanda')::date);
    fz:=jsonb_build_object('stock',k->'stock','used',k->'used','next_in',7-((k->>'done')::int%7),'max',2);
  end if;
  return jsonb_build_object(
    'today',coalesce((select xp from av_train_xp_day where user_id=uid and day=(now() at time zone 'Africa/Luanda')::date),0),
    'total',coalesce((select sum(xp) from av_train_xp_day where user_id=uid),0),
    'cap',300,'freeze',fz);
end $$;
grant execute on function public.av_train_xp_me() to authenticated;
