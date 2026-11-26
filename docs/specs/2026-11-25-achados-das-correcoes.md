# Spec: achados das correções de scripts (issues #272, #277)

Duas fases paralelas, sem arquivo de código em comum. Modo de fim de ambas: end:auto-close. Grupo: achados-das-correcoes. A #269 (mudar o nome da pasta dos scripts do método) não entra: é decisão de arquitetura do dono.

## Fase #272 — `test_setup_check.sh` estável sob carga

Fecha: #272.

Arquivos: `scripts/tests/test_setup_check.sh` (e `scripts/tests/lib.sh` só se a causa for estado compartilhado de lá).

Pronto quando:

- A causa do `missing: protection` em "check names only what is missing" está achada e escrita no commit (estado compartilhado, ordem ou tempo), não só mascarada com repetição.
- Teste que reproduz a causa e falha no código atual, ou, se a causa for tempo, uma contagem no lugar do tempo.
- Prova na parada: `validate.sh --full` com `AI_METHOD_TEST_JOBS` alto e outro `validate.sh` ao mesmo tempo passa duas rodadas seguidas; `check-docs.sh` verde.

1. Achar a causa e escrever o teste que falha. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (causa ainda desconhecida, escopo de um teste)
2. Corrigir e provar sob carga. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv

## Fase #277 — `--publish-review` usa o parecer da própria fase

Fecha: #277. Área sensível: `scripts/close-phase.sh` é o portão (`needs-gate-review`); o merge pede o ok do dono, digitado na sessão da fase.

Arquivos: `scripts/close-phase.sh` (`require_unedited_opinion`), `scripts/tests/` (teste do `close-phase.sh`).

Pronto quando:

- Teste que falha no código atual: o trace tem dois `SubagentStop` do `close-reviewer` de sessões diferentes; o `--publish-review` do parecer da primeira passa mesmo com o último evento do trace sendo da segunda.
- O `require_unedited_opinion` filtra o evento pelo `agent_id` do parecer salvo (ou, na falta dele, pelo `session_id` da fase), e continua recusando um parecer editado à mão.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Teste que falha no código atual, com dois revisores no trace. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (portão do merge)
2. Filtrar o evento pelo `agent_id`/`session_id` e manter a recusa do parecer editado. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (portão do merge)
