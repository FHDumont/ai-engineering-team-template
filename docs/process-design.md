# Método de engenharia com IA: desenho

Este documento descreve o método: um repositório, trabalhado por agentes de IA, com um dono que aprova e testa. Ele descreve o que os scripts e hooks do repositório fazem hoje. Cada regra está escrita num lugar só; os outros lugares apontam para ela. Notas próprias de um repositório (medidas, nomes, credenciais) ficam fora deste documento.

## Resumo

- O trabalho entra como issue. A triagem agrupa as issues, o planejamento escreve uma spec curta por fase e o dono do repo aprova a spec.
- Cada fase roda numa sessão filha, em branch e worktree próprios, com um commit por etapa.
- Todo merge passa por um portão: o check `CI` mais o status `review/independent`.
- Depois do último merge do grupo, a sessão principal faz o passo único de fim.
- O que o agente lê sempre é pequeno: `AGENTS.md`, `docs/STATE.md` e o índice de ADRs. As skills carregam só na etapa delas.

## Regras-base

São cinco. Cada uma tem uma trava que roda sozinha. A trava saiu com o código da tabela: faça o que a última coluna diz. Nenhuma regra-base tem segundo caminho.

| Regra | Script e hook que barram | Código de saída | O que o agente faz |
|---|---|---|---|
| 1. Plan obrigatório: a fase só abre com spec no git que cita a issue | `scripts/phase-start.sh` | 1 | Carrega a skill `plan`, escreve a spec, pede o ok do dono e roda `scripts/phase-start.sh <n>` de novo |
| 2. Fase em sessão filha: a sessão que abriu a fase não escreve nela | `.claude/hooks/block-phase-commit.sh` e `.claude/hooks/block-phase-edit.sh`; `.githooks/reference-transaction`; `scripts/close-phase.sh` | 2 nos hooks do agente; 1 no hook do git; 9 no `close-phase.sh` | Manda o pedido à sessão filha por `send_message` e para com o bloco de status |
| 3. Deploy único pela sessão principal | `scripts/deploy.sh`; `.claude/hooks/block-dangerous-git.sh` | 1 no `deploy.sh`; 2 no hook | A sessão de fase termina sem deploy. A sessão principal roda `scripts/deploy.sh` no passo único de fim |
| 4. Conflito mecânico sem cartão: PR em conflito com a `main` é refeito por script | `scripts/close-phase.sh --check`, que chama `scripts/redo-phase.sh` | 0 com o PR novo; 4 com conflito real | Com 0, segue do PR novo. Com 4, resolve os arquivos listados, faz `git add` pelo nome, `git cherry-pick --continue` e roda `scripts/redo-phase.sh` de novo |
| 5. Fim coerente: `pronto` só com o fim limpo | `scripts/status.sh --state pronto`, que roda `scripts/end-check.sh` | 1 | Corrige cada linha `fail:` e roda de novo. Até lá o Estado é `trabalhando` |

Onde cada regra está descrita: 1 e 2 na §4.3; 3 na §9.4; 4 na §6.1; 5 na §2, regra 4.

---

## 1. Idioma

| Inglês | Português (pt-BR) |
|---|---|
| Código, identificadores e comentários no código | Docs: `README.md`, este desenho, `AGENTS.md`, `docs/STATE.md`, ADRs, `docs/BOTS.md`, `CONTEXT.md`, texto das skills, comandos e agentes |
| Nomes de arquivos, pastas e scripts | Issues (título e corpo) e o conteúdo dos templates de issue |
| Labels (`type:feature`, `end:lab-test`, `needs-owner-ok`) | PRs (título, corpo, template) e comentários em issues e PRs |
| Nomes de workflows, jobs, passos e checks (`CI`, `review/independent`) | O bloco de status no chat e toda conversa com o dono do repo |
| Mensagens de commit (Conventional Commits) | |
| `--help` e mensagens de saída dos scripts | |

## 2. Regras para todo agente

1. **O dono do repo nunca roda script nem mexe em configuração do repo.** O setup do método (labels, proteção de branch, configurações) é pré-aprovado: o agente roda `scripts/setup-repo.sh` sozinho sempre que algo sair do padrão.
2. **Idioma** conforme a §1.
3. **Toda decisão do dono é um quadro de escolha** (`AskUserQuestion`), uma pergunta por decisão, que começa por `Fase #n — título`. O hook `block-card-title.sh` barra o quadro sem esse começo quando há fase aberta. Nunca peça ao dono para digitar o número de um item.
   - Só a sessão principal pergunta. A sessão filha manda a dúvida por mensagem e recebe `respondido: <decisão>`.
   - A sessão filha abre quadro para uma coisa só: a autorização da ação sensível que ela mesma executa (merge com `needs-owner-ok`; `close-phase.sh --abort --discard`). O ok do dono não atravessa sessões.
4. **Bloco de status em toda parada e em toda mensagem final de turno.** Rode `scripts/status.sh` e cole a saída como está, fora de bloco de código. São três linhas em negrito:

   **Estado:** trabalhando | esperando você | pronto

   **Você precisa:** nada | <ação exata do dono>

   **Próximo passo:** <o que o agente faz em seguida>

   - `trabalhando`: em andamento; `Você precisa: nada`.
   - `esperando você`: só com uma ação do dono em `--need`. Sem `--need`, o `status.sh` troca o estado para `trabalhando`.
   - `pronto`: o trabalho da sessão acabou. O `status.sh` roda o `scripts/end-check.sh` e sai 1 enquanto sobrar algo; `pronto` com `--need` também sai 1.
   - Na sessão principal, o `status.sh` lista antes do bloco cada fase aberta como `#n — título — estado` e põe em "Você precisa" a ação que uma fase espera do dono.
5. **Paralelo é o modo preferido.** A sessão de planejamento abre as sessões das fases.
6. **O que carrega sempre é pequeno.** Skills carregam só na etapa; `integration.md` só em fase paralela; regra de pasta (`<pasta>/CLAUDE.md`) só quando a pasta é tocada.
7. **Nada repete o git.** O histórico fica nos PRs, nas issues fechadas e no `git log`. Arquivos guardam só o estado atual.
8. **Chamar em vez de consultar.** O bot é avisado por webhook; nenhum bot faz polling.
9. **Nenhuma assinatura de IA** em commits, PRs, issues e comentários: nada de `Co-Authored-By`, "Generated with" nem emoji de assinatura. Travas: `block-attribution.sh`, `.githooks/commit-msg` e o job `policy` do CI.
10. **Os agentes usam o GitHub direto** (`gh`) para ler e comentar issues, abrir PRs e ver o CI. Scripts só para fluxos repetidos de vários passos. O merge é sempre pelo `close-phase.sh` (§2.3).

### 2.1 Princípios de execução

Baseados nas observações de Andrej Karpathy ([andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills)).

