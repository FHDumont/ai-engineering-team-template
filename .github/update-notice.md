---
name: Atualizar o método
about: Aviso para trazer uma versão nova do ai-engineering-team-template
title: "Atualizar o método ao ai-engineering-team-template"
labels: ["type:chore", "priority:high"]
---

## Objetivo

Trazer o método do commit de destino, partindo do commit de origem gravado em `.github/method-origin`, sem apagar o que é só deste repositório.

- Commit de origem: `<sha>`
- Commit de destino: `<sha>`

O checkout do template da filha é `.process/template` do worktree. O passo único é `scripts/fetch-template.sh <destino> --apply`: ele traz o destino, roda o `scripts/method-diff.sh` do destino, copia só o `outdated` e o `missing`, acrescenta ao fim de `.github/labels.tsv` cada `missing-label`, roda o `--remove` (`removed` e `template-only`) e imprime o `--notice`. Ele nunca sobrescreve um `adapted` nem um `repo-owned`, e o arquivo que o repo apagou de propósito (`deleted`) não volta.

## Pronto quando

- [ ] `scripts/fetch-template.sh <destino> --apply` rodou e a saída do `--notice` está colada na issue. O `--notice` lista só o `adapted` que o template mudou no intervalo.
- [ ] Cada `adapted` do `--notice` foi juntado à mão. O que é só do repo ficou.
- [ ] O PR traz o `.claude/settings.json` novo depois do ok do dono sobre o diff das permissões; sem ele a suíte fica vermelha (`test_settings_allow`).
- [ ] O PR traz `.github/ci-mode` (`push` ou `pr`) com a escolha do dono; sem esse arquivo nem a variável `PROCESS_CI_MODE` nenhuma fase abre.
- [ ] `docs/repo-notes.md` existe (modelo do template; junte a ele as regras do projeto do `AGENTS.md` antigo) e a frase antiga do `docs/STATE.md` ("o job `tests` roda em todo PR") saiu.
- [ ] Cada `deploy-*.yml` próprio (que não é o `deploy-example.yml`) tem o gate do `deploy-example.yml`: passo `scripts/ci-already-green.sh` com `id`, `permissions: checks: read` no job de validação e `if: steps.<id>.outputs.skip != 'true'` no passo do `scripts/validate.sh`. O `check-workflows.py` novo reprova o deploy sem isso.
- [ ] Os docs também passam no `check-docs.sh` da origem quando ela tem limite menor (o `--notice` imprime o comando); o `Policy` da CI roda o da base.
- [ ] `.github/method-origin` passou a ser o commit de destino (`scripts/setup-repo.sh --record-origin <destino>`).
- [ ] `scripts/validate.sh --full` e `scripts/check-docs.sh` verdes, e uma prova local: a atualização a partir da versão anterior.

Esta issue fecha no merge do PR. Não há fase de teste depois: a prova é a primeira fase normal, que abre e fecha pelo portão (primeira fase normal do repo).

> O PR de atualização que parte de `c1b76da` recebe `needs-owner-ok` do verificador antigo da base; quem troca `ci.yml` e os verificadores recebe `needs-gate-review`, uma segunda revisão automática sem o ok do dono. A label nova do portão entra no merge pelo `close-phase.sh`, sem passo manual.

## Linha de corte

A fase de atualização só abre issue no template quando, seguido este guia, o `scripts/validate.sh --full` ou o `scripts/check-docs.sh` fica vermelho, ou um script do método sai com erro. Ajuste à mão, observação e medida de tempo vão para "Decisões tomadas sem perguntar" do PR e nunca viram issue.

## Arquivos ou áreas afetadas

Arquivos do método listados em `.github/method-files.txt`. O que é só deste repositório não se sobrescreve.

## Prioridade sugerida

alta

## Decisões do dono

O intervalo entre o commit de origem e o de destino pode exigir ok antes de executar:

- Permissões novas: headless com Bash liberado, e qualquer permissão nova em `.claude/settings.json`.
- Gasto: a CI em push na `main` consome minutos de runner. A escolha vai em `.github/ci-mode` no PR de atualização (ou, sem commit na `main`, `scripts/setup-repo.sh --ci-mode push|pr`).
- Ações destrutivas: processos que o método encerra no fim da fase, e arquivos do método que o template removeu.

## Sugestão de fim

auto-close
