# ADR-005: Pesos num arquivo e par real conferido antes da primeira etapa

- Situação: vigente
- Data: herdada do template
- Fase/PR: herdada do template

## Contexto

Agentes e skills que fixam nomes de modelo não rodam num plano sem esses modelos. E o par pedido ao `start_session` não é garantido pelo app: uma fase pode pedir um par e rodar inteira em outro, sem aviso.

## Decisão

Usamos `scripts/lib/weights.tsv` como única fonte dos pares (`light`, `medium`, `strong`, `reviewer`, `triage`), lida por `scripts/weights.sh`; o padrão roda só com o modelo básico em esforço baixo ou médio. O hook `block-agent-pair.sh` recusa o `close-reviewer` e o `triage` fora do par do peso deles. O `check-env.sh` lê o par real da sessão filha (modelo da transcrição, esforço do ambiente) e só grava `phase_session` se cada um for o da spec ou o da sessão que abriu a fase; senão sai 1 e o portão do merge fica fechado. O `close-phase.sh --prepare` escreve a tabela pedido × usado do PR a partir do trace.

## Consequências

Trocar de plano é editar um arquivo. A divergência de par aparece antes de qualquer etapa, e não depende do que o app entrega. O modelo real depende do formato da transcrição do harness (`projects/*/<sessão>.jsonl`): se ele mudar, o `check-env.sh` sai 1 com "cannot read the real pair" e a leitura precisa ser ajustada.