1. **Critério de sucesso verificável.** Antes de codar, defina o "pronto quando" que dá para checar.
2. **Prova do vermelho.** Correção de bug começa com um teste que reproduz o bug e falha no código antigo. A prova é rodar o teste com o patch revertido, não raciocinar.
3. **Nunca supor em silêncio.** Requisito ambíguo antes da spec: pergunte no grilling. Dúvida nova no meio da execução, em passo reversível: siga e registre a suposição no PR. Dúvida em item da lista "sempre perguntar" (§2.2): mande à sessão principal.
4. **Sem refatoração de carona.** A fase toca só o escopo da spec. O resto vira issue de achado (§4.2).
5. **Sem over-engineering.** A solução mais simples que atende; nada de abstração "para um dia".
6. **Preservar o contexto.** Leia o arquivo antes de mudar; remova função e import só com certeza de que não são usados; comentário que você não entendeu fica.
7. **Verificar antes de declarar feito.** Código de saída 0 não prova "criado", "vinculado", "autorizado" nem "acabou". Leia o fato de volta e só então escreva no status, no PR e no `STATE.md`. A leitura não confirmou: o Estado é `trabalhando` com o passo real. Leituras mínimas:
   - commit e push: `git log` e `git ls-remote`;
   - PR, issue e label: `gh pr view`, `gh issue view`;
   - merge: `gh pr view --json state` devolve `MERGED`;
   - quadro do Projects: `gh project view <n> --owner <dono>` devolve o número;
   - sessão filha: `get_session` devolve a sessão e o par.
8. **Um commit por etapa**, Conventional Commits em inglês, no imperativo.

### 2.2 Quando pedir confirmação

- **Sempre perguntar** (quadro de escolha): ação destrutiva e irreversível, gasto, dependência nova, mudança de arquitetura e de schema, segredos e credenciais, e todo item da lista da §10.3.
- **Nunca perguntar** em passo rotineiro e reversível de uma spec aprovada: setup do método, labels, issue de achado, branch e PR.
- **Dúvida num passo reversível:** siga e relate no bloco de status.

### 2.3 Regras de git

| Regra | Trava |
|---|---|
| Nunca commitar na `main`; toda fase tem branch e worktree próprios | `.githooks/pre-commit`, `block-dangerous-git.sh` |
| Nunca `git add -A`, `git add .`, `git add --all`, `git commit -a`; adicione arquivos pelo nome | `block-dangerous-git.sh` |
| Merge só por `scripts/close-phase.sh --merge`, que usa `gh pr merge --auto --rebase --delete-branch`. Nunca `gh pr merge` direto, `--squash` nem `--admin` | deny do `.claude/settings.json`, `block-dangerous-git.sh` |
| Nunca `git push --force` nem `git reset --hard` | deny do `.claude/settings.json`, `block-dangerous-git.sh` |
| No fim da fase, `git branch` mostra só a `main` atualizada | `scripts/end-check.sh` |

---

## 3. Modelo e esforço

1. **Os pares ficam num arquivo.** `scripts/lib/weights.tsv` guarda o modelo e o esforço de cada peso; `scripts/weights.sh <peso>` imprime o par. Nenhum agente, skill ou script cita nome de modelo. Para mudar um par, edite esse arquivo e só ele.

   | Peso | Quando |
   |---|---|
   | `light` | texto, docs, ajuste pequeno, teste repetitivo, renomeação mecânica |
   | `medium` | feature comum, bug com causa conhecida |
   | `strong` | arquitetura, segurança, pagamento, migração, proteção e permissões do repo, bug sem causa clara |
   | `reviewer` | o agente `close-reviewer` (revisão independente) |
   | `triage` | o agente `triage` |

2. **A spec traz o par.** Cada fase e cada etapa da spec tem uma linha `modelo: <modelo> · esforço: <esforço> · motivo: <motivo>`, com o par que `scripts/weights.sh <peso>` imprime.
3. **O par da sessão de planejamento.** Trabalho `light` e `medium` fica no par da sessão. Com item `strong` ou ambiguidade que muda o escopo, a sessão mostra num quadro o par atual e o do peso `strong`, antes de qualquer `start_session`, e o dono troca no mesmo chat, uma vez.
4. **Todo agente e subagente é aberto com `model` e `effort` explícitos**, inclusive o ajudante avulso. O `close-reviewer` abre com o par do peso `reviewer` e o `triage` com o do peso `triage`. Trava: `block-agent-pair.sh` (saída 2).
5. **O par da sessão filha é conferido, não presumido.** A sessão principal passa o par da spec ao `start_session`, mas o app não garante que a sessão nasce nesse par. A trava é o `scripts/check-env.sh`, que a filha roda antes da primeira etapa. Ele lê o par real da sessão e compara:

   | Par real da filha | O que o `check-env.sh` faz | O que a filha faz |
   |---|---|---|
   | igual ao da spec | sai 0 e grava `phase_session` com o par real e o pedido | segue |
   | igual ao da sessão que abriu a fase | sai 0 e grava o mesmo `phase_session` | segue nesse par; a tabela do PR mostra a diferença |
   | outro par, ou par que não dá para ler | sai 1 e grava `phase_pair_mismatch`; sem `phase_session` o portão do merge fica fechado | não começa nenhuma etapa; avisa a sessão principal, que ajusta o par com `set_session_model` e `set_session_effort`; depois roda o `check-env.sh` de novo |

6. **Etapa com par diferente do da sessão.** O `check-env.sh` imprime, para cada etapa da spec, onde ela roda: par igual ao da sessão, na própria sessão; par diferente, num subagente aberto com o par da etapa.
7. **A tabela do PR é do script.** O `close-phase.sh --prepare` escreve a seção "Modelo e esforço" do PR com a saída de `scripts/trace-view.py --pairs <issue>` (pedido × usado, com `(diverge)` onde difere). Ninguém a preenche à mão.

---

## 4. Fluxo

Diagrama das raias: [`docs/diagrams/process-flow.html`](diagrams/process-flow.html).

0. **Pedido sem issue.** O planejamento faz o grilling do pedido, abre as issues com `scripts/open-issue.sh` e segue no mesmo chat.
1. **Entrada.** O trabalho entra como issue por template (§8.2). As labels são aplicadas na criação pelo workflow `issues-label.yml`.
2. **Triagem.** O agente `triage` lê só títulos e labels (`scripts/triage.sh`). Issue sem label é rotulada; a que não dá para classificar recebe `needs-context`.
3. **Sugestão.** A triagem devolve uma linha com os grupos, o modo de cada um e o peso do planejamento. Grupos sem arquivo de código em comum rodam em paralelo; arquivos gerados não contam. O quadro ao dono só aparece com arquivo de código em comum, dependência entre issues, pedido expresso de modo, ou par que precisa subir.
4. **Grilling e spec.** O planejamento lê por inteiro só as issues escolhidas. Faz um grilling único, antes de abrir qualquer filha: pergunta ao dono só o que muda alguma spec; o resto vira suposição escrita. Depois escreve uma spec curta por fase em `docs/specs/`: objetivo, pronto quando, arquivos previstos, etapas com o par (§3) e modo de fim.
5. **Aprovação.** Um ok para a spec inteira, num quadro de escolha. A label `approved`, posta pelo dono no GitHub, vale como o mesmo ok.
6. **Abertura.** `scripts/phase-start.sh <n> [<n>…]` (§4.3). Uma issue abre fase solo; duas ou mais abrem o grupo paralelo.
7. **Execução.** A sessão filha roda `scripts/check-env.sh` e executa as etapas, um commit por etapa (skill `execute`). Achados seguem a §4.2.
8. **Modo de fim.**
   - `end:auto-close`: a filha segue direto para o fecho.
   - `end:lab-test`: a filha para antes do fecho com `status.sh --state esperando --need "testar no lab …"`. O dono testa, itera pela sessão principal e diz "fechar fase". "Fechar fase" vale dito em qualquer sessão; quem fecha é a sessão da fase.
