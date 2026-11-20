# ADR-003: Arquivos gerados entram por um PR só deles

- Situação: vigente
- Data: herdada do template
- Fase/PR: herdada do template

## Contexto

Se cada fase regera `CHANGELOG.md` e `ROADMAP.md` no próprio PR, duas fases paralelas sempre conflitam nesses arquivos, e o conflito vira pergunta ao dono do repo. A `main` exige `CI` e `review/independent`, inclusive de admin, então ninguém escreve nela direto.

## Decisão

Nenhuma fase gera esses dois arquivos. A sessão principal roda `scripts/gen-docs.sh` uma vez, depois do último merge: ele abre um PR que contém só `CHANGELOG.md` e `ROADMAP.md`, lê do GitHub a lista de arquivos do PR e, se houver apenas esses dois, publica `review/independent` e faz o merge por rebase, lido de volta. Qualquer outro arquivo no PR: sai com erro, sem status e sem merge.

PR em conflito com a `main` é refeito pelo `scripts/redo-phase.sh`, chamado pelo `close-phase.sh --check` na sessão da fase, sem pergunta.

## Consequências

Fases paralelas deixam de conflitar em arquivos gerados. Existe um caminho de merge sem revisor, restrito pelo script aos dois arquivos gerados; o `CI` continua exigido. Os PRs de `gen-docs/*` ficam fora do changelog. Entre o último merge e o `gen-docs.sh`, os dois arquivos ficam atrasados na `main`.
