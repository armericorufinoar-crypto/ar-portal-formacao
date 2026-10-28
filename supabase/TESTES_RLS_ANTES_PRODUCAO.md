# Lista de testes obrigatórios de segurança RLS

Executar com contas distintas (administrador, formador e dois colaboradores de teste). Não utilizar dados pessoais reais.

- [ ] Sem sessão autenticada, as tabelas não devolvem dados privados.
- [ ] Um colaborador não consegue listar nem alterar os dados pessoais de outro colaborador.
- [ ] Um colaborador consulta apenas as suas presenças e avaliações.
- [ ] Um colaborador não consegue inserir/alterar presenças nem avaliações.
- [ ] Um colaborador não consegue ler mensagens privadas de outro colaborador, nem respostas dessas mensagens.
- [ ] Um colaborador só consegue criar uma mensagem privada associada ao seu próprio registo.
- [ ] Um colaborador não consegue promover o próprio perfil a `admin` ou `trainer`.
- [ ] Um formador consegue gerir sessões, presenças, avaliações, fórum e feedback, mas não consegue gerir o cadastro de colaboradores nem alterar papéis.
- [ ] Apenas a administração consegue criar/editar/desactivar colaboradores e gerir papéis.
- [ ] Utilizador desactivado ou removido perde o acesso previsto pela política aprovada.
- [ ] Links de materiais não permitem contornar permissões; ficheiros privados exigem bucket privado e políticas próprias.
- [ ] As operações de escrita e leitura continuam seguras quando chamadas directamente à API, sem passar pela interface.

A migração é uma fundação inicial e não substitui esta bateria de testes. Rever também os casos de moderação do fórum e de resposta privada com a equipa responsável antes de abrir o acesso a todos os colaboradores.
