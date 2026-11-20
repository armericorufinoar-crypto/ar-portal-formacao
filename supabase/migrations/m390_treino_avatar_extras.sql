-- 032_treino_avatar_extras.sql · Extras de avatar desbloqueáveis (3 Auscultadores, 4 Faixa, 5 Raio).
-- Só cosmético; não toca em av_train_answer nem na pauta. Idempotente.
-- Desbloqueio: 3 = 7 dias com XP (medalha «Constante»); 4 = escalão Prata/Ouro; 5 = escalão Ouro.
create or replace function public.av_train_avatar_allowed(p_code text)
returns boolean language plpgsql security definer set search_path=public stable as $$
declare uid uuid:=auth.uid(); x int; tr int; dias int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_code is null or p_code !~ '^[0-3]{2}[0-2]{2}[0-5]$' then return false; end if;
  x:=substr(p_code,5,1)::int;
  if x<=2 then return true; end if;
  select coalesce(max(tier),1) into tr from av_train_tier where user_id=uid;
  select count(*) filter (where xp>0) into dias from av_train_xp_day where user_id=uid;
  return case x when 3 then dias>=7 when 4 then tr>=2 else tr>=3 end;
end $$;
revoke all on function public.av_train_avatar_allowed(text) from public;
grant execute on function public.av_train_avatar_allowed(text) to authenticated;

-- substitui a versão da 031 (mesma assinatura): aceita o 5.º dígito 0-5 e valida o desbloqueio
create or replace function public.av_train_set_avatar(p_code text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  if p_code is null or btrim(p_code)='' then delete from av_train_avatar where user_id=auth.uid(); return; end if;
  if p_code !~ '^[0-3]{2}[0-2]{2}[0-5]$' then raise exception 'avatar inválido'; end if;
  if not public.av_train_avatar_allowed(p_code) then raise exception 'extra ainda bloqueado'; end if;
  insert into av_train_avatar(user_id,code) values(auth.uid(),p_code)
    on conflict(user_id) do update set code=excluded.code, updated_at=now();
end $$;
