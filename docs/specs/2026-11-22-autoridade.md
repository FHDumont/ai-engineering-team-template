# Spec: autoridade do recado, do parecer e da sessão (issues #122, #128 e #113)

Acompanhamento na #166. Uma fase só, a #122, fecha as três. Os comentários da #122 somam ao corpo: o ok do dono vale para um SHA; a filha do app também relê recados; a parada de lab-test recusa (saída 12) com recado sem resposta.

Modo de fim: `end:auto-close`. Área sensível: `scripts/close-phase.sh`, `.githooks/`, `.claude/hooks/`. Solo.

A linha abaixo é o par que `scripts/weights.sh medium` e `scripts/weights.sh strong` imprimem (modelo e esforço iguais neste arquivo de pesos).

## Fase #122

Arquivos previstos: `scripts/close-phase.sh`, `scripts/status.sh`, `.claude/skills/plan/SKILL.md`, `.claude/skills/close-phase/SKILL.md`, `.claude/skills/execute/SKILL.md`, `.claude/hooks/trace-event.sh`, `.githooks/pre-commit`, `.githooks/phase-guard.sh`, `docs/process-design.md`, testes desses arquivos.

Pronto quando: o das issues #122, #128 e #113, com os critérios dos comentários da #122.

1. Segurar o merge é comentário `Para: fase #n` na issue, para a filha do app e a headless, além da mensagem de sessão. O `--merge` relê esse recado imediatamente antes do `gh pr merge`. O ok do dono vale para um SHA: `--owner-ok` recebe o SHA e o script o confere com o HEAD. A parada de lab-test recusa (saída 12) com recado sem resposta. A filha do app também relê os recados antes de cada etapa. O ok dado no quadro não vence um recado posterior à abertura dele. Quadros de sessões diferentes sobre o mesmo merge não ficam abertos juntos, ou as opções dizem a ação inteira (incluindo o SHA). `modelo: sonnet · esforço: medium · motivo: peso strong (ok de merge sem SHA)`
2. O texto publicado em `review/independent` é a saída do revisor, sem reescrita. O `--publish-review` recusa texto que difere da saída gravada do subagente. Um teste cobre parecer reescrito e veredito trocado. A skill `close-phase` diz que o parecer vai inteiro. `modelo: sonnet · esforço: medium · motivo: peso strong (parecer reescrito)`
3. Commit de etapa no worktree sem `phase_session` da sessão é recusado, ou a falta é avisada já no primeiro commit. Fica definido o caso da fase que atualiza o próprio método, em que o `check-env.sh` muda no meio: o `phase_session` gravado no início da sessão continua válido; o commit que altera o `check-env.sh` não exige rodar o script novo antes de entrar. Um teste cobre a recusa. `modelo: sonnet · esforço: medium · motivo: peso medium (commit sem phase_session)`
