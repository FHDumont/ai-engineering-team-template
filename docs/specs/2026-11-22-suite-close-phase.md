# Spec: suíte abaixo da meta com a máquina carregada (issue #76)

Fase solo do grupo `estrutura`, `end:auto-close`, depois do merge da #71 e da #74 (mesmos testes do `close-phase.sh`). Autorização do dono na madrugada de 22/11: achado novo de estrutura entra antes de liberar os repos. Meta do projeto: `validate.sh` abaixo de 240 s (`.github/time-targets.tsv`).

## Fase #76 — test_close_phase.sh mais barato

Arquivos previstos: `scripts/tests/test_close_phase.sh`, `scripts/tests/lib.sh` (só ajudantes novos, se precisar), `scripts/close-phase.sh` só se um caminho de teste caro tiver uma opção de teste já prevista, `docs/process-design.md` §6.4 (o número medido). Não muda o comportamento do `close-phase.sh` no uso real.

Pronto quando: o da issue #76, mais: a suíte completa abaixo de 240 s com a máquina livre e sem falha por tempo com ela carregada; o `test_close_phase.sh` corta as chamadas repetidas ao `close-phase.sh` (por exemplo partir o arquivo em vários testes que rodam em paralelo pela #42, ou montar o repositório temporário uma vez e reaproveitar), sem perder nenhum caso coberto. Antes e depois no PR, com a carga do momento.

1. Medir o `test_close_phase.sh` por caso e cortar o maior custo, sem perder casos; antes e depois no PR. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
