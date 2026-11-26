# Spec: achados leves do grupo pasta-do-metodo (issue #294)

Fase solo, modo de fim end:auto-close, grupo achados-pasta-do-metodo. Área sensível: `.method/scripts/check-docs.sh` é verificador do portão; o merge segue o que o `close-phase.sh` pedir.

## Fase #294 — escapar o ponto do filtro de .method/scripts/

Fecha: #294.

Objetivo: nas linhas que filtram `.method/scripts/` em `.method/scripts/check-docs.sh` (hoje 159 e 165), o ponto fica escapado (`'^\.method/scripts/'`), para não casar um caminho como `xmethod/scripts/`.

Arquivos: `.method/scripts/check-docs.sh` e o teste dele (`.method/scripts/tests/test_docs_tools.sh` ou um novo `test_*.sh`).

Pronto quando:

- Teste que falha no código atual: um caminho `xmethod/scripts/...` no manifesto ou na seção "## 6. Scripts" não é tratado como script do método.
- `grep -n "'^.method/scripts/'" .method/scripts/check-docs.sh` não acha nada.
- Prova na parada: `validate.sh`, `check-docs.sh` e o CI do PR verdes.

1. Teste que falha no código atual. modelo: sonnet · esforço: low · motivo: peso light de .method/scripts/lib/weights.tsv (achado pequeno)
2. Escapar o ponto nas duas linhas. modelo: sonnet · esforço: low · motivo: peso light de .method/scripts/lib/weights.tsv (achado pequeno)
