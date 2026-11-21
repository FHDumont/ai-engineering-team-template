# Spec: meta de tempo por projeto e fecho visível (issues #47 e #46)

Fase solo do grupo `performance`, `end:auto-close`, depois do merge da #39 e da #40. Decisões do dono: a meta aceita na #39 (fase com mediana abaixo de 45 min sem a espera pelo dono, `validate.sh` abaixo de 240 s) é o padrão do método; cada projeto pode ter a sua, e quem passar da meta conversa com o dono por um quadro. A parada em `lab-test` nunca pede ao dono que rode script.

## Fase #47 — meta por projeto, lab-test sem script e progresso do fecho

Arquivos previstos: `.github/time-targets.tsv` (novo, com o padrão), `scripts/machine-slots.sh` ou `scripts/trace-view.py` (comparação com a meta), `scripts/close-phase.sh` (só as chamadas de `scripts/lib/progress.sh` em `--prepare`, `--check` e `--merge --wait`), `.claude/skills/integrate/SKILL.md`, `.claude/skills/execute/SKILL.md` (#46), `scripts/tests/` (incluindo `test_phase_texts.sh`), `docs/process-design.md` (§6.4 e a meta), `README.md` (o arquivo de meta é do repositório na atualização).

Pronto quando: o das issues #47 e #46, mais: o `close-phase.sh` grava o progresso dos passos longos (`--prepare`, `--check`, `--merge --wait`) no mesmo formato do §6.4, e o §6.4 deixa de dizer que ele ainda não grava. O PR fecha #47 e #46.

1. Arquivo de meta com o padrão, comparação over-target e o quadro ao dono na skill `integrate`, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. Progresso no `close-phase.sh`, com teste. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (close-phase.sh é caminho sensível)`
3. #46 na skill `execute` e no teste de textos; textos do `process-design` e do README. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`