9. **Fecho.** A filha fecha pelo `scripts/close-phase.sh` (§6.1), com a revisão independente (§10.2) e o merge pelo portão (§10).
10. **Fim do grupo.** Depois do último merge do grupo, solo e paralelo, a sessão principal faz o passo único de fim, uma vez. Os passos e a ordem estão na skill `integrate`: `scripts/gen-docs.sh`, `scripts/deploy.sh`, arquivamento das sessões filhas, remoção do batimento (§4.3), `scripts/end-check.sh`. A spec do grupo sai da `main` aqui: o PR do `gen-docs.sh` remove cada spec de `docs/specs/` cujas issues citadas estão todas fechadas, a que o fecho das fases (§6.1) deixou.

Espera acima de ~2 minutos: diga o que espera e onde (o run, o PR).

### 4.1 O que o dono do repo faz

| Situação | Toques |
|---|---|
| Sempre | 1 ok na spec |
| Item `strong` na spec | 1 troca de modelo e esforço no chat do planejamento |
| `end:lab-test` | testar no lab, iterar, "fechar fase" |
| `end:auto-close` | nada |
| PR com `needs-owner-ok` | 1 ok no quadro do merge |
| Achado `size:large` | 1 quadro: agora ou na próxima triagem |

### 4.2 Achados durante o trabalho

O agente abre a issue com `scripts/open-issue.sh --type finding --size small|medium|large`.

| Tamanho | O que acontece |
|---|---|
| `size:small` | a fase resolve, sem perguntar |
| `size:medium` | a fase resolve se o escopo da spec não muda, e avisa no PR; se muda, a issue fica para a próxima triagem |
| `size:large` | a fase avisa a sessão principal, que faz o quadro ao dono |

Achado fora do escopo da fase não é corrigido de carona: fica na issue. Os pontos leves da revisão independente seguem a §10.2.

### 4.3 Sessões: a principal e a filha

A sessão que o dono abre é a de planejamento. Depois de abrir as fases ela vira a **gerenciadora** (sessão principal). Cada fase roda numa **sessão filha**.

**Abertura (regras-base 1 e 2).**

1. "executar #n" sempre passa pela skill `plan`. O hook `prompt-phase-entry.sh` põe esse caminho no contexto do pedido. Issue sem spec, de qualquer tipo e tamanho, ganha uma spec curta na hora.
2. A fase só abre por `scripts/phase-start.sh <n>`. Ele sai 1, sem criar nada, em três casos: issue fechada; nenhuma spec em `docs/specs` cita `#n`; a spec não tem a linha do par. Com spec, ele grava `phase_opened` no trace, cria branch e worktree (`.worktrees/issue-<n>`), commita a spec na branch e imprime os argumentos do `start_session`.
3. Antes de qualquer `start_session`, a gerenciadora cria o **batimento**, uma tarefa recorrente do agente que a cada 4 minutos lê o estado das sessões ligadas e dos PRs das fases abertas e faz o próximo passo (cartão ainda não clicado: só repete o "Você precisa"), e o apaga no passo único de fim, porque ela só age quando algo a acorda e o aviso de fim da filha nem sempre chega (instrução impressa pelo `phase-start.sh`, sem trava que a confira). Vem antes das sessões porque a filha que vira cartão abre pelo clique do dono, fora de qualquer turno da gerenciadora.
4. A gerenciadora abre todas as filhas do grupo no mesmo turno do "executar", um `start_session` por fase, com os campos: `initiation: "user_asked"`, `context: "fresh"`, `use_worktree: false`, `title`, `prompt`, `background`, `model` e `effort` da spec.
5. O app recusou o `start_session` (turno sem mensagem do dono): a gerenciadora repete a chamada com `initiation: "own_initiative"`, que vira um cartão que o dono abre com um clique, e só então para em `esperando você`. Todo "Você precisa" que manda o dono agir em outra sessão (clicar num cartão, responder a um quadro) diz o título exato dela e onde ela fica: "na barra lateral, dentro do agrupamento da sessão principal; se não aparecer, abra o agrupamento". A fase nunca roda na gerenciadora nem num subagente dela.

**O que cada sessão faz.**

| | Gerenciadora (abriu a fase) | Sessão filha |
|---|---|---|
| Edita o worktree da fase | nunca (`block-phase-edit.sh`, `block-phase-commit.sh`, `.githooks/reference-transaction`) | sim, por caminho absoluto |
| Roda `close-phase.sh` | nunca (sai 9): repassa o pedido à filha por `send_message` e para | sim |
| Pergunta ao dono | sim, toda pergunta (§2, regra 3) | só o ok da ação sensível que ela executa |
| Recebe "fechar fase" | repassa à filha | fecha |
| Faz deploy e gera `CHANGELOG.md` e `ROADMAP.md` | sim, no passo único de fim | nunca |
| Arquiva a sessão filha | sim, no passo único de fim | termina com `Próximo passo: a gerenciadora arquiva esta sessão` |

**O portão confere a regra.** O `close-phase.sh --merge` lê o trace do checkout principal e exige: o `phase_opened` da issue da branch; que a sessão que roda o `--merge` seja outra; que ela tenha `phase_session` próprio (gravado pelo `check-env.sh`) e um evento gravado pelos hooks do harness. Linha do trace que não é JSON bloqueia. `--issue` diferente da issue da branch sai 2.

**Subagente** vale só dentro da sessão filha, para a etapa cujo par difere do par da sessão (§3, item 6). Ninguém diz que abriu um agente sem o evento no trace (§6.3).

---

## 5. Caminho B: bots

Opcional. Os bots atuam nas pontas: abrem issues, respondem quando perguntados e revisam o PR quando a issue pede. Uma fase que não pergunta nada a bot não usa esta seção.

### 5.1 O agente pergunta a um bot

`scripts/ask-bot.sh <bot> <issue> "texto"` faz os três passos:

1. Comenta a pergunta na issue com a marca `<!-- ask:<bot>:<id> -->`.
2. Chama o webhook do bot com o link do comentário (`scripts/notify-bot.sh`): três tentativas, `--max-time 10` cada. Sem sucesso, põe a label `ask:<bot>` na issue e o `ask-bot.sh` sai 4 sem esperar a resposta; o agente avisa o dono no bloco de status e segue com o que não depende dela.
3. Espera a resposta (`scripts/wait-reply.sh`, 15 minutos; sem resposta no prazo sai 3): só vale o comentário com a marca `<!-- bot:<slug> reply-to:<id> -->` postado depois da pergunta. A resposta é reconhecida pela marca, não pelo autor.

