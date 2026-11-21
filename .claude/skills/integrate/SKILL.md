---
name: integrate
description: Passo único de fim de um grupo de fases, solo ou paralelo — espera todas entrarem pelo portão e roda, uma vez, gen-docs.sh, deploy.sh, o arquivamento das sessões filhas e end-check.sh. Use na gerenciadora depois de abrir as fases com phase-start.sh. Frases: "integrar as fases", "integrar o grupo".
---

# Fim do grupo (solo ou paralelo)

1. Grupo paralelo: leia `integration.md` nesta pasta e rode `scripts/integrate-parallel.sh` em segundo plano; ele só espera o merge de todos os PRs registrados em `.worktrees/parallel-active.tsv` e faz um build. PR em conflito é refeito pela sessão da fase (`close-phase.sh --check` chama o `redo-phase.sh`, que regrava a linha do registro); esta sessão não refaz nada. Grupo solo: espere o aviso de merge de cada sessão filha. O aviso nem sempre chega: o batimento (skill `plan`, passo 7; a cada 4 minutos) acorda esta sessão, que então lê o estado das sessões ligadas e dos PRs.
2. Enquanto espera, esta sessão é a gerenciadora: responde às sessões filhas e repassa as mensagens do dono do repo por `send_message`; não edita o checkout nem abre fases novas no mesmo grupo. Só ela pergunta ao dono, num quadro que começa por `Fase #n — título`, e devolve `respondido: <decisão>` à filha. Antes de perguntar ou de agir numa mensagem atrasada, leia o estado da fase (`get_session`/`list_events`) e descarte o já resolvido. O `scripts/status.sh` lista cada fase aberta como `#n — título — estado` e põe em "Você precisa" a decisão que uma fase espera do dono.
3. Depois do último merge do grupo, lido de volta (`gh pr view --json state` devolve `MERGED` para cada PR), faça o passo único de fim, uma vez, no checkout principal, nesta ordem:
   1. `scripts/gen-docs.sh`, em segundo plano (ele espera o CI do PR e passa do tempo limite de um comando): gera `CHANGELOG.md` e `ROADMAP.md`, remove cada spec de `docs/specs/` cujas issues citadas estão todas fechadas, abre um PR só com esses dois arquivos e essas remoções, publica `review/independent`, faz o merge por rebase e lê o merge de volta. É o único caminho da spec que sobrou na `main`: nada de PR avulso nem de remoção à mão. Saída 3: o PR não entrou no prazo; leia o CI dele e rode de novo.
   2. `scripts/deploy.sh`: dispara o `deploy-*.yml` na `main`, espera o run, imprime a URL e lê o resultado. Saída 0 com `deployed:` ou `no deploy:`: cite a linha e a URL no status. Saída 3 ou 4: o deploy não saiu; leia o run pela URL, Estado `trabalhando`, e rode `scripts/deploy.sh` de novo depois da correção. Nunca `gh workflow run` nem `gh run rerun`: o hook barra. Negado pelo app: passo 4.
   3. Arquive cada sessão filha, sem perguntar ao dono, nesta ordem única:
      1. Confira que parou (`get_session`; rodando, `stop_session`).
      2. Desligue o Remote Control dela: `set_remote_control` `false`. Sempre, mesmo que pareça desligado.
      3. Leia de volta: `get_session` mostra `remoteControlState` `off`. Ainda ligado: repita o item 2 uma vez. Nunca arquive com ele ligado.
      4. `archive_session`. A primeira chamada pode voltar pedindo a repetição com um campo que o app devolve: repita uma vez, exatamente com esse campo. Negado pelo app: passo 4.
      5. Leia de volta: `get_session` mostra `isArchived`.
      6. Recusado por trabalho vivo (tarefa em segundo plano ou recorrente da filha): mande mensagem à filha (`send_message`): "pare as suas tarefas em segundo plano e recorrentes e responda quando não sobrar nenhuma". Com a resposta, tente de novo uma vez, do item 4.
      7. Só depois disso, se ainda não arquivou (sessão fixada ou em uso): abra um quadro ao dono (`AskUserQuestion`) que começa por `Fase #n — título`, com as opções "Tentar arquivar de novo" e "Deixar a sessão aberta", e rode `scripts/status.sh --state esperando --need "arquivar a sessão da fase #n"`.
      8. `scripts/sessions.sh --list` mostra o que ainda segura RAM; `scripts/sessions.sh --close-idle` encerra só headless paradas (nunca filha do `Claude.app`). Sessão do app parada e não arquivada é arquivada por esta sessão como no passo 3; nunca delete.
   4. Apague o batimento da gerenciadora, a tarefa recorrente criada antes de abrir as filhas (skill `plan`, passo 7; no Claude Code, `CronList` e `CronDelete`), e leia de volta que saiu da lista. Nenhum script confere isso: batimento esquecido segue acordando esta sessão.
   5. `scripts/end-check.sh`: sai 1 com branch ou worktree extra, registro não vazio, branch remota sem PR aberto, spec de issue fechada, arquivo não rastreado, `ROADMAP.md` diferente do gerado ou deploy não conferido. Cada linha `fail:` diz o que sobrou; corrija e rode de novo (spec de issue fechada ou `ROADMAP.md` diferente: rode o `gen-docs.sh` de novo).
4. Ação do passo 3 negada pelo app. Caminho único, para `scripts/deploy.sh`, `archive_session` e qualquer outra ação do passo 3 que o app recusa (comum no turno do batimento):
   1. Abra um quadro de escolha (`AskUserQuestion`) que começa por `Fase #n — título`, com a opção de autorizar: "Autorizar o deploy", "Autorizar o arquivamento".
   2. Com o ok do dono, esta sessão roda a mesma ação de novo e segue o passo 3 de onde parou.
   3. Sem resposta: pare com `scripts/status.sh --state esperando --need "responder ao quadro da fase #n"`.
   4. Nunca peça ao dono que rode script nem que arquive pela barra lateral. Só a sessão que o app não deixa arquivar depois da tentativa (fixada ou em uso, passo 3.3) vai para "Você precisa".
5. Pare com `scripts/status.sh --state pronto`: ele roda o `scripts/end-check.sh` e sai 1 com sobra. Toda mensagem final de turno termina com a saída do `status.sh` colada como está (três linhas em negrito, sem bloco de código).
