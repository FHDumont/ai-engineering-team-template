# Spec: cortes grandes de tempo (issues #42, #43, #44, #45 e #50)

Grupo `performance-2`, quatro fases sem arquivo de código em comum, em paralelo até o limite de 3 fases por máquina (a #45 abre quando liberar a primeira vaga). Pedido do dono: resolver antes de atualizar os 6 repos. Meta do projeto (`.github/time-targets.tsv`): fase abaixo de 45 min, `validate.sh` abaixo de 240 s. Cada fase mede antes e depois com `scripts/machine-slots.sh --report` e `scripts/trace-view.py --timings` e cita os números no PR.

Suposições (sem pergunta ao dono): a #42 roda os testes em paralelo e mantém a suíte completa na CI (não corta cobertura); a #45 usa a regra que já existe ("dúvida em passo reversível: siga e relate"), agora com um relatório único no PR.

## Fase #42 — suíte em paralelo

Arquivos previstos: `scripts/validate.sh`, `scripts/tests/lib.sh`, `.github/workflows/ci.yml`, testes que dependem de ordem ou de pasta comum, `docs/process-design.md` §6.4 (parâmetro novo de paralelismo, documentado como os da #9). Não toca `phase-start.sh`, `check-env.sh`, as skills nem os agentes.

Pronto quando: o da issue #42, mais: o número de testes em paralelo é um parâmetro de `~/.config/ai-method/machine-limits.env` (padrão pela quantidade de CPUs, respeitando as vagas da #9); cada teste roda em pasta temporária própria; a saída para o agente continua curta e o progresso da #40 conta os testes como hoje. O ok do dono para o `ci.yml` já está na #39.

1. Testes independentes entre si (pastas temporárias próprias), com a suíte passando em série. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. Execução em paralelo no `validate.sh` e na CI, com o parâmetro documentado e a medida antes e depois. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`

## Fase #43 — revisor usa o resultado da CI

Arquivos previstos: `.claude/agents/close-reviewer.md`, `.claude/skills/close-phase/SKILL.md`, `scripts/tests/test_phase_texts.sh`. Não toca scripts.

Pronto quando: o da issue #43.

1. Texto do revisor e da skill, com o teste de textos. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Fase #44 — abertura abaixo de 3 min (com a #50)

Arquivos previstos: `scripts/phase-start.sh`, `scripts/new-phase.sh`, `scripts/open-parallel.sh`, `scripts/start-headless.sh`, `scripts/check-env.sh`, `scripts/tests/test_phase_start.sh`, `scripts/tests/test_phase_scripts.sh`. Não toca `validate.sh`, `ci.yml`, as skills nem os agentes.

Pronto quando: o das issues #44 e #50. A medida por passo vem do progresso da #40 (`~/.cache/ai-method/progress/`). O PR fecha #44 e #50.

1. Medir a abertura por passo e cortar o maior, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. #50: a cópia solta da spec só fica por uma `## Fase #n` ainda não aberta, com teste que falha no código antigo. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Fase #45 — perguntas ao dono em lote

Arquivos previstos: `.claude/skills/execute/SKILL.md`, `.claude/skills/plan/SKILL.md`, `AGENTS.md`, `docs/process-design.md` §2.2, `scripts/tests/test_phase_texts.sh`. Não toca scripts.

Pronto quando: o da issue #45, mais: a fase só para para o dono em ação sensível ou irreversível (lista do `AGENTS.md`, "Quando perguntar: sempre"); o resto vira uma seção "Decisões tomadas sem perguntar" no PR, que o dono lê no fim; o grilling do `plan` junta as perguntas num quadro só.

1. Textos das skills `execute` e `plan`, do `AGENTS.md` e do `process-design`, com o teste de textos. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`
