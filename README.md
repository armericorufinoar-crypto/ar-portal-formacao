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


## Fase 2 — Matriz pedagógica

- Consultar `MATRIZ_PEDAGOGICA_AV.md` para a matriz inicial de temáticas, competências, evidências e reforços.
- A migração `supabase/migrations/013_matriz_competencias.sql` cria o catálogo de competências e a associação opcional das perguntas a uma competência.
- A associação é opcional para preservar todos os testes existentes; perguntas antigas continuam a funcionar sem alteração.
- Os limiares de diagnóstico no documento são propostas pedagógicas a validar, não regras de certificação.
- A ponderação da pauta permanece 60% testes automáticos / 40% avaliações práticas.
- Esta migração não foi executada no Supabase real. Aplicar primeiro em ambiente de teste e verificar RLS/permissões.


## Fase 3 — Diagnóstico de competências (implementação no frontend)

- O editor de perguntas apresenta um selector opcional de competência quando o catálogo da matriz está instalado. Perguntas sem associação continuam válidas.
- A área do formando inclui uma secção «Diagnóstico», distinta da pauta oficial. Os resultados são calculados no servidor a partir das respostas e das chaves de correcção, não do conteúdo enviado pelo navegador.
- A migração `supabase/migrations/014_diagnostico_competencias.sql` cria o registo por tentativa/competência e a função RPC de diagnóstico.
- Aplicar em ambiente de teste, por esta ordem, `013_matriz_competencias.sql` e `014_diagnostico_competencias.sql`. Não executar sem autorização e sem validar RLS.
- A ponderação oficial está bloqueada no frontend em 60% testes automáticos / 40% avaliação prática. A secção de diagnóstico não altera a classificação de certificação.
- Limitação: não foi possível testar contra a instância Supabase real nesta execução.
