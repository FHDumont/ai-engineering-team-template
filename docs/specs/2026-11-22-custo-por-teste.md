# Spec: custo fixo por teste de volta ao nível da #42 (issue #83)

Fase solo do grupo `estrutura`, `end:auto-close`, em paralelo com a #81 (sem arquivo em comum). Autorização do dono na madrugada de 22/11. Meta: `validate.sh` abaixo de 240 s.

Dado da gerenciadora: logo depois da #42 (suíte em paralelo) a suíte completa levava ~152 s; depois da #66 (órfãos), da #71 (limite de tempo) e dos cortes da #76 e da #81, ela está em ~296 s com load de 4 a 6, e "nenhum arquivo domina": o custo é muito processo curto (sys alto). A suspeita é o custo fixo que cada teste passou a pagar.

## Fase #83 — custo fixo por teste

Arquivos previstos: `scripts/validate.sh` (o embrulho de cada teste), `scripts/tests/lib.sh` (ajudantes e o trap de órfãos), `scripts/lib/procs.sh`, `scripts/lib/progress.sh`, `scripts/lib/slots.sh` (só o que roda por teste), e os testes `test_phase_scripts.sh`, `test_sessions.sh`, `test_setup_check.sh`, `test_phase_filter.sh` se o maior custo for deles. Não toca os arquivos da #81 (`test_phase_start_*.sh`, `test_block_*`, `test_start_headless.sh`) e não afrouxa a verificação de órfãos nem o limite de tempo.

Pronto quando: o da issue #83, mais: medir o custo fixo por teste (embrulho do `validate.sh`, trap e varredura de órfãos, gravação de progresso, cálculo do limite) comparando com o commit logo depois da #42; cortar o que pesa (por exemplo calcular o limite e a vaga uma vez por execução, gravar progresso sem subprocesso, varrer órfãos só uma vez no fim); suíte completa abaixo de 240 s com a máquina livre; antes e depois no PR.

1. Medir o custo fixo por teste contra o commit depois da #42 e cortar o maior, sem perder a garantia de órfão nem a do limite de tempo. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. Se ainda passar de 240 s, partir ou baratear os maiores testes restantes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
