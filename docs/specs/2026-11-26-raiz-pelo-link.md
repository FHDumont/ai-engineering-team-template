# Spec: check-env acha a spec pelo link scripts (issue #290)

Fase solo, regressão do PR 289 (#269). Modo de fim: end:auto-close. Grupo: raiz-pelo-link. Aberta com `phase-start.sh 290 --no-check`, decisão do dono: o próprio `check-env.sh` quebrado impede abrir qualquer fase. Depois do merge, a gerenciadora abre a #288.

## Fase #290 — raiz lógica no lugar de `$HERE/..` em caminho de arquivo

Fecha: #290. Área sensível: nenhum arquivo do portão.

Arquivos: `.method/scripts/check-env.sh` (linhas 141, 167 e 218), `.method/scripts/machine-slots.sh` (linha 62), os testes deles em `.method/scripts/tests/`.

Pronto quando:

- Teste que falha no código atual: num worktree com o link `scripts -> .method/scripts`, `scripts/check-env.sh` acha a spec da fase e a citação de bots, e `machine-slots.sh` lê o `.github/time-targets.tsv` da raiz.
- Os dois scripts usam a raiz lógica (`cd "$HERE/.." && pwd`) ou `git rev-parse --show-toplevel` em todo caminho de arquivo; nenhum `"$HERE/../"` sobra em glob ou leitura de arquivo nos scripts do método.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes; depois do merge, `scripts/phase-start.sh 288 --dry-run` passa.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. Raiz lógica nos dois scripts. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