- `ask-bot.sh --retry` refaz o aviso e a espera sem repostar a pergunta.
- URL e segredo do webhook vêm do `scripts/lib/secret.sh` na hora da chamada, nunca de arquivo do repo, argumento nem log. Ele procura nesta ordem: variável de ambiente, conta de serviço do gerenciador de senhas (CLI `op`), `.env` fora do repo (`~/.<repo-slug>/.env`, criado vazio pelo `scripts/init-env.sh`). Sem provedor, o `ask-bot.sh` para. O agente lê segredo só pelos scripts: o `.claude/settings.json` nega a chamada direta do `op`.
- O segredo vai em dois headers, `Authorization: Bearer <secret>` e `X-Automation-Key: <secret>`. Corpo:
  ```json
  {"source": "ask-bot", "bot": "<slug>", "repo": "<owner>/<name>", "issue": 11,
   "comment_url": "<link do comentário>", "ask_id": "<id>",
   "reply_marker": "<!-- bot:<slug> reply-to:<id> -->"}
  ```
- Depois de ~10 comentários, o `scripts/summarize-thread.sh` mantém um comentário fixo (`<!-- agreed-summary -->`) editado no lugar.

### 5.2 `docs/BOTS.md`

No máximo 450 palavras (conferido pelo `check-docs.sh`). Uma linha por bot: slug, papel, o que responde, o que nunca faz. Traz também como guardar os segredos dos webhooks. A skill `ask-bot` aponta para ele; `scripts/lib/bots.tsv` lista os slugs e a referência de cada webhook.

---

## 6. Scripts

Todo script tem `--help`, um teste em `scripts/tests/` e saída curta em inglês. As regras da pasta estão em `scripts/CLAUDE.md`. A tabela lista todo arquivo de `scripts/`; o `check-docs.sh` confere.

| Script | O que faz | Quem chama |
|---|---|---|
| `scripts/setup-repo.sh` | Idempotente: sincroniza as labels do `.github/labels.tsv`, aplica a proteção e as configurações do repo (§10.1) e as lê de volta; `--offers`, `--project` e `--decline` na §8.3 | o agente, em qualquer desvio do padrão |
| `scripts/setup-runner.sh` | Registra o runner próprio (§9.3) | sessão principal |
| `scripts/init-env.sh` | Cria o `.env` fora do repo só com as chaves vazias; nunca lê nem escreve valores | skill `setup` |
| `scripts/triage.sh` | Issues abertas em JSON curto: número, título, labels; marca as sem label | agente `triage` |
| `scripts/label-issue.sh` | Aplica tipo, área, prioridade, grupo, tamanho e fim | triagem, agentes |
| `scripts/auto-label.py` | Lê as seções `##` do corpo da issue e gera as labels; seção obrigatória vazia vira `needs-context` | `issues-label.yml` |
| `scripts/open-issue.sh` | Monta o corpo a partir do arquivo de template, exige as seções obrigatórias do tipo, aplica as labels | agentes, bots |
| `scripts/weights.sh` | Lê `scripts/lib/weights.tsv`: lista os pesos, imprime o par de um peso, confere o arquivo (`--check`) | skills, `block-agent-pair.sh` |
| `scripts/phase-start.sh` | Entrada única da fase (§4.3) | sessão principal |
| `scripts/new-phase.sh` | Branch e worktree de uma fase solo; sai 1 sem spec | `phase-start.sh` |
| `scripts/open-parallel.sh` | Worktrees do grupo paralelo e o registro `.worktrees/parallel-active.tsv`; sai 1 com sobra no registro | `phase-start.sh` |
| `scripts/check-env.sh` | Confere o ambiente da fase: fora da `main`, spec da issue no git, par real da sessão (§3), git hooks instalados, testes rodando | sessão filha, antes da primeira etapa |
| `scripts/status.sh` | Imprime o bloco de status (§2, regra 4) | todo agente, em toda parada |
| `scripts/end-check.sh` | Confere o fim sem consertar nada e sai 1 listando cada sobra em linhas `fail:`. Do grupo: branch e worktree extra, registro não vazio, branch remota sem PR aberto, spec de issue fechada, arquivo não rastreado, `ROADMAP.md` diferente do gerado, deploy não conferido. Com `--issue <n>`: só a fase | `status.sh --state pronto`; sessão principal |
| `scripts/close-phase.sh` | Fecha a fase (§6.1) | sessão filha |
| `scripts/redo-phase.sh` | Refaz a fase cujo PR conflita com a `main` (§6.1, passo 3) | `close-phase.sh --check` |
| `scripts/integrate-parallel.sh` | Só espera todas as fases do registro entrarem e faz um build; não faz deploy | sessão principal |
| `scripts/gen-docs.sh` | Geração única de `CHANGELOG.md` e `ROADMAP.md` e remoção das specs cujas issues citadas estão todas fechadas: PR só com os dois arquivos e essas remoções, `review/independent` publicado pelo script, merge por rebase lido de volta. Outro arquivo, spec adicionada ou modificada, spec removida com issue aberta: sai 1 sem status e sem merge | sessão principal, no passo único de fim |
| `scripts/gen-changelog.py` | `CHANGELOG.md` a partir dos PRs com merge, agrupado por `type:*` | `gen-docs.sh` |
| `scripts/gen-roadmap.py` | `ROADMAP.md` das issues abertas por área e prioridade | `gen-docs.sh`, `end-check.sh` |
| `scripts/deploy.sh` | O único deploy (§9.4) | sessão principal, no passo único de fim |
| `scripts/validate.sh` | Lint e todos os testes; único lugar onde roda o shellcheck | agentes, CI |
| `scripts/check-docs.sh` | Limites de palavras (`AGENTS.md` 300–500, `docs/STATE.md` ≤500, `docs/BOTS.md` ≤450, skill `plan` ≤400); `CLAUDE.md` só com `@AGENTS.md`; uma linha por ADR no índice; nenhuma seção de histórico; este desenho contra o repositório: tabela das regras-base, tabela de scripts, tabela de hooks e tabela de arquivos | CI, `close-phase.sh` |
| `scripts/check-workflows.py` | Padrão dos workflows (§9) além do `actionlint` | CI |
| `scripts/check-attribution.sh` | Reprova assinatura de IA abrindo uma linha nos commits e no corpo do PR | CI `policy`, `close-phase.sh --merge`, `.githooks/commit-msg` |
| `scripts/ci-gate.sh` | Decide o resultado do job `CI` a partir dos outros jobs (§9.2) | `ci.yml` |
| `scripts/archive-adr.sh` | Marca a ADR como substituída no índice e a move para `docs/adr/archive/` | agente que cria a ADR nova |
| `scripts/search-history.sh` | Busca um termo na ordem da §7.1 e devolve lista curta com links | qualquer agente |
| `scripts/ask-bot.sh` | Pergunta a um bot e espera a resposta (§5.1) | agentes |
| `scripts/notify-bot.sh` | Chama o webhook do bot (§5.1) | `ask-bot.sh` |
| `scripts/wait-reply.sh` | Espera a resposta marcada (§5.1) | `ask-bot.sh` |
| `scripts/summarize-thread.sh` | Mantém o comentário de resumo de um fio longo (§5.1) | agentes |
| `scripts/trace-view.py` | Lê o trace (§6.3): árvore de agentes e tabela de pares do PR | `close-phase.sh --prepare`, agentes |
| `scripts/measure-session.py` | Mede palavras lidas, toques do dono e acerto da triagem de uma sessão | sessão principal, sob pedido |
| `scripts/CLAUDE.md` | Regras da pasta `scripts/` | lido ao tocar a pasta |

### 6.1 `close-phase.sh`

Roda só na sessão filha; na sessão que abriu a fase, `--prepare`, `--publish-review`, `--check` e `--merge` saem 9.

