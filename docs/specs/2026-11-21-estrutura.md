# Spec: estrutura antes de liberar os repos (issues #54, #62 e #66)

Grupo `estrutura`, três fases em paralelo, sem arquivo de código em comum. Pedido do dono: terminar tudo o que mexe na estrutura do método antes de abrir as issues de atualização nos 6 repos. A #12 foi fechada (perdeu o sentido) e a #35 fica no roadmap.

## Fase #66 — nenhum processo órfão (crítico)

Decisão do dono: processo órfão é crítico e não pode acontecer.

Arquivos previstos: `scripts/tests/lib.sh`, os testes que iniciam processos em segundo plano (o do `start-headless.sh` e outros que usam `&`), `scripts/validate.sh` (verificação de órfãos no fim), `scripts/sessions.sh` (marca órfão), `scripts/close-phase.sh` (só o `--cleanup` encerra órfão), `docs/process-design.md` §6.4. Não toca `scripts/phase-start.sh`, `.github/workflows/ci.yml`, `scripts/gen-docs.sh` nem `scripts/tests/test_phase_texts.sh` (são das outras fases).

Pronto quando: o da issue #66, com teste que deixa um processo de propósito e falha no código antigo.

1. Grupo de processos e trap em todo processo de fundo dos testes e scripts, com teste. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (decisão crítica do dono, bug sem causa única)`
2. Verificação de órfãos no fim do `validate.sh`, marca no `sessions.sh` e encerramento no `--cleanup`, com testes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (close-phase.sh é caminho sensível)`

## Fase #54 — PR de docs não quebra a main

Arquivos previstos: `.github/workflows/ci.yml`, `scripts/ci-gate.sh`, `scripts/gen-docs.sh`, `scripts/tests/test_phase_texts.sh`, o teste do workflow. Não toca `scripts/tests/lib.sh`, `scripts/validate.sh` nem `scripts/phase-start.sh`. O ok do dono para o `ci.yml` está na #39 e na #59.

Pronto quando: o da issue #54.

1. Arquivo lido por teste (ROADMAP.md, CHANGELOG.md) roda os testes de textos mesmo em PR só de doc, ou o `gen-docs.sh` roda esses testes antes do PR; o teste do intervalo antigo do batimento procura só o texto do batimento. Com teste que reproduz o caso da #44. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv`

## Fase #62 — portão espera a CI da main antes do job CI existir

Arquivos previstos: `scripts/phase-start.sh`, `scripts/tests/fakes/gh`, `scripts/tests/test_phase_start.sh`. Não toca os outros arquivos do grupo.

Pronto quando: o da issue #62.

1. Portão pelo workflow run do commit, com teste que reproduz o Tests em andamento sem o job CI e falha no código antigo. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (trava de entrada do método)`
