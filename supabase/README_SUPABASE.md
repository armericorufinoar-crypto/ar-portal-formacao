# Backend Supabase — Portal de Formação AR

Esta pasta prepara a base de dados e as políticas de acesso para o portal interno. A aplicação HTML v4 ainda não está ligada a este backend; não introduza dados reais até concluir a integração de autenticação e testar as permissões.

## O que inclui o esquema

- Perfis de autenticação com papéis `admin`, `trainer` e `collaborator`.
- Cadastro de colaboradores sem recolha de BI por defeito.
- Sessões e materiais, presenças, avaliações práticas, fórum, feedback e mensagens privadas.
- Row Level Security (RLS) em todas as tabelas.
- Colaborador limitado aos próprios registos; equipa formativa com permissões de gestão de formação; administração com gestão de cadastros e perfis.

## Instalação num projecto dedicado

1. Crie um projecto Supabase dedicado ao Portal de Formação AR (não reutilize a base de dados de outros sistemas).
2. No painel Supabase, abra **SQL Editor**.
3. Reveja e execute as migrações por ordem (001, 002, 003, 004, 005, 006, 007, 008, e as `migracao_*`/`migracao-v11` conforme a versão do portal). A `001` já traz as áreas novas (Marketing e Vendas, Gestão Estratégica, Liderança, Oratória, Finanças). Se as tabelas já foram criadas com as áreas antigas, corra apenas `009_novas_areas_ar_formacao.sql`.
4. Em **Authentication → URL Configuration**, configure a URL do portal e os redirect URLs exactos usados pelo ambiente de teste/produção.
5. Em **Authentication → Providers**, mantenha o método de acesso escolhido pela AR Formação e desactive inscrições públicas se os colaboradores forem convidados pela administração.
6. Crie a conta do primeiro administrador através do mecanismo de autenticação e copie o UUID dessa conta.
7. No SQL Editor, promova essa conta: `update public.av_profiles set role = 'admin' where user_id = '<UUID_DO_UTILIZADOR>';` Substitua o marcador pelo UUID real; não execute literalmente.
8. Faça uma revisão de segurança das políticas RLS com contas de teste de cada papel antes de importar quaisquer dados reais.

## Segredos e chaves

- Nunca colocar a chave `service_role` no HTML, JavaScript de navegador, repositório ou ZIP partilhado.
- O URL do projecto e a chave `anon`/publishable podem ser usados no cliente apenas depois de activar e validar as políticas RLS.
- As credenciais reais não foram fornecidas nem incorporadas neste pacote.

## Nota importante sobre a migração

O esquema está normalizado e não é um espelho directo das listas JSON guardadas em `localStorage`. A integração do frontend precisa de adaptar operações síncronas actuais para operações assíncronas, associar o utilizador autenticado ao registo de colaborador e substituir o link demonstrativo `?colaborador=TOKEN` por sessão autenticada. Não copie dados de demonstração para produção.

## Antes de produção

- Rever as políticas com testes positivos e negativos por papel.
- Definir recuperação de conta, expiração de sessão e revogação de acesso.
- Configurar backups, monitorização e retenção.
- Criar bucket privado e políticas de armazenamento se for necessário carregar ficheiros; esta migração guarda ligações a materiais, não implementa upload.
- Definir finalidade, base legal, acesso e retenção para qualquer dado de identificação pessoal.
- Testar concorrência, falhas de rede e exportação de relatórios.
