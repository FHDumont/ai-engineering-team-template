# Spec: o close-phase.sh refaz o PR com commit que a base já tem (issue #262)

Fase solo. Modo de fim: end:auto-close. Grupo: commit-duplicado.

## Fase #262 — commit já aplicado na base vira redo, não loop de merge

Fecha: #262.

Arquivos: `scripts/close-phase.sh` (a leitura do `--check`, que o `--merge` também roda), `scripts/redo-phase.sh` só se precisar, `scripts/tests/test_close_phase_stale_base.sh` (ou o teste do `--check` com o `gh` falso). Área sensível: `scripts/close-phase.sh` (classe `gate`): o merge pede o segundo parecer do `close-reviewer` ("enfraquece o portão?").

Decisão (sem grilling, passo reversível): o conserto é no `close-phase.sh --check`, não no `phase-start.sh`. Ele pega também outros commits duplicados, não só o da spec, e deixa como está a cópia da spec em cada branch, que o `check-docs.sh` de cada fase precisa.

Pronto quando:

- `close-phase.sh --check` (e o `--merge`, que o roda) usa `git cherry <base> HEAD` para ver se a branch tem um commit que a base já tem, mesmo com outro SHA. Se tiver, chama o `redo-phase.sh` como faz com DIRTY/CONFLICTING (sem esperar a CI e sem perguntar), e sai 0 com o PR novo (sob `--merge`, sai 6, como hoje).
- Branch sem commit já aplicado: nada muda. PR só atrasado, sem commit duplicado, continua não sendo refeito.
- O `--help` cita o caso.
- Teste que falha no código atual: duas branches com o mesmo commit de spec; depois de a primeira entrar na base, o `--check` da segunda chama o `redo-phase.sh`.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida, área gate)
2. A leitura do `git cherry` no `--check` e o `--help`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida, área gate)
