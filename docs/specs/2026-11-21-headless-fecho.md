# Spec: base da main sem check CI e fecho da filha headless (issues #33 e #31)

Fase solo do grupo `fases-e-maquina`, `end:auto-close`. Entraram no grupo com o ok do dono, antes das issues de atualização nos repos que usam o template.

Abertura por fora, uma vez, com o ok do dono: o `phase-start.sh` recusa toda fase (é o defeito da #33), então esta fase abre pelo `scripts/new-phase.sh`, que grava o `phase_opened`. O merge segue pelo portão.

## Fase #33 — base da main e filha headless

Arquivos previstos: `scripts/phase-start.sh`, `scripts/start-headless.sh`, `scripts/tests/fakes/gh`, `scripts/tests/test_phase_start.sh`, o teste do `start-headless.sh`, `.claude/skills/close-phase/SKILL.md`, `docs/process-design.md` §4.3 (texto da retomada, se estiver lá).

Pronto quando: o das issues #33 e #31. O PR fecha #33 e #31.

1. Bug #33: teste que reproduz o commit da `main` sem check `CI` com o PR verde e a mesma árvore (falha no código antigo), depois a correção no `phase-start.sh`. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (trava de entrada do método, bug com causa conhecida)`
2. #31: `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0` no `start-headless.sh`, prompt logo depois do `-p` no texto da retomada, revisão em primeiro plano na skill `close-phase` para a filha headless, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
