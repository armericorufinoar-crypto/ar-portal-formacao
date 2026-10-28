# AR Formação — Portal interno de formandos

## Objectivo
Plataforma interna para organizar o período formativo dos formandos da AR. Não é um portal público de inscrições nem uma plataforma comercial de formação.

## Áreas de formação
- Finanças e Investimentos
- Marketing e Vendas
- Negócios
- Oratória
- Liderança

## Módulos desta versão demonstrativa
1. Painel geral com indicadores, distribuição por área, próximas sessões e média de desempenho.
2. Cadastro de formandos: número interno, nome, profissão, função, contactos e campo opcional de identificação para futura certificação. Os formandos podem participar nas cinco áreas; a área é atribuída à sessão, não ao formando.
3. Gestão de sessões: data, hora, formador, local, objectivos, material por ligação e exercício prático.
4. Controlo de presenças por sessão: Presente, Falta e Justificada, com resumo de assiduidade.
5. Avaliação dos exercícios práticos: resultado de 0 a 100, critérios e feedback do formador.
6. Fórum para dúvidas, perguntas, opiniões e respostas da equipa formativa.
7. Feedback individual da sessão (classificação de 1 a 5 e comentário).
8. Mensagens privadas e respostas da equipa formativa.
9. Relatório CSV para conferir assiduidade e resultados antes de preparar certificação. A aplicação não emite certificados nesta fase.
10. Link de demonstração para a área de cada formando, gerado a partir do cadastro.

## Persistência actual e segurança
Esta versão é um protótipo funcional local: os dados são guardados em `localStorage` no navegador e não são partilhados entre dispositivos ou utilizadores. O link de formando é apenas demonstrativo e não constitui autenticação segura. Os materiais são ligados por URL; não existe upload privado. Não introduzir dados pessoais reais ou documentos de identificação.

## Requisitos antes da utilização operacional
- Backend e base de dados partilhada, com migrações e cópias de segurança.
- Autenticação individual, papéis (administrador, formador e formando), convites seguros com expiração/revogação e recuperação de acesso.
- Permissões verificadas no servidor; cada formando apenas consulta os próprios dados e os conteúdos autorizados.
- Armazenamento privado de materiais e registos de acesso/alteração.
- Regras formais para assiduidade, avaliação e elegibilidade para certificação.
- Definir a base legal, finalidade, retenção e acesso a dados de identificação antes de recolher BI ou informação equivalente.
- Testes funcionais, de autorização, segurança e recuperação.

## Integração futura com RH
Manter identificador interno estável e prever API versionada. Não há integração ou sincronização activa nesta versão.
