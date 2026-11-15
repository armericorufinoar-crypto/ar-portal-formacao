-- Conversão das áreas formativas (executar uma vez no SQL Editor do Supabase)
-- Finanças e Investimentos      -> Gestão Financeira e Tesouraria
-- Marketing e Vendas            -> Marketing, Prospecção e CRM
-- Negócios                      -> Empreendedorismo e Modelo de Negócio
-- Oratória e Liderança          -> Gestão Estratégica e Liderança
-- Gestão de Equipas, Processos e KPIs -> área nova (sem origem)

begin;

-- 1) Fichas dos formandos (array de áreas; quem tinha Oratória e Liderança fica só com uma)
update av_staff s
set areas = (
  select coalesce(array_agg(distinct m.nova), '{}')
  from unnest(s.areas) as a(v)
  cross join lateral (select case a.v
    when 'Finanças e Investimentos' then 'Gestão Financeira e Tesouraria'
    when 'Marketing e Vendas'       then 'Marketing, Prospecção e CRM'
    when 'Negócios'                 then 'Empreendedorismo e Modelo de Negócio'
    when 'Oratória'                 then 'Gestão Estratégica e Liderança'
    when 'Liderança'                then 'Gestão Estratégica e Liderança'
    else a.v end as nova) m
)
where s.areas && array['Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança'];

-- 2) Sessões, planos de pagamento e perguntas de treino (campo de texto simples)
do $$
declare t text;
begin
  foreach t in array array['av_sessions','av_fee_plans','av_train_questions'] loop
    if to_regclass(t) is not null then
      execute format($f$update %I set area = case area
        when 'Finanças e Investimentos' then 'Gestão Financeira e Tesouraria'
        when 'Marketing e Vendas'       then 'Marketing, Prospecção e CRM'
        when 'Negócios'                 then 'Empreendedorismo e Modelo de Negócio'
        when 'Oratória'                 then 'Gestão Estratégica e Liderança'
        when 'Liderança'                then 'Gestão Estratégica e Liderança'
        else area end
        where area in ('Finanças e Investimentos','Marketing e Vendas','Negócios','Oratória','Liderança')$f$, t);
    end if;
  end loop;
end $$;

commit;