1. **`--prepare --title … --body-file …`**
   - roda `validate.sh` e `check-docs.sh`;
   - apaga, num commit da fase, cada spec que cita a issue da fase e não cita outra issue aberta; a spec que sobra na `main` depois do último merge sai no passo único de fim, pelo `gen-docs.sh`;
   - faz um `git push` (um run de CI; grava `phase_push` no trace);
   - abre o PR pelo `.github/pull_request_template.md`; PR já aberto é editado só se o título ou o corpo mudou;
   - copia as labels da issue para o PR e escreve a tabela de pares (§3, item 7);
   - não gera `CHANGELOG.md` nem `ROADMAP.md` e não exige mudança no `docs/STATE.md`.
2. **`--check`**, antes e durante a espera do CI. Lê `mergeable`, `mergeStateStatus` e os checks do SHA do HEAD. Check de SHA anterior não vale.

   | Saída | Significa | O que a filha faz |
   |---|---|---|
   | 0 `ok` | PR sem conflito, checks lidos | espera o CI com `gh pr checks` |
   | 0 com PR novo | o PR conflitava e foi refeito (passo 3) | segue do PR novo |
   | 4 | conflito real no cherry-pick | resolve (passo 3) |
   | 7 | nenhum check no HEAD em ~3 min | investiga o CI e diz no status |
   | 8 | `mergeable` segue `UNKNOWN` após 5 leituras | olha o PR no GitHub e diz no status |

3. **PR em conflito com a `main` (regra-base 4).** O `--check` chama o `scripts/redo-phase.sh` sem esperar CI e sem pergunta ao dono: branch nova a partir da `main`, cherry-pick dos commits da fase, PR novo com `Closes #n`, PR antigo fechado, branch remota antiga apagada, linha do registro paralelo regravada; cada passo lido de volta, sem push forçado. Conflito só em arquivo gerado é resolvido pelo script. Conflito real para o cherry-pick e sai 4: a filha resolve os arquivos listados, faz `git add` pelo nome, `git cherry-pick --continue` e roda `scripts/redo-phase.sh` de novo. PR só atrasado, sem conflito, não é refeito.
4. **Revisão independente** (§10.2) e **`--publish-review <arquivo> --verdict success|failure`**: publica o status `review/independent` no SHA do HEAD e o parecer como comentário. Recusa parecer sem rodada do `close-reviewer` desta sessão posterior ao último push (lê `phase_push` e `SubagentStart` no trace).
5. **`--merge --wait`**. Recusa se um destes itens falhar:
   - a regra da sessão filha (§4.3);
   - o `--check` (com PR refeito sai 6: o PR novo ainda não tem CI nem revisão);
   - `needs-owner-ok` e label de área sensível (§10.3; sai 5);
   - `review/independent` verde, com a rodada do revisor no trace depois do push do HEAD;
   - a proteção da branch base com `CI` e `review/independent`;
   - `check-attribution.sh --pr N` no corpo final e nos commits.

   Passou: `gh pr merge --auto --rebase --delete-branch`. Nunca dispara deploy.
6. **`--cleanup`** (o `--wait` roda depois do merge): tira a linha da fase de `.worktrees/parallel-active.tsv`, apaga worktree, branch local e branch remota (lida de volta), atualiza a `main` local e move a issue para `Done` no quadro.
7. **`--abort`** desiste da fase sem merge. Lista o que seria perdido (alteração não commitada, arquivo não rastreado, commit sem push, commit enviado que nenhum PR guarda) e sai 10 sem tocar em nada. A filha faz commit e push do que fica. Perda aceita: a filha pede o ok do dono num quadro `Fase #<n> — <título>:` e roda `--abort --discard`, que fecha o PR, apaga a branch remota, o worktree, a branch local e a linha do registro, e devolve a issue a `Todo`.

### 6.2 Hooks

**Modelo de ameaça.** Os hooks do agente são salvaguarda contra engano, não barreira. A barreira é a proteção da `main` (`CI` + `review/independent`, vale para admin), os hooks do git e o deny do `.claude/settings.json`. Desvio de um hook por ofuscação deliberada é achado `size:small`.

Os hooks do agente saem 2 quando barram; os do git saem 1. Todo hook tem teste. A tabela lista todo arquivo de `.claude/hooks/` e de `.githooks/`; o `check-docs.sh` confere.

| Hook | Evento | O que barra |
|---|---|---|
| `.claude/hooks/block-dangerous-git.sh` | PreToolUse, Bash | A lista fechada abaixo |
| `.claude/hooks/block-attribution.sh` | PreToolUse, Bash | `git commit`, `gh pr create\|edit\|comment\|review\|close` e `gh issue create\|comment\|edit\|close` cujo texto tem assinatura de IA abrindo uma linha |
| `.claude/hooks/block-phase-commit.sh` | PreToolUse, Bash | Todo comando git fora da lista de leitura (`status`, `log`, `diff`, `show`, `fetch`…) que rodaria em `.worktrees/issue-<n>`, quando a sessão é a que gravou o `phase_opened` da issue; e, para essa mesma sessão, `git push` da branch da fase a partir de qualquer diretório, o checkout principal incluído (destino da refspec, branch atual quando não há refspec, `--all`, `--mirror`, `--branches` ou padrão). Para qualquer sessão: comando que define ou apaga `CLAUDE_CODE_SESSION_ID` ou `PROCESS_EVENTS_FILE`, e escrita à mão em `.process/events.jsonl`. Falha fechado: sem `session_id`, sem trace ou com linha do trace que não é JSON, a escrita no worktree e o push da branch de fase são barrados |
| `.claude/hooks/block-phase-edit.sh` | PreToolUse, Edit, Write, NotebookEdit | A edição de arquivo em `.worktrees/issue-<n>` pela sessão que gravou o `phase_opened` da issue; falha fechado igual. Para qualquer sessão: `.process/events.jsonl` |
| `.claude/hooks/block-agent-pair.sh` | PreToolUse, Agent | A chamada de `Agent` sem `model` ou sem `effort`; a do `close-reviewer` e a do `triage` com par diferente do peso em `scripts/lib/weights.tsv` |
| `.claude/hooks/block-card-title.sh` | PreToolUse, AskUserQuestion | Com fase aberta, o quadro cuja pergunta não começa por `Fase #<n> — <título>`; na sessão da fase, o número é o da fase dela |
| `.claude/hooks/prompt-phase-entry.sh` | UserPromptSubmit | Nada: põe no contexto de "executar #<n>" o caminho único (skill `plan`, depois `phase-start.sh`) |
| `.claude/hooks/trace-event.sh` | SessionStart, SubagentStart, SubagentStop, Stop, SessionEnd, Pre e PostToolUse do Agent | Nada: grava o trace (§6.3) |
| `.githooks/pre-commit` | git | Commit na `main`; commit da sessão que abriu a fase |
| `.githooks/pre-merge-commit` | git | Merge feito pela sessão que abriu a fase |
| `.githooks/pre-rebase` | git | Rebase feito pela sessão que abriu a fase |
| `.githooks/reference-transaction` | git, em toda atualização de ref | Mover a branch da fase e o `HEAD` do worktree dela pela sessão que abriu a fase, por qualquer comando (commit, cherry-pick, merge, rebase, `reset`, `update-ref`). Criar e apagar a branch passam |
| `.githooks/commit-msg` | git | Mensagem de commit com assinatura de IA |
| `.githooks/phase-guard.sh` | incluído pelos quatro hooks acima que barram a sessão que abriu a fase | Não é hook: guarda a regra comum, lida de `CLAUDE_CODE_SESSION_ID` e do trace |

