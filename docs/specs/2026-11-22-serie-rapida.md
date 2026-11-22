# Spec: caso em série do test_validate.sh sem esperar o limite (issue #78)

Fase solo do grupo `estrutura`, `end:auto-close`, em paralelo com a #74 (sem arquivo em comum). Regressão da #71 achada pela gerenciadora na madrugada de 22/11: o caso em série espera 600 s vezes o fator de carga antes de falhar, em toda suíte. Autorização do dono na mesma madrugada para resolver achado de estrutura antes de liberar os repos.

## Fase #78 — limite curto no caso em série

Arquivos previstos: `scripts/tests/test_validate.sh`. Não toca `scripts/tests/test_close_phase.sh` (é da #76) nem os arquivos da #74.

Pronto quando: o da issue #78, com o tempo do `test_validate.sh` antes e depois no PR.

1. Limite curto e explícito no caso em série, parâmetro só no caso em paralelo; tempo do teste antes e depois. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`
