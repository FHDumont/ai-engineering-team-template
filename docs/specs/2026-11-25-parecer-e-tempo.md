# Spec: parecer literal do revisor e tempo do validate.sh (issues #258, #251)

Duas fases em paralelo, sem arquivo de código em comum (#258: `close-phase.sh`, hook do trace, `common.sh`; #251: `validate.sh`, `machine-slots.sh`). Modo de fim: end:auto-close nas duas. Grupo: parecer-e-tempo.

## Fase #258 — close-phase.sh --save-review grava o parecer literal

Fecha: #258.

Arquivos: `scripts/close-phase.sh`, `.claude/hooks/trace-event.sh`, `scripts/lib/common.sh` (ou uma lib nova em `scripts/lib/`), `.claude/skills/close-phase/SKILL.md`, `scripts/tests/test_close_phase_review.sh`, `.claude/hooks/tests/test_trace_event.sh`. Área sensível: `.claude/hooks/` (classe `owner-ok`) e `scripts/close-phase.sh` (classe `gate`): o merge pede o ok do dono, digitado na sessão da fase, e o segundo parecer do `close-reviewer` ("enfraquece o portão?").

Pronto quando:

- `close-phase.sh --save-review <agentId> [--gate]` acha a transcrição `subagents/agent-<agentId>.jsonl` da sessão, extrai o último texto com uma linha `Veredito:` e grava `.process/reviewer-<sha>.md` (ou `reviewer-gate-<sha>.md`) do HEAD. Sai com erro, sem gravar, quando o hash não é o `output_sha` que o trace guardou para aquele agente.
- O filtro de extração fica numa função só em `scripts/lib/`, usada pelo hook e pelo comando. O hash do hook não muda para o mesmo texto.
- A skill `close-phase` (passos 1a e 5 e o parecer `--gate`) manda usar `--save-review`, com o revisor em primeiro ou em segundo plano, e nunca gravar o parecer à mão.
- O `--publish-review` segue recusando um parecer editado.
- Teste que falha no código atual: uma transcrição de mentira de subagente em segundo plano; `--save-review` grava o arquivo, e o `--publish-review` aceita esse arquivo.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (comportamento novo, áreas owner-ok e gate)
2. A função de extração na lib, usada pelo hook, e o `--save-review`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (comportamento novo, áreas owner-ok e gate)
3. O texto da skill `close-phase` e o `--help`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (só texto)

## Fase #251 — o validate.sh mostra onde vai o tempo e cobra o repo só pela parte dele

Fecha: #251.

Arquivos: `scripts/validate.sh`, `scripts/machine-slots.sh`, `scripts/lib/slots.sh` (se o histórico mudar), `scripts/tests/test_validate.sh` e o teste do `--report`, `docs/process-design.md` §6.4 (meta de tempo). Área sensível: nenhuma.

Suposições (sem grilling, passo reversível; vão em "Decisões tomadas sem perguntar" no PR):

- O lint completo roda o shellcheck em paralelo (`AI_METHOD_TEST_JOBS` arquivos por vez), com a mesma saída e o mesmo código de saída.
- O tempo do `.github/validate-repo.sh` vai ao histórico como medida própria (`validate-repo`). O `.github/time-targets.tsv` do repo aceita essa medida, e o `--report` compara cada medida com a sua meta. A meta `validate` do método continua sendo a do método.

Pronto quando:

- O fim do `validate.sh` lista os 5 testes mais lentos com o tempo de cada um, e o tempo do lint e do bloco da aplicação.
- O shellcheck do lint completo roda em paralelo; com `AI_METHOD_TEST_JOBS=1`, em série, como hoje.
- `machine-slots.sh --report` imprime `info: time validate-repo ...` quando há histórico dessa medida, comparado com a linha `validate-repo` do `.github/time-targets.tsv` (ou com o padrão do método).
- Teste que falha no código atual: um `validate.sh` com um `.github/validate-repo.sh` de mentira grava a medida `validate-repo` no histórico.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes, e o tempo do `validate.sh --full` antes e depois citado no PR.

1. Teste que falha no código atual (medida `validate-repo`). modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (desempenho em script do método)
2. Shellcheck em paralelo, os mais lentos e a medida `validate-repo`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (desempenho em script do método)
3. O `--report` e o `process-design` §6.4. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (desempenho em script do método)
