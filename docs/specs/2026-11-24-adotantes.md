# Spec: o que a adoção num repo real quebrou (issues #245, #246, #247, #248)

Três fases em paralelo, sem arquivo de código em comum. Modo de fim: end:auto-close nas três. Grupo: adotantes. Depois do merge, a gerenciadora responde nos repos que abriram as issues (vaulty e o adotante de #166) que os ajustes locais podem sair.

## Fase #245 — os testes do método só varrem arquivos do método

Fecha: #245.

Arquivos: `scripts/tests/test_issue_refs.sh`, `scripts/tests/test_phase_texts.sh`, `scripts/tests/test_pipefail.sh`, `scripts/tests/test_workflow_tools.py` (só `app_filter_sample`). Área sensível: nenhuma.

Pronto quando:

- `test_issue_refs.sh` lê só os arquivos do manifesto (`.github/method-files.txt`), `scripts/lib/`, `ci.yml` e `issues-label.yml`.
- `test_phase_texts.sh` deixa de fora as ADRs do repo (`docs/adr/ADR-[0-9][0-9][0-9].md` que não estão no manifesto).
- A parte estática de `test_pipefail.sh` lê `scripts/*.sh`, `scripts/lib/*`, `.claude/hooks/*` e `.githooks/*`, não `git ls-files '*.sh'`.
- `test_workflow_tools.py`: sem a linha `echo "app=$(has '^(...)')"` no `ci.yml`, o teste usa um caminho padrão e não cai em `AttributeError`.
- Teste que falha no código atual: um repo de mentira com um script da aplicação que cita `#n` em `scripts/`, uma ADR `ADR-NNN.md` com "8 min", um `.sh` em `infra/scripts/` sem pipefail e um `ci.yml` sem a linha `app=`; os quatro testes passam nele.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Teste que falha no código atual (o repo de mentira). modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. Os quatro testes limitados aos arquivos do método. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #246 — grupo maior que o limite da máquina sai na hora

Fecha: #246.

Arquivos: `scripts/phase-start.sh`, `scripts/open-parallel.sh`, `scripts/tests/test_phase_start_slots.sh`, `.claude/skills/plan/SKILL.md`, `.claude/skills/triage/SKILL.md`, `.claude/agents/triage.md`. Área sensível: nenhuma.

Pronto quando:

- Com `needed > limit` (limite da classe `fase` de `machine-slots.sh`), `open-parallel.sh` sai com um código próprio (diferente de 75) e o texto do que fazer: abrir até L issues agora e o resto quando houver vaga.
- `phase-start.sh` não entra no laço de espera nesse código: sai na hora, sem criar nada, com o mesmo texto. O 75 de vagas ocupadas segue esperando como hoje.
- As skills `plan` e `triage` (e o agente `triage`) citam o limite da máquina ao sugerir quantas fases em paralelo.
- Teste que falha no código atual: limite 3 e 4 issues; o `phase-start.sh` sai em menos de 5 s com o código novo, sem branch nem worktree.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. O código novo no `open-parallel.sh` e no `phase-start.sh`, e o texto nas skills. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #247 — o ci.yml aceita runner próprio sem actions/* e sem gh

Fecha: #247 e #248.

Arquivos: `.github/workflows/ci.yml`, os testes do workflow (`test_workflow_tools.py` só na parte do checkout; a fase #245 mexe no `app_filter_sample`, então esta fase não toca nessa função), `docs/process-design.md` §9.2 e §9.3, `README.md` (adoção, passo 8). Área sensível: `.github/workflows/ci.yml` (classe `gate`): o merge pede o segundo parecer do `close-reviewer` ("enfraquece o portão?").

Decisões do dono (grilling): checkout pela variável `CI_CHECKOUT_CMD`; `runs-on` só documentado.

Resposta aos cinco pontos de #247 (vai no PR e num comentário na issue):

1. Checkout: muda no template. Cada `actions/checkout` vira dois passos: o `actions/checkout` com `if: vars.CI_CHECKOUT_CMD == ''` e um `run` com `if: vars.CI_CHECKOUT_CMD != ''` que roda o comando da variável passado por `env` (nunca `${{ }}` dentro do `run`), com uma variável de ambiente que diz se o passo pede histórico completo.
2. Leitura da base: muda no template. Os três "Checkout the … from the base" viram `git archive <base> .github scripts | tar -x -C base` em todo repo (o checkout antes traz a base no histórico).
3. `gh` fixado no primeiro CI: muda no template (é #248). Se a base não tem `.github/gh-pin` nem `.github/method-files.txt`, o runner não tem `gh` e o PR tem `.github/gh-pin`, o passo usa o pin do PR, com `::notice::`, nos dois passos que instalam o `gh`.
4. `runs-on` padrão: fica local. O README da adoção diz para definir `CI_RUNS_ON` (e `CI_CHECKOUT_CMD`, se for o caso) antes de abrir o PR de adoção.
5. Job extra num PR só de doc: muda só no desenho. `process-design` §9.3 diz que o job extra roda sempre e os passos pulam com `docs_only`, porque o `ci-gate.sh` reprova job extra `skipped`.

Pronto quando:

- Os cinco pontos acima estão no `ci.yml`, no `process-design` e no README, e o comentário na issue responde cada um.
- Sem `CI_CHECKOUT_CMD`, o `ci.yml` faz o mesmo de hoje no `ubuntu-latest` (CI do próprio PR verde).
- `check-workflows.py`/`actionlint` aceitam o `ci.yml` novo; nenhum `${{ vars.* }}` dentro de `run`.
- Teste que falha no código atual: o passo do `gh` fixado, com base sem pin e sem manifesto, sem `gh` no PATH e com pin no PR, usa o pin do PR (simulado no teste dos passos do workflow, como os testes atuais fazem).
- Prova na parada: `validate.sh`, `check-docs.sh` e a CI do PR verdes.

1. Teste que falha no código atual (o pin do PR no primeiro CI). modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (CI, área gate)
2. O `gh` fixado no primeiro CI e a leitura da base por `git archive`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (CI, área gate)
3. O checkout por `CI_CHECKOUT_CMD`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (CI, área gate)
4. `process-design` §9.2 e §9.3, README e o comentário na issue. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (só docs)
