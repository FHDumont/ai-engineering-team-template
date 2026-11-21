# Spec: fases e carga da máquina (issues #7, #8, #9, #10, #11)

Grupo `fases-e-maquina`, em duas ondas. Todas `end:auto-close`.

- **Onda 1, em paralelo:** #7, #9 e #10. Nenhum arquivo de código em comum: #10 é a única que toca `scripts/phase-start.sh`, #7 a única que toca `scripts/close-phase.sh`, e #9 a única que toca `scripts/validate.sh`, `scripts/new-phase.sh` e `scripts/open-parallel.sh`.
- **Onda 2, depois do merge da onda 1, em paralelo:** #8 (depende da #10, mesmo `phase-start.sh`) e #11 (depende da #7, mesmo `close-phase.sh`, e das filhas headless da #10).
- `docs/process-design.md`, `README.md` e `AGENTS.md` são texto: cada fase muda só a sua seção; conflito vai pelo `redo-phase.sh`.

Decisões do dono no grilling: #10 abre a filha headless (`claude -p`) quando o app recusa o `start_session`; #9 usa vagas globais, e a carga entra só como aviso, com o portão de carga no roadmap (#12) e uma medição de tempos que diga se deu certo; #8 cala quando nada muda e o batimento só nasce com a primeira filha rodando.

## Fase #10 — início de fases com agentes

Objetivo: a gerenciadora abre a fase sem o clique no cartão quando o app recusa o `start_session` (Remote Control).

Arquivos previstos: `scripts/phase-start.sh`, `scripts/start-headless.sh` (novo), `scripts/check-env.sh` (só se o par da filha headless precisar de outra leitura), `scripts/tests/test_phase_start.sh` e o teste novo, `.claude/skills/plan/SKILL.md`, `.claude/skills/execute/SKILL.md`, `docs/process-design.md` §4.3, `AGENTS.md` (regra 9, se mudar). Não toca `scripts/close-phase.sh`, `scripts/validate.sh`, `scripts/new-phase.sh` nem `scripts/open-parallel.sh`.