Os hooks do git são instalados pelo `check-env.sh` (`core.hooksPath=.githooks`) e valem em qualquer ferramenta. Os hooks do agente são referenciados no `.claude/settings.json` como `"$CLAUDE_PROJECT_DIR"/.claude/hooks/...`, para funcionar em worktrees e subpastas. As travas leem sempre o trace do checkout principal; `PROCESS_EVENTS_FILE` só redireciona a gravação.

**Lista fechada do `block-dangerous-git.sh`** (o resto não é promessa):

1. `git commit` na `main`, inclusive depois de `cd`, `pushd`, `git -C` e `git switch main` no mesmo comando;
2. commit com `--no-verify`;
3. desligar hooks: `core.hooksPath` por `-c`, `--config-env`, `git config` e `GIT_CONFIG_*`;
4. `git commit -a` e `--all`;
5. `git add` e `git stage` com `-A`, `.`, `:/` e `-u`;
6. `git push` com `--force`, `-f`, `--mirror` e refspec `+`;
7. `git reset --hard`;
8. merge de PR direto: `gh pr merge`, `gh api … pulls/N/merge`, `gh api graphql` com mutation de merge e de proteção; toda escrita em `branches/*/protection`;
9. deploy fora do `deploy.sh`: `gh workflow run`, `gh run rerun`, `gh api` em `…/dispatches` e `…/rerun`;
10. os mesmos casos dentro de `bash -c`, `eval`, heredoc entregue a shell, `echo … | bash`, `$(…)`, depois de `env`, `command`, `nice`, `timeout` e `sudo`, em blocos e com caminho absoluto;
11. falha fechado: comando ilegível ou grande demais (>256 KB ou >400 partes) que cita git ou gh é barrado.

### 6.3 Trace

O hook `trace-event.sh` acrescenta uma linha JSON por evento em `.process/events.jsonl`, no checkout principal, fora do git. Campos: `ts`, `event`, `session_id`, `agent_id`, `agent_type`, `model`, `effort`, `cwd`, `branch`, `issue`; nos eventos do Agent, também `tool_use_id` e `subagent_id`.

| Evento | Quem grava | Para quê |
|---|---|---|
| `phase_opened` | `phase-start.sh` | diz qual sessão abriu a fase (regra-base 2) e o par dela |
| `phase_session` | `check-env.sh` | diz qual sessão executa a fase, com o par real e o pedido |
| `phase_pair_mismatch` | `check-env.sh` | par real diferente do pedido (§3, item 5) |
| `phase_push` | `close-phase.sh --prepare`, `redo-phase.sh` | marca o push; a revisão precisa vir depois dele |
| eventos do harness | `trace-event.sh` | sessões e subagentes abertos, com o par |

`scripts/trace-view.py` gera `.process/tree.html`; com `--text`, a árvore em texto; com `--pairs <issue>`, a tabela pedido × usado do PR. O `effort` do `SubagentStart` vem sempre "medium"; o valor pedido está no `PreToolUse` do Agent.

---

## 7. Arquivos

A tabela é a árvore de arquivos do método. Caminho sem `<…>` precisa existir; o `check-docs.sh` confere.

| Caminho | O que é |
|---|---|
| `AGENTS.md` | fonte única das regras para todo agente, 300–500 palavras |
| `CLAUDE.md` | só `@AGENTS.md` |
| `CONTEXT.md` | glossário curto do domínio |
| `README.md` | entrada para pessoas; aponta para a abertura de issue |
| `CHANGELOG.md` | gerado pelo `gen-docs.sh` |
| `ROADMAP.md` | gerado pelo `gen-docs.sh` |
| `docs/STATE.md` | estado atual, ≤500 palavras; a fase que muda o estado atualiza a sua parte |
| `docs/BOTS.md` | caminho B, ≤450 palavras |
| `docs/process-design.md` | este documento |
| `docs/diagrams/process-flow.html` | diagrama das raias |
| `docs/specs/<AAAA-MM-DD>-<grupo>.md` | spec em curso; sai no fecho da última fase aberta que ela cita e, se sobrar, no PR do `gen-docs.sh` |
| `docs/adr/INDEX.md` | uma linha por ADR: número, título, vigente ou substituída |
| `docs/adr/TEMPLATE.md` | modelo de ADR |
| `docs/adr/ADR-<NNN>-<título>.md` | ADRs vigentes |
| `docs/adr/archive/` | ADRs substituídas |
| `<pasta>/CLAUDE.md` | regra que só vale naquela pasta |
| `.claude/settings.json` | atribuição vazia, permissões e hooks (§10.4) |
| `.claude/skills/triage/SKILL.md` | triagem |
| `.claude/skills/plan/SKILL.md` | grilling e spec, ≤400 palavras |
| `.claude/skills/execute/SKILL.md` | sessão filha da fase |
| `.claude/skills/close-phase/SKILL.md` | fecho da fase |
| `.claude/skills/integrate/SKILL.md` | passo único de fim do grupo |
| `.claude/skills/integrate/integration.md` | regras das fases paralelas |
| `.claude/skills/ask-bot/SKILL.md` | pergunta a um bot |
| `.claude/skills/setup/SKILL.md` | configuração do repo |
| `.claude/commands/triage.md` | comando que chama a skill |
| `.claude/commands/plan.md` | comando que chama a skill |
| `.claude/commands/close-phase.md` | comando que chama a skill |
| `.claude/agents/triage.md` | agente de triagem (peso `triage`) |
| `.claude/agents/close-reviewer.md` | agente da revisão independente (peso `reviewer`) |
| `.claude/hooks/` | hooks do agente (§6.2) e os testes deles em `.claude/hooks/tests/` |
| `.cursor/rules/base.mdc` | aponta para o `AGENTS.md` |
| `.cursor/rules/scripts.mdc` | aponta para o `scripts/CLAUDE.md` |
| `.githooks/` | hooks do git (§6.2) |
| `.github/ISSUE_TEMPLATE/feature.md` | template de issue |
| `.github/ISSUE_TEMPLATE/bug.md` | template de issue |
| `.github/ISSUE_TEMPLATE/debt.md` | template de issue |
| `.github/ISSUE_TEMPLATE/finding.md` | template de issue |
| `.github/ISSUE_TEMPLATE/config.yml` | desliga a issue em branco |
| `.github/pull_request_template.md` | corpo do PR |
| `.github/labels.tsv` | labels do repo (§8.1) |
| `.github/sensitive-paths` | globs dos caminhos sensíveis (§10.3) |
| `.github/workflows/ci.yml` | o CI único (§9.2) |
| `.github/workflows/issues-label.yml` | labels automáticas das issues |
| `.github/workflows/deploy-<alvo>.yml` | deploy, só quando há app (§9.4) |
| `scripts/` | scripts do método (§6) |
| `scripts/lib/` | código comum, `weights.tsv` e `bots.tsv` |
| `scripts/tests/` | testes dos scripts |
| `<checkout principal>/.worktrees/issue-<n>` | worktree da fase, fora do git |
| `<checkout principal>/.process/events.jsonl` | trace, fora do git (§6.3) |

