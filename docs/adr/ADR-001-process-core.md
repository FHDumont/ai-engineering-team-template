# ADR-001: Núcleo do processo com portão único de merge

- Situação: vigente
- Data: herdada do template
- Fase/PR: herdada do template

## Contexto

Um processo de agentes que carrega muito texto antes de planejar e registra cada fase em vários lugares fica caro e diverge. Quando o dono do repo, os agentes e os bots usam a mesma conta do GitHub, a aprovação de PR não serve como controle.

## Decisão

Adotamos o desenho de `docs/process-design.md`: a issue é a entrada (templates Markdown, labels automáticas); o contexto fixo é pequeno (`AGENTS.md` ≤500 palavras, `docs/STATE.md` ≤500, este índice); os fluxos repetidos são scripts testados que o agente roda, inclusive o `setup-repo.sh`; e todo merge passa por um portão só: o check `CI` mais o status `review/independent`, com 0 aprovações, histórico linear, proteção valendo para admins e merge só por rebase. Caminhos e áreas sensíveis recebem `needs-owner-ok` e nunca fecham sozinhos. A assinatura de IA é barrada em quatro camadas (configuração, `AGENTS.md`, hook e CI).

## Consequências

- Nenhum merge como admin: um erro no CI bloqueia tudo até ser corrigido por PR.
- A revisão independente é salvaguarda de processo, não de segurança (mesma conta); uma GitHub App para o revisor pode vir depois.
- `CHANGELOG.md` e `ROADMAP.md` são gerados e o `docs/STATE.md` guarda só o estado atual; o histórico fica no git e nos PRs.
- O CI precisa de um agregador para eventos de label não esconderem lint e testes.
