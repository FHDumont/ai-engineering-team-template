# Spec: permissões e headless (issues #93, #94, #95, #135 e #123)

Acompanhamento na #166. Uma fase, a #93, fecha as cinco. Decisões do dono já aprovadas em 2026-11-22. Modelo de execução: Grok, esforço médio. A linha abaixo é o par que `scripts/weights.sh medium` imprime.

Modo de fim: `end:auto-close`. Área sensível: `.claude/settings.json`, `scripts/setup-repo.sh`, `.github/sensitive-paths`. Solo.

## Fase #93 — adoção não alarga permissão nem solta trava

Arquivos previstos: `.claude/settings.json`, `.claude/hooks/block-dangerous-git.sh`, `scripts/setup-repo.sh`, `.github/sensitive-paths`, `scripts/phase-start.sh`, `scripts/start-headless.sh`, `scripts/status.sh`, `.claude/skills/plan/SKILL.md`, `.claude/skills/setup/SKILL.md`, `docs/process-design.md`, `README.md`, testes desses arquivos.

Pronto quando: o das issues #93, #94, #95, #135 e #123, com os critérios dos comentários.

1. `allow` lista os scripts do método pelo nome. Saem `Bash(scripts/*)`, `Bash(./scripts/*)` e `git push` genérico. Teste recusa `scripts/*` no allow. A adoção mostra o diff e espera ok antes de a sessão usar o settings novo. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (permissão)`
2. `block-dangerous-git.sh` barra `git clean -f` e `git branch -D`. Hook citado no settings que não existe faz a conferência falhar. O README manda inventariar hooks e deny existentes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (trava)`
3. O setup lista check que sai, `strict` que afrouxa, label em uso e a entrada no modo sem proteção. Sem ok, `--check` não fica limpo e nada disso é aplicado. Checks extras ficam em arquivo do repo. "Upgrade to GitHub" não grava o modo sozinha. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (proteção)`
4. A lista sensível do método fica no código: hooks, settings, githooks, actions, workflows com token, `procs.sh`, `sessions.sh`, `start-headless.sh`, `setup-repo.sh`. O arquivo do repo só acrescenta. A atualização soma caminho novo sem apagar o do repo. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (caminho sensível)`
5. Headless desligado por padrão. Recusa por falta de fala do dono vira cartão ou espera. Sem `--allowedTools Bash` além da filha do app. Fase sem `phase_session` aparece como "aberta, sem sessão". Cartão que já virou sessão fica `trabalhando`. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (headless)`
