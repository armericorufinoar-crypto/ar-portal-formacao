-- 020 · Ficha do interessado com a mesma lógica do perfil (nome, profissão, e-mail, telefone)
-- + os 4 novos interessados recebidos por WhatsApp.
-- EXECUTAR ANTES de publicar o novo index.html (acrescenta a coluna «profession»).
alter table public.av_crm_deals add column if not exists profession text;
update public.av_crm_deals set profession = interest where profession is null and interest is not null;
alter table public.av_crm_deals drop column if exists interest;

-- Novos interessados recebidos por WhatsApp (perfil preenchido para a próxima turma).
-- Entram no Pipeline na etapa «Novo», origem WhatsApp. Os códigos CRM-000N são atribuídos pelo servidor.
-- Re-executável: se já existirem (mesmo id), não duplica.
insert into public.av_crm_deals (id, name, profession, phone, email, origin, stage, probability, entered_on, notes)
values
 ('D-WA-MANUELLUCIANO', 'Manuel Luciano António', 'Assistente de contabilidade', '928519023', 'manuelluciano391@gmail.com', 'WhatsApp', 'NOVO', 10, current_date, 'Entrada por WhatsApp (próxima turma)'),
 ('D-WA-JOAQUINACAROLINA', 'Joaquina Carolina Magalhães Pedro', 'GRH', '926321999', 'cjoaquinacarolina@gmail.com', 'WhatsApp', 'NOVO', 10, current_date, 'Entrada por WhatsApp (próxima turma)'),
 ('D-WA-MARINETHGUNZA', 'Marineth Gunza do Rosário', 'Cabeleireira / técnico de RH', '937867951', 'marinethrosario061@gmail.com', 'WhatsApp', 'NOVO', 10, current_date, 'Entrada por WhatsApp (próxima turma)'),
 ('D-WA-JOSIASMUCUTA', 'Josias Mucuta Sacatala', 'Estudante universitário do 2.º ano', '935279126', 'josiasmucutasacatala@gmail.com', 'WhatsApp', 'NOVO', 10, current_date, 'Entrada por WhatsApp (próxima turma). Administração de empresas')
on conflict (id) do nothing;

select code, name, phone, stage from public.av_crm_deals where id like 'D-WA-%' order by code;
