# Spec: merge fora de fase (issue #161)

Acompanhamento na #166. Uma fase, a #161. O dono já decidiu: merge fora de fase só com o ok dele, preso ao SHA. A CI continua obrigatória. Esta fase não enfraquece o portão de uma fase.

Modo de fim: end:auto-close.

## Fase #161 — PR sem fase passa no mesmo portão

Arquivos: `scripts/close-phase.sh`, testes dele, `scripts/setup-repo.sh`, `docs/process-design.md` §10, `README.md` (o aviso antes de ligar a proteção). Não mexe em `ci.yml` nem no portão de `fix/issue-*`.

Pronto quando: um PR que não é branch de fase recebe `review/independent` e merge só com `--owner-ok` igual ao HEAD, CI verde e o texto da revisão independente daquele SHA; branch de fase continua no `--merge` atual; o setup e o README avisam isso antes de ligar a proteção.

1. Testes que falham no código anterior: publicar e mergear um PR sem fase exige `--pr`, `--owner-ok` igual ao HEAD, CI verde e o parecer salvo daquele SHA; SHA errado, CI ausente e branch `fix/issue-*` são recusados. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (portão)
2. O comando no `close-phase.sh` e o aviso no setup e no README, antes de a proteção ser ligada. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (portão)
