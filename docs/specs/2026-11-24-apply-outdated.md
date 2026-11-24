# Spec: --apply traz o arquivo outdated (issue #228)

Fase solo, achada na prova local do grupo segunda-leva. Modo de fim: end:auto-close. Grupo: segunda-leva. Depois do merge, a gerenciadora repete a prova `eaeaaea` → `main` e avisa os adotantes.

## Fase #228 — fetch-template.sh --apply e os outdated fora do manifest

Fecha: #228.

Arquivos: `scripts/fetch-template.sh`, `scripts/method-diff.sh` (só o `--notice`), `scripts/tests/test_fetch_template.sh`, `scripts/tests/test_method_diff.sh`. Área sensível: nenhuma do dono.

Pronto quando:

- `--apply` copia todo arquivo `outdated` das pastas do método, dentro e fora do `method-files.txt`; o `adapted` e o `repo-only` ficam como estão; teste com um teste fora do manifest igual ao da origem falha no código atual;
- o `--notice` lista os `adapted`, que pedem junção à mão;
- prova na parada: `validate.sh` verde. A prova `eaeaaea` → `main` com `validate.sh --full` é da gerenciadora, depois do merge.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
