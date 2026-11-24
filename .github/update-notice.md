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

## Pronto quando

- [ ] O PR lista o que é idêntico, adaptado, faltante, removido e só do repo (`scripts/method-diff.sh`).
- [ ] Arquivo do repo com padrão do template que faltava (`missing` no `method-diff.sh`) foi trazido; o que existe não foi sobrescrito.
- [ ] O que o template removeu e o repo não mudou saiu; o que é só do repo ficou.
- [ ] `.github/method-origin` passou a ser o commit de destino.
- [ ] O PR traz `.github/ci-mode` (`push` ou `pr`) com a escolha do dono; num repo privado sem esse arquivo (nem a variável `PROCESS_CI_MODE`) nenhuma fase abre.
- [ ] `docs/repo-notes.md` existe (modelo do template; junte a ele as regras do projeto do `AGENTS.md` antigo).
- [ ] Script só deste repo que o desenho cita entra em `.github/method-files.txt`.
- [ ] `scripts/validate.sh` e `scripts/check-docs.sh` verdes, e uma prova local: a atualização a partir da versão anterior.

Esta issue fecha no merge do PR. Não há fase de teste depois: a prova é a primeira fase normal, que abre e fecha pelo portão (primeira fase normal do repo).

> O PR de atualização que parte de `c1b76da` recebe `needs-owner-ok` do verificador antigo da base. Com as classes novas (`owner-ok` e `gate`), quem troca `ci.yml` e os verificadores recebe `needs-gate-review`: uma segunda revisão automática, sem o ok do dono.

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
