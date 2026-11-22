# Spec: testes não caem por tempo sob carga (issue #71)

Fase solo do grupo `estrutura`, `end:auto-close`, depois do merge da #66 (mesmo `scripts/tests/lib.sh`). Decisão do dono: importante antes de liberar os repos, porque o paralelismo no efesto deixa a máquina carregada e um teste que cai por tempo derruba o fecho da fase.

## Fase #71 — testes sem limite fixo e sem suíte aninhada

Arquivos previstos: `scripts/tests/lib.sh`, `scripts/tests/test_validate.sh`, os testes com alarme ou espera fixa, `scripts/lib/machine-limits.env.example`, `docs/process-design.md` §6.4. Não toca `scripts/start-headless.sh` (é da #68).

Pronto quando: o da issue #71, mais: a suíte completa volta abaixo da meta de 240 s (`.github/time-targets.tsv`) com a verificação de órfãos da #66 ligada; a #66 entrou sem medir isso, e o `--prepare` dela levou mais de 24 min. Meça com e sem a verificação e cite os números no PR; se a verificação pesar, ela fica barata (uma varredura só no fim, filtrada pela pasta da execução) sem deixar passar órfão.

1. Teste que reproduz a carga e falha no código antigo; limite de tempo dos testes como parâmetro, que cresce com a carga. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. `test_validate.sh` sem rodar o `test_close_phase.sh` de verdade (stub), e o parâmetro documentado no §6.4. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
