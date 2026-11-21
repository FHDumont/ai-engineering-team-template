# Spec: performance e progresso visível (issues #39, #40, #32 e #36)

Grupo `performance`, duas fases em paralelo, sem arquivo de código em comum. Pedido do dono: rodar antes de atualizar os outros repos. Economia de token continua sendo regra: o agente não lê o progresso, só o resultado curto e o caminho do log.

Decisões do dono no grilling: os achados pequenos #36 e #32 entram na fase #40 (mesmos scripts de abertura); o filtro do CI pula os testes quando só muda doc e quando o código não mudou desde um commit já testado, sem perguntar ao dono (o ok do `ci.yml` está na #39); o progresso fica num lugar por máquina (`~/.cache/ai-method/progress/`), lido pelo painel do dono (claude-runs-painel, issue própria para a UI com streaming); a #39 mede e já aplica os cortes pequenos e seguros, e os grandes viram issues.

## Fase #40 — progresso visível dos scripts longos

Objetivo: o dono e o painel veem em que passo está cada script longo, há quanto tempo e quanto falta.

Arquivos previstos: `scripts/start-headless.sh` (#36), `scripts/lib/progress.sh` (novo), `scripts/progress.sh` (novo, leitura para o dono), `scripts/validate.sh` (só as chamadas de progresso), `scripts/phase-start.sh` e `scripts/new-phase.sh` (só as chamadas), `scripts/status.sh` (uma linha com o passo atual), `scripts/tests/` (teste novo), `docs/process-design.md` §6 (formato). Não toca `scripts/close-phase.sh` nem as skills (são da #39); as chamadas de progresso no `close-phase.sh` ficam para a #39, que já mexe nele.

Pronto quando:
- `scripts/lib/progress.sh` grava, em `~/.cache/ai-method/progress/<repo>-<issue>.jsonl` (sem fase: `<repo>-main.jsonl`), uma linha JSON por evento, só com append: `ts`, `repo`, `issue`, `script`, `pid`, `step`, `done`, `total`, `elapsed_s`, `state` (`start`, `step`, `end`, `fail`). Feito para leitura por streaming (`tail -f`), sem reescrever o arquivo.
- `validate.sh` grava cada teste (`tests 23/49 test_close_phase.sh`) e o lint; `phase-start.sh` e `new-phase.sh`, cada passo da abertura.
- `scripts/progress.sh [--repo r] [--issue n] [--follow]` mostra para o dono o script rodando, o passo e o tempo; `status.sh` cita o passo atual numa linha.
- A saída para o agente não cresce: só o resultado e o caminho do log.
- Arquivo de fase encerrada some na limpeza (ou passa de 7 dias); o formato fica documentado no `process-design` §6 para o painel.
- #36: o `start-headless.sh` lê a spec do worktree da fase, com teste em que a spec só existe na branch.
- #32: o `phase-start.sh` separa falha da API do GitHub de CI ausente na base, com teste dos dois casos.
- O PR fecha #40, #36 e #32.
- Testes cobrem a gravação, o formato e a leitura; `scripts/validate.sh` e `scripts/check-docs.sh` saem 0.

1. `lib/progress.sh`, as chamadas no `validate.sh`, no `phase-start.sh` e no `new-phase.sh`, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. `scripts/progress.sh`, a linha no `status.sh` e o formato no `process-design` §6, com testes. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
3. #36 e #32, com testes que falham no código antigo. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`

## Fase #39 — medir e cortar o tempo das fases

Objetivo: saber onde vai o tempo de uma fase, cortar os ganhos fáceis e transformar os grandes em issues. Termina em `end:lab-test`: o dono sente a diferença numa fase real antes de fechar.

Arquivos previstos: `.github/workflows/ci.yml` (filtro dos testes, ok do dono já dado na #39), `scripts/close-phase.sh`, `scripts/trace-view.py` (divisão do tempo por fase), `scripts/tests/`, `.claude/skills/execute/SKILL.md`, `.claude/skills/close-phase/SKILL.md`, `.claude/agents/close-reviewer.md`, `docs/process-design.md`. Não toca `scripts/validate.sh`, `scripts/phase-start.sh` nem `scripts/new-phase.sh` (são da #40).

Pronto quando:
- `trace-view.py --timings [--issue n]` divide o tempo das fases do trace: abertura, cada etapa, `validate.sh`, `--prepare`, CI do PR, revisão (cada rodada), `redo-phase.sh`, merge e limpeza.
- Relatório na issue #39 com as fases do grupo fases-e-maquina e os 3 maiores custos, cada um com causa e corte.
- Cortes pequenos e seguros aplicados aqui, por exemplo: o `--prepare` não roda a suíte de novo quando o HEAD é o mesmo de uma rodada verde já gravada; a revisão da rodada 2 olha só o diff desde a rodada 1. Cada corte com teste.
- O job `tests` do `ci.yml` pula quando só muda doc (`*.md`, `docs/`, CHANGELOG, ROADMAP, remoção em `docs/specs/`) e o check `CI` fica verde para o portão.
- Cortes grandes viram issues com `size:*`.
- Medida combinada: mediana e p90 da fase e do `validate.sh` no `machine-slots.sh --report`, antes e depois.
- `scripts/validate.sh` e `scripts/check-docs.sh` saem 0.

1. `trace-view.py --timings` e o relatório na issue. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. Cortes pequenos no `close-phase.sh`, nas skills e no revisor, com testes; issues dos cortes grandes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (portão do merge, caminho sensível)`
