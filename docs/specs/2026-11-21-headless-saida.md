# Spec: filha headless solta da saída de quem chamou (issue #68)

Fase solo do grupo `estrutura`, `end:auto-close`. Liga-se à #66 (nenhum processo do método preso ou órfão): a filha headless não pode segurar o pipe de quem a chamou nem morrer junto com o grupo de processos dele.

## Fase #68 — start-headless.sh

Arquivos previstos: `scripts/start-headless.sh` e o teste dele. Não toca `scripts/tests/lib.sh`, `scripts/lib/procs.sh`, `scripts/sessions.sh` nem `scripts/phase-start.sh` (são da #66 e da #62).

Pronto quando: o da issue #68.

1. Filha com stdin de /dev/null, stdout e stderr só no log da fase e sessão de processos própria; teste com `| tail -2` que termina em segundos e falha no código antigo. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
