# Spec: suíte abaixo de 240 s, testes restantes (issue #81)

Fase solo do grupo `estrutura`, `end:auto-close`, em paralelo com a #76 (sem arquivo em comum). Autorização do dono na madrugada de 22/11: achado de estrutura entra antes de liberar os repos. Meta do projeto: `validate.sh` abaixo de 240 s.

## Fase #81 — test_phase_start e testes de hooks mais baratos

Arquivos previstos: `scripts/tests/test_phase_start.sh`, `.claude/hooks/tests/test_block_dangerous_git.sh`, `.claude/hooks/tests/test_block_phase_commit.sh` e um arquivo comum novo de preparo, se precisar (sem prefixo `test_`), `scripts/tests/test_start_headless.sh` (só a instabilidade sob carga). Não toca `scripts/tests/test_close_phase*.sh` nem `scripts/tests/close_phase_common.sh` (são da #76) e não muda o comportamento dos scripts e hooks testados.

Pronto quando: o da issue #81, mais: a suíte completa abaixo de 240 s com a máquina livre, sem perder nenhum caso coberto; o `test_start_headless.sh` não falha sob carga. Antes e depois no PR, com a carga do momento.

1. Partir ou baratear os três maiores testes (como a #76 fez com o `test_close_phase.sh`), sem perder casos; antes e depois. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`
2. `test_start_headless.sh` estável sob carga, com teste. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`
