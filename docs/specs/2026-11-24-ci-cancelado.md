# Spec: job CI cancelado não trava o merge (issue #209)

Uma fase, solo. Modo de fim: end:auto-close. Grupo: atritos. Ok do dono: "está tudo aprovado" (2026-11-24, sessão principal).

## Fase #209 — cancelled conta como falha e o merge não prende a filha

Fecha: #209.

Arquivos: `scripts/rerun-ci.sh`, `scripts/close-phase.sh` (laço do `--merge --wait`), `.claude/skills/close-phase/SKILL.md`, `scripts/tests/test_rerun_ci.sh`, testes do `--merge --wait`. Área sensível: gate (segunda revisão, sem o dono).

Pronto quando:

- teste vermelho no código atual: run do `ci.yml` com o job `CI` `cancelled` no HEAD do PR; `rerun-ci.sh <run>` refaz o job (hoje sai com "has no failed job; nothing was rerun"); o limite de reruns continua;
- `close-phase.sh --merge --wait` vê um check `cancelled` no HEAD e sai na hora, com a causa e o comando `scripts/rerun-ci.sh <run>`, sem gastar as 120 tentativas; teste cobre;
- a skill `close-phase` manda rodar o `--merge --wait` em segundo plano, para a filha seguir recebendo mensagens da gerenciadora.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção, um commit por item. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