### 7.1 Pesquisa de histórico

`scripts/search-history.sh "termo"` busca nesta ordem: `docs/STATE.md` e índice de ADRs → ADRs, inclusive arquivadas → git (`log --grep`, `log -S`, `blame`; cada commit aponta para o PR e a issue) → issues, PRs e comentários no GitHub. Leia o índice e abra só o que importa.

---

## 8. Labels e templates de issue

### 8.1 Labels

Fonte: `.github/labels.tsv` (nomes em inglês, descrições em português). O `setup-repo.sh` sincroniza e apaga as labels padrão do GitHub.

| Label | Para quê | Quem põe |
|---|---|---|
| `type:feature`, `type:bug`, `type:docs`, `type:chore` | tipo do trabalho; agrupa o changelog | template, workflow |
| `roadmap`, `debt` | trabalho planejado; débito técnico | template, triagem |
| `area:<parte>` | área do código | workflow, triagem |
| `area:billing`, `area:auth`, `area:migration`, `area:credentials` | áreas sensíveis: nunca merge sem ok do dono (§10.3) | workflow, triagem |
| `priority:high`, `priority:medium`, `priority:low` | ordem | template, triagem |
| `group:<afinidade>` | issues planejadas juntas numa spec | triagem |
| `size:small`, `size:medium`, `size:large` | tamanho do achado (§4.2) | quem abre |
| `end:lab-test`, `end:auto-close` | modo de fim da fase | planejamento |
| `needs-context` | não deu para classificar; seção obrigatória vazia | triagem, workflow |
| `needs-owner-ok` | PR toca caminho sensível (§10.3) | CI `policy`, `close-phase.sh --merge` |
| `finding`, `friction` | achado durante o trabalho; atrito do método | agentes |
| `ask:<bot>` | o bot não foi avisado (§5.1) | `notify-bot.sh`; sai quando o bot responde |
| `approved` | ok do dono na spec, pelo GitHub | só o dono do repo |
| `test` | issue de teste; fora do roadmap e do changelog | agentes |

### 8.2 Templates de issue

Templates em Markdown, não issue forms. Cada template tem front matter (`name`, `about`, `title`, `labels`) e o texto-guia em comentários `<!-- -->`. O `config.yml` mantém `blank_issues_enabled: false`.

| Seção (`##`) | feature | bug | debt | finding |
|---|---|---|---|---|
| Objetivo | ✓ | ✓ | ✓ | ✓ |
| Pronto quando | ✓ | ✓ | ✓ | ✓ |
| Arquivos ou áreas afetadas | ✓ | ✓ | ✓ | ✓ |
| Prioridade sugerida | ✓ | ✓ | ✓ | opcional |
| Como reproduzir | | ✓ | | opcional |
| Risco de não fazer | | | ✓ | |
| Achado em | | | | ✓ |
| Sugestão de fim | opcional | opcional | opcional | |
| Bots | opcional | opcional | opcional | opcional |

O `open-issue.sh` e o `auto-label.py` usam exatamente esses títulos. Seção obrigatória vazia recebe `needs-context` e um comentário curto.

### 8.3 Quadro do Projects e runner próprio

São duas ofertas opcionais, feitas uma vez pela skill `setup`, nunca em repositório público.

- `setup-repo.sh --offers` lista as ofertas sem resposta. O "não" fica numa variável do repositório (`setup-repo.sh --decline project|runner`), fora do git.
- **Quadro aceito:** `setup-repo.sh --project`, idempotente: cria o quadro se não houver, vincula ao repo, cria as views que faltam e lê tudo de volta. O que a API não faz sai em linhas `pending:`, e a sessão faz no navegador. Sem o escopo `project` no token do `gh`, o script sai 1 com a linha `fix:`; o passo de login é do dono (skill `setup`).
- **Escopo do `gh`:** toda correção de escopo é um comando só, rodado pelo dono, com a lista completa de escopos que o método usa: `gh auth login -h github.com -p https -w -s gist,project,read:org,repo,workflow` (a lista fica num lugar só, `scripts/lib/project.sh`). Pedir um escopo avulso derruba os outros de um login que outras sessões podem usar. O agente só roda `gh auth status`; nunca pede nem roda `gh auth refresh`, `gh auth logout`, `gh auth setup-git` ou `--with-token`, e nunca define `GH_TOKEN=` ou `GITHUB_TOKEN=` (o `ci.yml` usa o token do próprio job). O `test_gh_login.sh` recusa esses textos no repositório.
- **Escrita no quadro** (`scripts/lib/project.sh`): repo sem quadro não tenta nada. Repo com quadro lê cada escrita de volta; a que não confirma faz o script sair ≠ 0 com `error:` (a causa) e `fix:` (o comando de correção).
- **Status movido pelos scripts:** `open-issue.sh` → `Todo`; `phase-start.sh` → `In Progress`; `close-phase.sh --cleanup` → `Done`; `close-phase.sh --abort` → `Todo`.

| View | Layout | Filtro e agrupamento |
|---|---|---|
| Board por Status | board | colunas = Status |
| Em execução | board | `status:"In Progress"` |
| Fase atual | table | labels `group:*` das fases ativas; `phase-start.sh` põe, `close-phase.sh` tira |
| Por prioridade e área | table | agrupada por Labels |
| Roadmap por group | table | agrupada por Labels (`group:*`) |
| Esperando o dono | table | `label:needs-owner-ok` |
| Bugs abertos | table | `is:open label:type:bug` |

---

## 9. Workflows

### 9.1 Padrão

- Nome do arquivo: `ci.yml` para o CI único; para os outros, prefixo da categoria (`deploy-`, `issues-`, `release-`, `bot-`) mais a finalidade.
- `name` legível em inglês, `run-name` que explica a execução, `name` em todo job e passo.
- Conferido no CI pelo `actionlint` e pelo `scripts/check-workflows.py`.

### 9.2 `ci.yml`

O arquivo é a fonte. Jobs: `changes`, `policy`, `lint`, `tests`, `workflows` e o agregador `CI`.

| Técnica | Regra |
|---|---|
| CI só no PR | roda em `pull_request` (`opened`, `synchronize`, `reopened`, `ready_for_review`); nada de CI no push da `main` |
| Um run por rodada | editar título, corpo e labels do PR não gera run. O corpo final é conferido pelo `close-phase.sh --merge` |
| Filtro de mudanças | o job `changes` decide o que roda, por `git diff` da base ao HEAD; o gatilho não usa `paths-ignore`, para o `CI` sempre reportar |
| Jobs condicionais | filtro por exclusão: doc é arquivo em `docs/` e `.md` (fora os templates de issue); todo o resto é código e roda `lint`. O job `tests` roda em todo PR, inclusive no só de docs: os testes leem `AGENTS.md`, as skills e este desenho. PR só de docs pula só o `lint`; o `ci-gate.sh` exige `tests` sempre e só dispensa o `lint` com `code` exatamente `false` |
| `policy` | sempre roda: assinatura de IA nos commits e no corpo do PR, `.github/sensitive-paths` → label `needs-owner-ok`, `check-docs.sh` (o da base, sobre os docs do PR) |
| Verificadores da base | `ci-gate.sh`, `check-attribution.sh`, `check-docs.sh`, `sensitive_paths.py` e `.github/sensitive-paths` são lidos do commit base do PR: o PR não enfraquece a checagem que o julga |
| Agregador | o job `CI`, com `if: always()`, é o único check exigido além de `review/independent`; falha se um job necessário falhou ou foi pulado sem motivo |
| Runner | todo `runs-on` lê `vars.CI_RUNS_ON` (JSON: string ou lista de labels), padrão `ubuntu-latest` |
| Concurrency | cancela o CI em andamento do mesmo PR |
| Timeouts | `timeout-minutes` em todo job (5–30) |
| Permissões mínimas | `permissions: {}` no topo, liberadas por job |
| Sem trabalho repetido | o shellcheck roda uma vez, dentro do `validate.sh` |

