# Spec: o --merge --wait sai quando a CI do PR fica vermelha (issue #256)

Fase solo, em paralelo com a #249 (que no `close-phase.sh` só mexe em `registry_drop`; esta mexe no laço de espera do merge). Modo de fim: end:auto-close. Grupo: merge-wait.

## Fase #256 — o laço do merge lê os checks e sai na falha

Fecha: #256.

Arquivos: `scripts/close-phase.sh` (laço "waiting for the merge" do `--merge --wait`), `scripts/tests/test_close_phase_gate.sh` (ou o teste de `--merge` que já usa o `gh` falso; o executor escolhe), `scripts/status.sh` só se o texto da fase precisar mudar. Área sensível: `scripts/close-phase.sh` (classe `gate`): o merge pede o segundo parecer do `close-reviewer` ("enfraquece o portão?").

Pronto quando:

- A cada volta do laço, o `close-phase.sh --merge --wait` (com ou sem `--owner-ok <sha>`) lê o check `CI` e o status `review/independent` do HEAD do PR. Se qualquer um terminar em `failure` ou `cancelled`, ele sai na hora, com um código próprio citado no `--help` e com o run que falhou.
- A mensagem diz o próximo passo: corrigir num commit novo, ou `scripts/rerun-ci.sh` se for flake. Diz também que o ok do dono vale só para o SHA antigo.
- Check ainda em andamento ou verde: o laço segue como hoje. O portão não fica mais fraco: nada passa a mesclar sem `CI` e `review/independent` verdes.
- Teste que falha no código atual: com o `gh` falso, a CI vira `failure` no meio da espera e o `--wait` sai antes do prazo, com o código novo.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida, área gate)
2. A leitura dos checks no laço, a saída própria e o texto. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida, área gate)
