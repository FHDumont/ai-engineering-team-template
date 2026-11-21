# Spec: setup obrigatório (issue #4)

Fase solo, `end:auto-close`. O dono pediu a trava e deu o ok pela label `approved`.

## Fase #4 — setup obrigatório

Arquivos previstos: `scripts/setup-repo.sh`, `scripts/phase-start.sh`, `scripts/open-issue.sh`, `.claude/hooks/session-setup-check.sh` (novo) e o teste dele, `.claude/settings.json`, `.claude/skills/setup/SKILL.md`, `AGENTS.md`, `docs/process-design.md`, `README.md`, `scripts/tests/`. Não toca `scripts/close-phase.sh` nem `.github/`.

Pronto quando: o da issue #4.

1. Conferência do setup (`setup-repo.sh --check`), a recusa no `phase-start.sh` e no `open-issue.sh`, o hook de início de sessão e os testes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (trava de entrada do método)`
2. Textos: skill `setup`, `AGENTS.md`, desenho e "Começo rápido" do README. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
