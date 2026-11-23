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
- [ ] O que o template removeu e o repo não mudou saiu; o que é só do repo ficou.
- [ ] `.github/method-origin` passou a ser o commit de destino.

## Arquivos ou áreas afetadas

Arquivos do método listados em `.github/method-files.txt`. O que é só deste repositório não se sobrescreve.

## Prioridade sugerida

alta

## Decisões do dono

O intervalo entre o commit de origem e o de destino pode exigir ok antes de executar:

- Permissões novas: headless com Bash liberado, e qualquer permissão nova em `.claude/settings.json`.
- Gasto: a CI em push na `main` consome minutos de runner.
- Ações destrutivas: processos que o método encerra no fim da fase, e arquivos do método que o template removeu.

## Sugestão de fim

auto-close
