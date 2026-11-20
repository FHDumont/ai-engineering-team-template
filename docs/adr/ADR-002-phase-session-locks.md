# ADR-002: Travas da sessão que abriu a fase

- Situação: vigente
- Data: herdada do template
- Fase/PR: herdada do template

## Contexto

A regra "a fase roda só em sessão filha" não se sustenta só com texto: um hook do agente lê poucas formas de comando e, se falha aberto, deixa passar; um portão que aceita trace redirecionado, sessão trocada por variável ou fase sem `phase_opened` também. O método precisa rodar com modelo leve: a regra precisa de trava que sai com erro.

## Decisão

- A identidade da trava é o par (`phase_opened` da issue no trace, `CLAUDE_CODE_SESSION_ID`). As travas leem sempre `.process/events.jsonl` do checkout principal (`phase_trace_file`); `PROCESS_EVENTS_FILE` só redireciona a gravação.
- A trava durável é do git: `reference-transaction` recusa que a sessão que abriu a fase mova a branch da fase ou o `HEAD` do worktree dela, por qualquer comando; `pre-commit`, `pre-merge-commit` e `pre-rebase` recusam antes, com mensagem limpa. Criar e apagar a branch passam, então o `new-phase.sh` cria a branch já sobre o commit da spec.
- Os hooks do agente (`block-phase-commit.sh`, `block-phase-edit.sh`) falham fechado e barram, para qualquer sessão, comando que define `CLAUDE_CODE_SESSION_ID` ou `PROCESS_EVENTS_FILE` e escrita à mão no trace.
- O portão do `--merge` aceita só a sessão que tem `phase_session` da issue e um evento gravado pelos hooks do harness, diferente da que abriu a fase.

## Consequências

- Os hooks do git sem `CLAUDE_CODE_SESSION_ID` (terminal, outra ferramenta) não recusam nada: a trava vale para sessões do agente.
- Uma linha do trace que não é JSON bloqueia a escrita no worktree e o merge até ser corrigida pelo dono.
- Os hooks do git moram no worktree (`core.hooksPath=.githooks`): apagar o arquivo do hook desliga a trava local; o portão continua valendo.
- A sessão que abriu a fase não refaz a fase em conflito: quem refaz é a sessão filha, pelo `redo-phase.sh` (ADR-003).
