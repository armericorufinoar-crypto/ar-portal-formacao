-- ============================================================================
-- AV Formação · Uniformizar etapas (5) no CRM de treino
-- Seguro repetir. Só mexe em av_sim_deals e na função av_sim_seed.
-- ============================================================================
update public.av_sim_deals set stage='CONTACTADO' where stage='QUALIFICADO';
update public.av_sim_deals set stage='PROPOSTA'    where stage='NEGOCIACAO';

create or replace function public.av_sim_seed(p_mode text default 'guiado')
returns void
language plpgsql security definer set search_path = public
as $$
declare
  uid uuid := auth.uid();
  r   record;
  cid uuid;
  did uuid;
begin
  if uid is null then raise exception 'Sessão inválida'; end if;
  if p_mode <> 'guiado' then raise exception 'Só o cenário guiado tem dados iniciais'; end if;
  if exists (select 1 from av_sim_deals where user_id = uid and mode = 'guiado') then return; end if;

  for r in
    select * from (values
      (1,'Ana Beatriz Mateus','923100001','Indicação',  'NOVO',       'Turma de empreendedores', 27000,  1, 2,20),
      (2,'Joana Kiala',       '923100002','Instagram',  'CONTACTADO', 'Turma de empreendedores', 27000,  2, 1,15),
      (3,'Joana Kyala',       '923100002','Instagram',  'CONTACTADO', 'Turma de empreendedores', 27000,  2, 1,15),
      (4,'Pedro Manuel',      '923100004','Facebook',   'CONTACTADO', 'Consultoria no negócio',  60000, 20, 3,10),
      (5,'Domingos Lemos',    '923100005','Indicação',  'PROPOSTA',   'Turma de empreendedores', 27000,  3,null, 8),
      (6,'Fernando Chivela',  '923100006','Indicação',  'PROPOSTA',   'Consultoria no negócio', 150000,  2, 1, 5),
      (7,'Cristina Bento',    '923100007','WhatsApp',   'GANHO',      'Turma de empreendedores', 27000, 10, 4,null)
    ) as t(n,name,phone,source,stage,title,value,last_days,task_days,close_days)
    order by n
  loop
    insert into av_sim_contacts(user_id, mode, name, phone, source)
    values (uid, 'guiado', r.name, r.phone, r.source) returning id into cid;
    insert into av_sim_deals(user_id, mode, contact_id, title, stage, value, expected_close, last_activity)
    values (uid, 'guiado', cid, r.title, r.stage, r.value,
            case when r.close_days is null then null else current_date + r.close_days end,
            current_date - r.last_days)
    returning id into did;
    if r.task_days is not null then
      insert into av_sim_tasks(user_id, mode, deal_id, title, due)
      values (uid, 'guiado', did, 'Contacto de follow-up', current_date + r.task_days);
    end if;
  end loop;
end;
$$;
revoke all on function public.av_sim_seed(text) from public;
grant execute on function public.av_sim_seed(text) to authenticated;
