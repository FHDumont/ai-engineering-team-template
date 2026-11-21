# Spec: setup explica a meta de tempo e os limites da máquina (issue #55)

Fase solo do grupo `performance-2`, `end:auto-close`. Decisão do dono: a meta e os limites são explicados e perguntados só no setup, para não gastar token nas fases; depois disso, o dono só é chamado quando o fim do grupo acusa over-target (skill `integrate`, #47).

## Fase #55 — setup com meta e limites

Arquivos previstos: `.claude/skills/setup/SKILL.md`, `scripts/setup-repo.sh` (só se gravar o `.github/time-targets.tsv`), o teste do setup ou `scripts/tests/test_phase_texts.sh`, `README.md` (Começo rápido). Não toca as skills `execute`, `plan`, `close-phase` nem `integrate`, o `validate.sh`, o `phase-start.sh` nem o `ci.yml` (são das outras fases do grupo).

Pronto quando: o da issue #55.

1. Pergunta da meta e apresentação dos limites da máquina no quadro da skill `setup`, gravação do arquivo de meta, com teste. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`
