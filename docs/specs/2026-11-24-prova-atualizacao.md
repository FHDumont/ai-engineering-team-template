# Spec: a atualização de c1b76da passa só pelo guia (issue #207)

Uma fase, solo. Modo de fim: end:auto-close. Grupo: atritos. Depois do merge, a gerenciadora refaz a prova local num repo de mentira em `c1b76da`, publica o aviso na #166 e fecha a #165 e a #166.

## Fase #207 — arquivos do repo com padrão do template e find-base rápido

Fecha: #207.

Arquivos: `scripts/method-diff.sh`, `scripts/tests/test_method_diff.sh`, `README.md` (seção de atualização), `.github/update-notice.md`, `scripts/tests/test_update_notice.sh`. Área sensível: não.

Pronto quando:

- teste vermelho no código atual: repo de mentira em `c1b76da`, com `labels.tsv` sem `group:*` e um script só do repo, atualizado só pelo que o guia manda; `check-docs.sh` sai 0;
- `method-diff.sh` lista como `missing` os arquivos do repo que têm padrão do template (`.github/required-checks`, `.github/headless`, `.github/update-notice.md`, `.github/label-areas.tsv`, `.github/ci-extra-jobs`) quando faltam, e não os sobrescreve quando existem; o guia diz para trazer o padrão;
- o guia diz que a frase antiga do `docs/STATE.md` ("o job `tests` roda em todo PR") sai na revisão do STATE, citando a mensagem do `check-docs.sh`;
- `method-diff.sh --find-base` num repo de 2 commits vindo de `c1b76da` sai em menos de 30 s (hoje passa de 15 min); teste com limite de tempo folgado.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção, um commit por item. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