Pronto quando:
- O que o Remote Control recusa e o que aceita fica medido e escrito no `process-design` §4.3 (VERIFIED ou INFERRED, como no comentário da #11).
- `start_session` recusado: o passo da gerenciadora roda `scripts/start-headless.sh <n>`, que abre a filha como `claude -p` em segundo plano, no worktree, com o par da spec, o prompt da skill `execute`, log em `.worktrees/issue-<n>/.process/headless.log` (fora do git) e o PID gravado no trace (`phase_headless`). O cartão deixa de ser o caminho padrão; fica só quando o `claude` não existe ou o script falha.
- A filha headless roda o `check-env.sh` como a do app e grava `phase_session`; o portão do merge não muda.
- Pergunta da filha headless ao dono: comentário na issue (ela não tem quadro); a gerenciadora repassa a resposta por `claude -p --resume` com o id gravado no trace.
- `--help` do script novo; testes com um `claude` falso cobrem a abertura, o par passado, o PID no trace e a falha; `scripts/validate.sh` e `scripts/check-docs.sh` saem 0.

Suposições: o painel do dono (fora deste repo) lê o log e o trace para acompanhar a filha headless; esta fase só garante os dois no lugar fixo acima.

1. Medir o Remote Control e escrever o resultado no §4.3. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (arquitetura do fluxo de sessões)`
2. `scripts/start-headless.sh`, a chamada nos passos do `phase-start.sh` e os testes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (arquitetura do fluxo de sessões)`
3. Textos: skills `plan` e `execute`, `process-design` §4.3. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Fase #9 — fases paralelas

Objetivo: a máquina inteira (todos os projetos, bots e pessoas) não passa de N validações e M fases ao mesmo tempo, e há números que mostrem se o tempo das fases melhorou.

Arquivos previstos: `scripts/validate.sh`, `scripts/machine-slots.sh` (novo), `scripts/lib/slots.sh` (novo), `scripts/lib/machine-limits.env.example` (novo), `scripts/new-phase.sh`, `scripts/open-parallel.sh`, `scripts/tests/test_validate.sh` e o teste novo, `docs/process-design.md` §6, `README.md`. Não toca `scripts/phase-start.sh` nem `scripts/close-phase.sh`.

Pronto quando:
- Vagas globais em `~/.cache/ai-method/slots/` (locks por `mkdir`), duas classes: `validate` (padrão 2) e `fase` (padrão 3). Cada vaga guarda repositório, issue, PID e início; vaga de PID morto ou de worktree que não existe mais é liberada sozinha.
- `validate.sh` sem vaga espera na fila mostrando "aguardando vaga" e quem ocupa, com timeout (padrão 20 min); um segundo `validate.sh` no mesmo worktree não dispara outro: espera o que roda e devolve o resultado dele.
- Durante a fase, `validate.sh --lint` só passa o `shellcheck` nos arquivos alterados contra a `main`; a validação completa fica no `close-phase.sh --prepare` e na CI (`--full` força tudo).
- `new-phase.sh` e `open-parallel.sh` pegam a vaga `fase`; sem vaga, saem com código próprio, sem criar nada, e dizem quem ocupa.
- Carga só como aviso: `machine-slots.sh --status` e o início da fase mostram load1, memória livre e swap contra os limiares, sem bloquear (o portão é a #12).
- Medição: cada validação e cada fase gravam espera e duração em `~/.cache/ai-method/history.tsv`; `machine-slots.sh --report [--days 7]` mostra mediana e p90 de espera e duração por classe e por repositório, para comparar antes e depois.
- Limites em `~/.config/ai-method/machine-limits.env`, criado do `.example` na primeira execução; cada parâmetro (nome, padrão, efeito, unidade) documentado no `.example` com comentário e numa tabela no `process-design` §6 e no README.
- Testes cobrem fila, timeout, vaga órfã, lock por worktree, lint incremental e o relatório; `scripts/validate.sh` e `scripts/check-docs.sh` saem 0.

Suposições: `HOME` comum a todos os projetos da máquina; testes usam um `HOME` temporário.

1. Vagas, lock por worktree e fila no `validate.sh`, com testes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (arquitetura, recurso compartilhado da máquina)`
2. Vaga `fase` no `new-phase.sh` e no `open-parallel.sh`, lint incremental, aviso de carga, histórico e `--report`, com testes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (arquitetura, recurso compartilhado da máquina)`
3. `.example` comentado, tabela no `process-design` §6 e no README. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Fase #7 — modo sem proteção de branch

Objetivo: o método funciona em repo privado de plano gratuito, sem proteção da `main`, mantendo as travas por script.

Arquivos previstos: `scripts/setup-repo.sh`, `scripts/close-phase.sh`, `scripts/end-check.sh`, `.githooks/` (push na `main`), `.claude/skills/setup/SKILL.md`, `scripts/tests/`, `README.md`, `docs/process-design.md` §10, `docs/STATE.md` (pontos de atenção). Não toca `scripts/phase-start.sh` nem `scripts/validate.sh`.

Pronto quando: o da issue #7.

Suposições: o modo fica numa variável do repositório (como o "não" das ofertas); caminho sensível (`close-phase.sh`), então o PR pode pedir `needs-owner-ok`.

1. Detecção e registro do modo no `setup-repo.sh`, `--check` e `end-check.sh`, com testes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (proteção e permissões do repo)`
2. Portão do `close-phase.sh --merge` pela API e hook de push na `main`, com testes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (proteção e permissões do repo)`
3. Textos: README, `process-design` §10, skill `setup`, `STATE.md`. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Fase #8 — batimento só avisa quando o estado muda (onda 2)

Objetivo: o batimento não polui o chat.

Arquivos previstos: `scripts/phase-start.sh`, `scripts/tests/test_phase_start.sh`, `AGENTS.md` (regra 3), `docs/process-design.md` §4.3, `.claude/skills/plan/SKILL.md`, `.claude/skills/integrate/SKILL.md` (se o texto do batimento mudar lá).

Pronto quando: o da issue #8, mais o comentário: o batimento só é criado depois que `list_sessions` mostra a primeira filha rodando (app ou headless da #10); com cartão esperando, não há batimento e a gerenciadora retoma quando o dono escrever.

1. Texto e ordem dos passos no `phase-start.sh`, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. Exceção na regra 3 do `AGENTS.md`, `process-design` §4.3 e skills. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Fase #11 — fechar sessões e MCPs no fim da fase (onda 2)

Objetivo: fase fechada não deixa processo nem MCP órfão, e o dono sabe o que arquivar.

Arquivos previstos: `scripts/close-phase.sh` (`--cleanup`), `scripts/sessions.sh` (novo), `scripts/tests/` (teste novo e `test_cleanup.sh`), `.claude/skills/execute/SKILL.md`, `.claude/skills/close-phase/SKILL.md`, `.claude/skills/integrate/SKILL.md`, `docs/process-design.md`.

Pronto quando: o da issue #11, com o comentário "Arquivar x fechar x deletar":
- `close-phase.sh --cleanup` encerra os processos cujo `cwd` está no worktree da fase (servidores de teste, watchers, `validate.sh`), nunca um processo `claude` filho do `Claude.app`, e encerra a filha headless da #10 (PID do trace) com os MCPs dela.
- Mensagem de fim: "Arquive esta sessão no app Claude (menu ⋯ → Archive) …; não delete; só fechar a aba não basta", e as outras sessões não arquivadas do mesmo repo paradas há mais de N horas (N em `~/.config/ai-method/machine-limits.env`, documentado como na #9).
- `scripts/sessions.sh --list` (sessões e MCPs por repo, idade, CPU, RAM) e `--close-idle` (só headless paradas, nunca filhas do `Claude.app`).
- Testes com processos falsos; `scripts/validate.sh` e `scripts/check-docs.sh` saem 0.

Suposições: identificar processos pelo `cwd` (lsof) em vez de gravar PIDs no `phase-start.sh`, para não tocar o arquivo da #8.

1. Limpeza no `--cleanup` e `scripts/sessions.sh`, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. Mensagem de fim e textos das skills e do desenho. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Achados do claude-runs-painel (onda 3)

Os achados #17 a #20 entraram no grupo com o ok do dono, antes das issues de atualização nos repos que usam o template. #18, #19 e #20 em paralelo (arquivos separados); #17 depois da #8 (mesmo `phase-start.sh`) e da #18 (a mesma linha de dependência faltando). Decisão do dono na #17: a suíte de testes roda só no fim e na CI, não na abertura.

## Fase #18 — dependência faltando no validate.sh

Arquivos previstos: `scripts/validate.sh`, `scripts/tests/test_validate.sh`. Não toca `scripts/check-env.sh` (a checagem de ambiente da abertura é da #17), `scripts/phase-start.sh`, `scripts/new-phase.sh` nem `scripts/open-parallel.sh`.

Pronto quando: o da issue #18, só no `validate.sh` (que no fim roda pelo `close-phase.sh --prepare`); a linha do `check-env.sh` fica com a #17.

1. Linha de dependência faltando no `validate.sh`, com teste. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`

## Fase #19 — arquivo temporário único por fase

Arquivos previstos: `.claude/skills/execute/SKILL.md`, `.claude/skills/close-phase/SKILL.md`, `.claude/skills/ask-bot/SKILL.md`, `.claude/agents/`, `scripts/tests/test_phase_texts.sh`. Mexe só nas linhas de arquivo temporário das skills; a #11 mexe na mensagem de fim delas, e conflito de texto vai pelo `redo-phase.sh`.

Pronto quando: o da issue #19.

1. Textos das skills e agentes e o teste de textos. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Fase #20 — chaves parecidas no erro do secret.sh

Arquivos previstos: `scripts/lib/secret.sh`, `scripts/tests/test_secret.sh`.

Pronto quando: o da issue #20.

1. Nomes das chaves `BOT_WEBHOOK_*` no erro, sem valores, com teste. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Fase #17 — abertura sem suíte e sem sobra (depois da #8 e da #18)

Decisão do dono: teste só no fim. A abertura lê o check `CI` do commit base da `main` e faz uma checagem rápida de ambiente; o `check-env.sh` confere o par e o ambiente, sem `validate.sh --tests`; a suíte fica no `close-phase.sh --prepare` e na CI.

Arquivos previstos: `scripts/phase-start.sh`, `scripts/new-phase.sh`, `scripts/open-parallel.sh`, `scripts/check-env.sh`, `scripts/tests/test_phase_start.sh`, `scripts/tests/test_phase_scripts.sh`, `docs/process-design.md` §4.3.

Pronto quando: o das issues #17, #16 e #22. A #16 (modelo e esforço de cada filha no `status.sh` e nos passos da gerenciadora) saiu da #8 porque a filha headless não recebeu o brief; a #22 corrige isso (`start-headless.sh --brief`). O PR fecha #17, #16 e #22.

Arquivos a mais: `scripts/status.sh`, `scripts/tests/test_status.sh`, `scripts/start-headless.sh` e o teste dele.

1. CI do commit base e checagem de ambiente no lugar da suíte, na abertura e no `check-env.sh`, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. Desfazer o que a abertura criou quando ela falha, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
3. Par real de cada filha no `status.sh` e nos passos da gerenciadora (#16) e `--brief` no `start-headless.sh` (#22), com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
