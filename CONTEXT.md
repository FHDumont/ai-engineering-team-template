# Glossário

- **Fase**: uma unidade de trabalho com issue, branch, worktree e PR próprios. Solo ou paralela.
- **Grupo**: fases afins (`group:*`) planejadas juntas; podem rodar em paralelo.
- **Spec**: plano curto de uma fase (etapas, modelo/esforço/motivo, modo de fim), aprovado pelo dono do repo com um ok.
- **Triagem**: leitura só de títulos e labels (`scripts/triage.sh`) para sugerir grupos e o peso do planejamento.
- **Modo de fim**: `end:auto-close` (o agente fecha pelo portão) ou `end:lab-test` (o dono do repo testa no lab e diz "fechar fase").
- **Portão**: o check `CI` mais o status `review/independent`; nada entra na `main` sem os dois.
- **Revisão independente**: o agente `close-reviewer` lê a issue, o diff e os testes (nunca o resumo do executor) e publica `review/independent`.
- **Caminho sensível**: glob de `.github/sensitive-paths`; o PR que toca um deles recebe `needs-owner-ok` e não fecha sozinho.
- **Achado**: algo encontrado durante uma fase; vira issue `finding` com `size:small|medium|large`.
- **Caminho A / B**: A é só o agente de código; B acrescenta o time de bots, chamados pelo `scripts/ask-bot.sh`.
- **Marca de resposta**: `<!-- bot:<slug> reply-to:<id> -->`; é como a resposta de um bot é reconhecida, mesmo quando todos usam a mesma conta.
- **Bloco de status**: as 3 linhas do `scripts/status.sh` (Estado, Você precisa, Próximo passo) que fecham toda parada e toda mensagem final de turno.
- **Lab**: ambiente de teste com deploy próprio onde o dono do repo valida uma fase `end:lab-test`.
- **Sessão filha**: sessão do app desktop aberta pelo `plan` com `start_session` para executar uma fase; edita o worktree dela por caminho absoluto.
- **Gerenciadora**: a sessão de planejamento que abriu as filhas; repassa as mensagens do dono do repo por `send_message` e, no fim, arquiva as sessões ligadas.
- **Provedor de segredo**: onde `scripts/lib/secret.sh` lê URL e segredo de um bot: variável de ambiente, conta de serviço do gerenciador de senhas (opcional) ou `~/.<repo-slug>/.env` (padrão).
