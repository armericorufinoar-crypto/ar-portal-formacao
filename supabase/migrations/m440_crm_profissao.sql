-- 020 · Ficha do interessado com a mesma lógica do perfil (nome, profissão, e-mail, telefone).
-- (A inserção de 4 interessados reais foi retirada desta versão: dados pessoais não pertencem a migrações.)
-- EXECUTAR ANTES de publicar o novo index.html (acrescenta a coluna «profession»).
alter table public.av_crm_deals add column if not exists profession text;
update public.av_crm_deals set profession = interest where profession is null and interest is not null;
alter table public.av_crm_deals drop column if exists interest;
