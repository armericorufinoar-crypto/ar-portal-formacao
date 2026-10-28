# Portal de Formação AR — MVP interno

## Teste
1. Extraia o ZIP.
2. Abra `index.html` num navegador moderno. Para links de formando, é preferível servir a pasta por HTTP local.
3. Registe formandos, crie sessões, registe presenças e avaliações e teste o fórum/feedback.
4. O botão **Link** na tabela de formandos gera um link demonstrativo para a área individual. O link só encontra os dados no mesmo navegador/perfil e na mesma origem.
5. Em **Relatórios e certificação**, exporte CSV para conferir os registos.

## Aviso
Esta é uma demonstração local, não uma plataforma de produção. Os dados permanecem neste navegador. Não use nomes, contactos ou números de identificação reais; use dados fictícios para os testes. Não existe autenticação segura, sincronização, upload privado nem emissão de certificados.

## Preparação do backend partilhado

A pasta `supabase/` contém o esquema SQL inicial e instruções de instalação para um projecto Supabase separado. Consulte também `CONFIGURACAO_BACKEND.md`. **O frontend ainda não está ligado ao Supabase**; a versão actual continua local. Não introduza dados reais nem considere o portal pronto para produção antes de implementar e testar autenticação, sincronização e RLS.

## AR Formação — ligação ao Supabase
O `index.html` aponta para o projecto `xpeeaekzomusoqjdpbxn`. A chave publishable já está configurada. Nunca use a `service_role` no navegador. Se as tabelas já existirem com as áreas antigas, execute `supabase/migrations/009_novas_areas_ar_formacao.sql`. A função `admin-utilizadores` tem de ser publicada também neste projecto.

## Módulo de Pagamentos
- **Administrador:** separador «Pagamentos» (painel, a confirmar, parcelas, facturas, planos, definições, CSV).
- **Formando:** separador «Facturação» (pró-formas, efectuar pagamento, comprovativo, facturas).
- Requer as migrações `005` e `010`. Os dados de pagamento (telemóvel Express, IBAN, banco, titular) ficam na tabela `av_pay_settings` e editam-se em Pagamentos → Definições. Não os guarde em ficheiros do repositório.
