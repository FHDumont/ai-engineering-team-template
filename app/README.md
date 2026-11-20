# App de exemplo

Esta pasta é só um marcador: existe para o workflow de exemplo `.github/workflows/deploy-example.yml` ter o que buildar. Troque-a pelo código do seu projeto.

- `app/build.sh <pasta-de-saída>` copia o `index.html` para a pasta de saída.
- O deploy roda só pelo `scripts/deploy.sh`, na sessão principal, no passo único de fim (`docs/process-design.md`, §9.4).
- Ao trocar de pasta, ajuste a linha `# deploy-paths:` do workflow de deploy, o filtro `app` do job `changes` no `ci.yml` e a label `area:app` em `.github/labels.tsv`.
