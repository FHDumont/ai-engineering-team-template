# Spec: comunicação com bots e autoria visível (issue #34)

Fase solo do grupo `fases-e-maquina`, `end:auto-close`, em paralelo com a #33 (sem arquivo em comum). Achado do dumontech-midia #29: todos os comentários saem como a mesma conta, e dois pedidos ao bot foram por `gh issue comment` solto. Decisão do dono: cabeçalho de autoria agora; um usuário por papel (GitHub Apps) fica no roadmap.

Abertura por fora, com o ok do dono ("já pode abrir em paralelo para corrigir agora"): o `phase-start.sh` recusa toda fase até a #33 entrar, então esta fase abre pelo `scripts/new-phase.sh`. O merge segue pelo portão.

## Fase #34 — comunicação com bots

Arquivos previstos: `scripts/ask-bot.sh`, `scripts/wait-reply.sh`, `scripts/lib/` (cabeçalho de autoria), `scripts/open-issue.sh` (cabeçalho só nos comentários, se comentar), `.claude/hooks/` (hook novo e teste), `.claude/settings.json`, `.claude/skills/ask-bot/SKILL.md`, `docs/BOTS.md`, `AGENTS.md` (regra 6), `docs/process-design.md` §5, `scripts/tests/test_bots.sh`. Não toca `scripts/phase-start.sh`, `scripts/start-headless.sh` nem `.claude/skills/close-phase/SKILL.md` (são da #33); o cabeçalho nos comentários do `close-phase.sh` fica para quando a #33 entrar, numa linha da issue.

Pronto quando: o da issue #34.

1. Cabeçalho de autoria (lib) e `ask-bot.sh --append`, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. Hook `PreToolUse` contra comentário de agente sem cabeçalho ou com pedido a bot fora do `ask-bot.sh`, e o aviso cedo do `wait-reply.sh`, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
3. Textos: skill `ask-bot`, `docs/BOTS.md`, regra 6 do `AGENTS.md`, `process-design` §5. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`