O `issues-label.yml` roda em `opened` e em `edited` só quando o corpo mudou, com `contents: read` e `issues: write`.

### 9.3 Runner próprio

O registro é só `scripts/setup-runner.sh --register`. Ele recusa repo público e repo de visibilidade ilegível, porque o runner rodaria o código de qualquer PR. Um runner recusado no setup só volta a ser oferecido pelo gatilho da triagem (`triage.sh --runner-offer`): média de run acima de 5 minutos ou cota acima de 50%.

### 9.4 Deploy (regra-base 3)

Um deploy por grupo de fases, disparado só pelo `scripts/deploy.sh`, rodado pela sessão principal no checkout principal, no passo único de fim, depois do `gen-docs.sh`. Nenhuma sessão de fase faz deploy, e o `close-phase.sh` não dispara nada.

O `deploy.sh`:

1. **Recusa (saída 1), sem disparar nada:** fora do checkout principal; sem id de sessão; em sessão que tem `phase_session` no trace de issue que ela não abriu; com `.worktrees/parallel-active.tsv` não vazio; com worktree de fase (`.worktrees/issue-<n>`); com PR de fase aberto.
2. **Decide, para cada `deploy-*.yml` da `origin/main`:** o SHA já tem deploy com sucesso, não dispara; há um run em andamento no SHA, espera esse run; nada mudou, desde o último deploy com sucesso, nos caminhos da linha `# deploy-paths:` do workflow, não dispara; run que falhou no SHA é disparado de novo.
3. **Dispara** por `workflow_dispatch` na `main`, imprime a URL do run, espera o fim e lê o resultado.

| Saída | Significa | O que a sessão principal faz |
|---|---|---|
| 0 com `deployed:` | o run terminou com sucesso | cita a linha e a URL no status |
| 0 com `no deploy:` | nada a publicar | cita a linha no status |
| 3 | o run não terminou no prazo | lê o run pela URL e roda `deploy.sh` de novo |
| 4 | o run falhou | lê o run, corrige e roda `deploy.sh` de novo |

O `deploy-*.yml` roda só por `workflow_dispatch`; o primeiro job roda o `scripts/validate.sh` na `main` e todos os outros dependem dele; `concurrency` com `cancel-in-progress: false`. O `check-workflows.py` recusa deploy com outro gatilho, sem a linha `# deploy-paths:` e sem o job de validação. Disparo fora do `deploy.sh` é barrado pelo `block-dangerous-git.sh` (§6.2, item 9) e pelo deny do `.claude/settings.json`.

---

## 10. Portão de merge e proteção

### 10.1 Proteção de branch e configurações do repo

Aplicadas e lidas de volta pelo `setup-repo.sh`:

- Checks exigidos: `CI` e o commit status `review/independent`. Sem "branch atualizada" obrigatória (um rebase geraria SHA novo e derrubaria o status da revisão).
- 0 aprovações exigidas: os agentes usam a conta do dono, que não aprova o próprio PR.
- Histórico linear obrigatório; vale para admins; sem force-push; sem deleção.
- Repo: auto-merge ligado; só rebase (merge commit e squash desligados); branch apagada no merge.
- Sem a proteção não há merge: o `close-phase.sh --merge` recusa. Plano sem proteção de branch (repo privado em conta gratuita): o `setup-repo.sh` sai 6 e indica a correção.

### 10.2 Revisão independente

O agente `close-reviewer`, aberto com o par do peso `reviewer` (§3), lê a issue, o diff e a saída dos testes, nunca o resumo do executor. A sessão filha salva o parecer num arquivo e o publica com `close-phase.sh --publish-review` (§6.1, passo 4). Todo push novo gera SHA sem o status: a revisão roda de novo. É salvaguarda de processo, não barreira de segurança (mesma conta).

| Situação | Regra |
|---|---|
| Problema grave ou médio dentro do escopo da issue | bloqueia; a filha corrige num commit novo e roda o `--prepare` de novo |
| Ponto leve só em arquivos do PR | não bloqueia; a filha corrige num commit no PR, e a rodada seguinte confere |
| Ponto leve em outros arquivos | não bloqueia; entra numa única issue `finding` guarda-chuva por grupo, com checklist |
| Critério que não dá para provar na sessão | vira nota no parecer, nunca bloqueio |
| Rodada N+1 | olha só o diff desde a rodada N e as regressões que ele causou |
| 3ª rodada de "mudanças pedidas" | a filha para e avisa a sessão principal, que faz o quadro ao dono: corrigir, aceitar com achado, pausar |
| Registro | toda rodada, aprovada e reprovada, vira comentário no PR |

### 10.3 Nunca fecha sozinho

Lista: cobrança, autenticação, migração de banco, credenciais, infraestrutura de produção, dependências e lockfiles. Vale mesmo com `end:auto-close`. Três camadas:

1. As labels `area:billing`, `area:auth`, `area:migration` e `area:credentials` são aplicadas pela triagem e pelo workflow.
2. `.github/sensitive-paths` tem os globs do projeto e os arquivos do próprio portão (`close-phase.sh`, workflows de deploy, `ci.yml`, os verificadores lidos da base e a própria lista); o job `policy` do CI põe `needs-owner-ok` quando o diff toca um deles.
3. O `close-phase.sh --merge` sai 5 com `needs-owner-ok` ou com label de área sensível. A filha pede o ok do dono num quadro `Fase #<n> — <título>:` e roda `--merge --owner-ok --wait`. O `--owner-ok` só vale com a label `needs-owner-ok` já posta no PR: sem ela, a recusa põe a label e sai 5.

Para todo o resto, `end:auto-close` vale como ok prévio do dono para o merge.

### 10.4 `.claude/settings.json`

O arquivo é a fonte. Ele precisa ter:

- `attribution` com `commit` e `pr` vazios;
- `allow` para os scripts, para a leitura e escrita de issues e PRs com `gh` e para os comandos de git do dia a dia;
- `deny` para `gh pr merge`, push forçado, `git reset --hard`, apagar o repo, disparo de workflow e leitura direta de segredo; o deny vence o allow;
- os hooks da §6.2, cada um no evento da tabela.

A assinatura de IA é barrada em quatro camadas: configuração, regra no `AGENTS.md`, hook e CI `policy`.

---

## 11. Pacote do método

Ainda não existe: o método como um pacote versionado (plugin com skills, comandos, agentes, hooks e scripts), atualizado em cada repo por um comando.
