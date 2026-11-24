# Spec: docs do método na atualização (issue #231)

Fase solo, achada na segunda prova local do grupo segunda-leva. Modo de fim: end:auto-close. Grupo: segunda-leva. Depois do merge, a gerenciadora repete a prova `eaeaaea` → `main` e atualiza as issues dos adotantes.

## Fase #231 — method-diff e --apply cobrem os docs do método

Fecha: #231.

Arquivos: `scripts/method-diff.sh`, `scripts/fetch-template.sh`, `.github/method-files.txt` (só se a lista entrar lá), `scripts/tests/test_method_diff.sh`, `scripts/tests/test_fetch_template.sh`. Área sensível: nenhuma do dono.

Pronto quando:

- `method-diff.sh` compara os docs do método fora das pastas do manifest: `AGENTS.md`, `CLAUDE.md`, `docs/process-design.md`, `docs/adr/TEMPLATE.md`, `docs/adr/INDEX.md`, os ADRs do template e `.cursor/rules/*`. `README.md`, `CONTEXT.md`, `docs/STATE.md`, `docs/BOTS.md`, `docs/repo-notes.md`, `app/`, `CHANGELOG.md` e `ROADMAP.md` continuam do repositório;
- `--apply` traz esses docs quando `outdated` ou `missing`; o `--notice` lista os `adapted`;
- teste: repo na origem com o `docs/process-design.md` da origem, e o `--apply` traz o do destino (falha no código atual);
- prova na parada: `validate.sh` e `check-docs.sh` verdes. A prova `eaeaaea` → `main` com `validate.sh --full` é da gerenciadora, depois do merge.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
