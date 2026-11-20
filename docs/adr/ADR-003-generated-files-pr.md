# ADR-003: Arquivos gerados e specs encerradas entram por um PR só deles

- Situação: vigente
- Data: herdada do template
- Fase/PR: herdada do template

## Contexto

Se cada fase regera `CHANGELOG.md` e `ROADMAP.md` no próprio PR, duas fases paralelas sempre conflitam nesses arquivos, e o conflito vira pergunta ao dono do repo. A `main` exige `CI` e `review/independent`, inclusive de admin, então ninguém escreve nela direto.

A spec de um grupo paralelo pode sobrar na `main`: a primeira fase a mantém (a outra issue está aberta) e a última, quando é refeita pelo `redo-phase.sh`, não a remove. O `end-check.sh` acusa a sobra, e sem um caminho pelo portão ela não sai.

## Decisão

Nenhuma fase gera esses dois arquivos. A sessão principal roda `scripts/gen-docs.sh` uma vez, depois do último merge: ele abre um PR que contém só `CHANGELOG.md`, `ROADMAP.md` e a remoção de cada spec de `docs/specs/` cujas issues citadas estão todas fechadas. Depois lê do GitHub os arquivos do PR e publica `review/independent` e faz o merge por rebase, lido de volta, quando há apenas esses dois arquivos e specs com status `removed` cujas issues estão todas fechadas. Qualquer outro arquivo, spec adicionada ou modificada, ou spec removida que cita issue aberta: sai com erro, sem status e sem merge.

O fecho da fase (`close-phase.sh`) segue removendo a spec quando a fase que fecha é a última aberta que ela cita; o `gen-docs.sh` remove a que sobrou. Não há outro caminho: nada de PR avulso nem de remoção à mão.

PR em conflito com a `main` é refeito pelo `scripts/redo-phase.sh`, chamado pelo `close-phase.sh --check` na sessão da fase, sem pergunta.

## Consequências

Fases paralelas deixam de conflitar em arquivos gerados. Existe um caminho de merge sem revisor, restrito pelo script aos dois arquivos gerados e à remoção de specs de issues fechadas; o `CI` continua exigido. Os PRs de `gen-docs/*` ficam fora do changelog. Entre o último merge e o `gen-docs.sh`, os dois arquivos ficam atrasados na `main`.
