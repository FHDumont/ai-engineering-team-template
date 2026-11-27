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

O checkout do template da filha é `.process/template` do worktree. O passo único é `.method/scripts/fetch-template.sh <destino> --apply`: ele traz o destino, roda o `.method/scripts/method-diff.sh` do destino, copia só o `outdated` e o `missing`, acrescenta ao fim de `.github/labels.tsv` cada `missing-label`, roda o `--remove` (`removed` e `template-only`) e imprime o `--notice`. Ele nunca sobrescreve um `adapted` nem um `repo-owned`, e o arquivo que o repo apagou de propósito (`deleted`) não volta.

Origem anterior à pasta `.method/` (sem `.method/scripts/fetch-template.sh` neste repo): o `fetch-template.sh` antigo não serve, e ele mora aqui. Rode o do próprio destino, com o SHA completo do destino (o curto não resolve no `fetch`):

<!-- update-cmd:before-method -->
```bash
mkdir -p .process/template && git -C .process/template init --quiet
git -C .process/template fetch --quiet --no-tags https://github.com/FHDumont/ai-engineering-team-template <destino-completo>
git -C .process/template checkout --quiet --force --detach FETCH_HEAD
bash .process/template/.method/scripts/fetch-template.sh <destino-completo> --apply
if [ -L scripts ]; then git rm -q scripts; fi
for f in scripts/*; do
  if [ -e ".method/scripts/${f#scripts/}" ]; then git rm -rqf --ignore-unmatch "$f"; rm -rf "$f"; fi
done
```

O laço final tira de `scripts/` só a cópia antiga de arquivo do método (nome que existe em `.method/scripts/`); o script da aplicação fica.

## Pronto quando

- [ ] `.method/scripts/fetch-template.sh <destino> --apply` rodou e a saída do `--notice` está colada na issue. O `--notice` lista só o `adapted` que o template mudou no intervalo.
- [ ] Cada `adapted` do `--notice` foi juntado à mão. O que é só do repo ficou.
- [ ] O PR traz o `.claude/settings.json` novo depois do ok do dono sobre o diff das permissões; sem ele a suíte fica vermelha (`test_settings_allow`).
- [ ] O PR traz `.github/ci-mode` (`push` ou `pr`) com a escolha do dono; sem esse arquivo nem a variável `PROCESS_CI_MODE` nenhuma fase abre.
- [ ] `docs/repo-notes.md` existe (modelo do template; junte a ele as regras do projeto do `AGENTS.md` antigo) e a frase antiga do `docs/STATE.md` ("o job `tests` roda em todo PR") saiu.
- [ ] Cada `deploy-*.yml` próprio (que não é o `deploy-example.yml`) tem o gate do `deploy-example.yml`: passo `.method/scripts/ci-already-green.sh` com `id`, `permissions: checks: read` no job de validação e `if: steps.<id>.outputs.skip != 'true'` no passo do `.method/scripts/validate.sh`. O `check-workflows.py` novo reprova o deploy sem isso.
- [ ] Os docs também passam no `check-docs.sh` da origem quando ela tem limite menor (o `--notice` imprime o comando); o `Policy` da CI roda o da base.
- [ ] Se a origem é anterior à pasta `.method/` (#269, #288): os scripts do método saíram de `scripts/` para `.method/scripts/`, sem link e sem migração automática; o `--apply` traz os arquivos novos, mas a troca dos caminhos é manual. Rode `git rm scripts` se o link existir, e depois confira cada lugar da lista "Troca de caminhos" abaixo.
- [ ] `.github/method-origin` passou a ser o commit de destino (`.method/scripts/setup-repo.sh --record-origin <destino>`).
- [ ] `.method/scripts/validate.sh --full` e `.method/scripts/check-docs.sh` verdes, e uma prova local: a atualização a partir da versão anterior.

Esta issue fecha no merge do PR. Não há fase de teste depois: a prova é a primeira fase normal, que abre e fecha pelo portão (primeira fase normal do repo).

> O PR de atualização que parte de `c1b76da` recebe `needs-owner-ok` do verificador antigo da base; quem troca `ci.yml` e os verificadores recebe `needs-gate-review`, uma segunda revisão automática sem o ok do dono. A label nova do portão entra no merge pelo `close-phase.sh`, sem passo manual.

## Troca de caminhos (scripts/ para .method/scripts/)

Todo `scripts/` do método passa a `.method/scripts/`; o link `scripts` deixou de existir. Nos arquivos que o `--apply` não sobrescreve (`adapted`, `repo-owned`) e no que é só do repo, troque à mão:

- `.github/workflows/ci.yml`: o `git ls-tree` que lê o método da base lista `.github .method` (no job `ci`, só `.method`); os passos que leem `base/scripts/...` leem `base/.method/scripts/...`. O mesmo vale para os `deploy-*.yml` próprios e para o `issues-label.yml` (`sparse-checkout` com `.method`).
- `.claude/settings.json`: cada `Bash(scripts/x *)` vira `Bash(.method/scripts/x *)`. Mostre o diff ao dono antes de usar.
- `.github/sensitive-paths`, `.github/method-files.txt` e `.github/label-areas.tsv`: caminhos `scripts/...` viram `.method/scripts/...`.
- `AGENTS.md`, `CONTEXT.md`, `docs/` e as skills, hooks e agentes próprios do repo: toda menção a `scripts/<nome>` vira `.method/scripts/<nome>`.
- Scripts e testes da aplicação que usam `$HERE/..` como raiz do repo: dentro de `.method/scripts/` a raiz está dois níveis acima (`$HERE/../..`). Script da aplicação que fica em `scripts/` continua lá.
- Confira com `git grep -n "scripts/"`: só deve sobrar `.method/scripts/` ou menção histórica.

## Linha de corte

A fase de atualização só abre issue no template quando, seguido este guia, o `.method/scripts/validate.sh --full` ou o `.method/scripts/check-docs.sh` fica vermelho, ou um script do método sai com erro. Ajuste à mão, observação e medida de tempo vão para "Decisões tomadas sem perguntar" do PR e nunca viram issue.

## Arquivos ou áreas afetadas

Arquivos do método listados em `.github/method-files.txt`. O que é só deste repositório não se sobrescreve.

## Prioridade sugerida

alta

## Decisões do dono

O intervalo entre o commit de origem e o de destino pode exigir ok antes de executar:

- Permissões novas: headless com Bash liberado, e qualquer permissão nova em `.claude/settings.json`.
- Gasto: a CI em push na `main` consome minutos de runner. A escolha vai em `.github/ci-mode` no PR de atualização (ou, sem commit na `main`, `.method/scripts/setup-repo.sh --ci-mode push|pr`).
- Ações destrutivas: processos que o método encerra no fim da fase, e arquivos do método que o template removeu.

## Sugestão de fim

auto-close
