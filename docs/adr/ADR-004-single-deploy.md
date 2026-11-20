# ADR-004: Um deploy por fecho, só pelo deploy.sh

- Situação: vigente
- Data: herdada do template
- Fase/PR: herdada do template

## Contexto

Deploy disparado por cada sessão de fase, com a saída do disparo descartada, dá vários deploys para um grupo, nenhum para outro e runs que falham sem aviso. E publica uma `main` que ninguém testou depois do merge.

## Decisão

Só o `scripts/deploy.sh` dispara deploy, rodado pela sessão principal depois do último merge do grupo, no passo único de fim (skill `integrate`), depois do `scripts/gen-docs.sh`; o `integrate-parallel.sh` só espera e não o chama. Ele recusa em sessão de fase e com fase, PR de fase ou registro paralelo aberto; espera o run e sai ≠ 0 se falhar. O workflow roda o `scripts/validate.sh` na `main` antes do build.

Cada `deploy-*.yml` declara o que publica na linha `# deploy-paths:`; sem mudança nesses caminhos desde o último deploy com sucesso, não há dispatch. SHA com deploy com sucesso ou em andamento não recebe outro; SHA cujo run falhou é disparado de novo, porque `gh run rerun` fica barrado. "Fase ou PR do grupo aberto" é lido como qualquer worktree `.worktrees/issue-<n>` ou PR aberto de branch `issue-<n>`, de qualquer grupo.

## Consequências

Um deploy por fecho, com o resultado lido. Hook, `deny` e `check-workflows.py` fecham os outros caminhos. Um grupo aberto segura o deploy de outro. O que é publicado a partir de dados que mudam sem mudança nos caminhos declarados só é republicado quando esses caminhos mudam.
