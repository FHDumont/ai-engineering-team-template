# Template de time de engenharia com IA

Template de repositório para trabalhar com agentes de IA de código (Claude Code) e um dono que aprova e testa. A issue é a porta de entrada, o contexto carregado sempre é pequeno, os fluxos repetidos são scripts testados e todo merge passa por um portão só: o check `CI` mais a revisão independente (`review/independent`).

O desenho completo está em [docs/process-design.md](docs/process-design.md). As regras para os agentes estão em [AGENTS.md](AGENTS.md).

## Como funciona

1. O trabalho entra como issue, por template.
2. A triagem lê só títulos e labels e sugere os grupos.
3. O planejamento escreve uma spec curta por fase em `docs/specs/`, e o dono do repo aprova com um ok.
4. Cada fase roda numa sessão filha, em branch e worktree próprios, com um commit por etapa.
5. O fecho abre o PR, roda a revisão independente e faz o merge pelo portão.
6. Depois do último merge do grupo, a sessão principal faz o passo único de fim: gera `CHANGELOG.md` e `ROADMAP.md`, faz o deploy e confere que nada sobrou.

Opcional: um time de bots que respondem em issues por webhook ([docs/BOTS.md](docs/BOTS.md)).

## As cinco regras-base

Cada regra tem uma trava que roda sozinha e sai com erro. A tabela é a do desenho.

| Regra | Trava | Código de saída |
|---|---|---|
| 1. Plan obrigatório: a fase só abre com spec no git que cita a issue | `scripts/phase-start.sh` | 1 |
| 2. Fase em sessão filha: a sessão que abriu a fase não escreve nela | `.claude/hooks/block-phase-commit.sh` e `.claude/hooks/block-phase-edit.sh`; `.githooks/reference-transaction`; `scripts/close-phase.sh` | 2 nos hooks do agente; 1 no hook do git; 9 no `close-phase.sh` |
| 3. Deploy único pela sessão principal | `scripts/deploy.sh`; `.claude/hooks/block-dangerous-git.sh` | 1 no `deploy.sh`; 2 no hook |
| 4. Conflito mecânico sem cartão: PR em conflito com a `main` é refeito por script | `scripts/close-phase.sh --check`, que chama `scripts/redo-phase.sh` | 0 com o PR novo; 4 com conflito real |
| 5. Fim coerente: `pronto` só com o fim limpo | `scripts/status.sh --state pronto`, que roda `scripts/end-check.sh` | 1 |

## Começo rápido

1. Crie o seu repositório com **Use this template** e clone.
2. Abra o repositório no Claude Code e diga "configurar o repo". O agente roda `scripts/setup-repo.sh` (labels, proteção da `main`, configurações do repo) e faz as perguntas do setup num quadro de escolha, incluindo a meta de tempo (fase abaixo de 45 min e `validate.sh` abaixo de 240 s, por padrão) e, na primeira vez em cada máquina, os limites dela (`~/.config/ai-method/machine-limits.env`). Só aí: depois, o agente só o chama de novo se o fim de um grupo ficar acima da meta. Você não roda script nem mexe em configuração.
   Sem o setup aplicado, o `scripts/phase-start.sh` e o `scripts/open-issue.sh` recusam e dizem "configurar o repo".
3. Abra a primeira issue por um [template](../../issues/new/choose).
4. Diga "executar #n" (o número da issue). O agente planeja, pede o seu ok na spec, abre a fase numa sessão filha e fecha pelo portão.

Antes da primeira fase, troque o que é exemplo: a pasta `app/`, o passo de deploy de `.github/workflows/deploy-example.yml`, os globs de `.github/sensitive-paths`, as labels `area:*` de `.github/labels.tsv` e os bots de `.github/bots.tsv` e `docs/BOTS.md`.

## Requisitos

- **Claude Code** no app desktop: o método usa sessões filhas abertas pela sessão de planejamento.
- **`gh`** (GitHub CLI) autenticado, com os escopos `gist`, `project`, `read:org`, `repo` e `workflow`. Faltou escopo: o único comando a rodar é `gh auth login -h github.com -p https -w -s gist,project,read:org,repo,workflow`.
- **`git`**, **`bash`** (3.2 ou mais novo), **`jq`**, **`shellcheck`**, **`python3`** e **`curl`**.
- **Proteção de branch:** o portão exige a proteção da `main` com `CI` e `review/independent`. O GitHub só oferece proteção de branch em repositório público ou em plano pago. Sem ela (repositório privado em plano gratuito), o `scripts/setup-repo.sh` lista a entrada no modo sem proteção e só a grava com ok do dono; uma resposta "Upgrade to GitHub" não grava o modo sozinha. Com o modo gravado, as travas passam a ser de script: o `scripts/close-phase.sh --merge` confere pela API que `CI` e `review/independent` estão verdes (saída 11 se não) e um hook recusa push na `main`. O servidor não impede um merge feito à mão pelo GitHub (`docs/process-design.md` §10.5).
- **Runner:** o CI usa runners hospedados pelo GitHub (`ubuntu-latest`) por padrão. Repositório público usa só runners hospedados: o `scripts/setup-runner.sh` recusa registrar runner próprio em repositório público, porque ele rodaria o código de qualquer PR. Em repositório privado, o runner próprio é opcional e a variável `CI_RUNS_ON` aponta para ele.
- **Modelos:** os pares de modelo e esforço ficam em `scripts/lib/weights.tsv`. O padrão roda num plano que só tem o Sonnet; para usar outros modelos, edite só esse arquivo.
- **Segredos dos bots (só no caminho B):** o padrão é um `.env` fora do repositório, criado vazio pelo `scripts/init-env.sh`. Detalhes em [docs/BOTS.md](docs/BOTS.md).

## Mínimo suportado

O método foi validado de ponta a ponta com o modelo Sonnet em esforço `low` nas sessões de fase e na sessão principal, e com o revisor em Sonnet em esforço `medium`. É o padrão de `scripts/lib/weights.tsv` e o mínimo suportado.

Cenários que passaram nesse mínimo, num repositório criado a partir deste template:

| Cenário | O que foi conferido |
|---|---|
| "executar #n" sozinho | a spec é escrita e commitada antes de a fase abrir |
| Fase em sessão filha | a sessão principal não escreve na fase; a tabela pedido × usado do PR confere |
| Fases paralelas com conflito | o PR em conflito é refeito por script, sem pergunta ao dono |
| Deploy único no fim | um deploy por grupo, disparado pela sessão principal |
| Fim coerente | `scripts/end-check.sh` limpo: só a `main`, sem spec, worktree ou branch sobrando |

Também rodou com a sessão principal em Sonnet em esforço `medium` e com tudo em Opus em esforço `medium` (pesos trocados em `scripts/lib/weights.tsv`).

Limites conhecidos:

- **Abertura das sessões filhas.** O app só abre a sessão filha sozinho quando o pedido ("executar #n") vem do dono, na sessão principal. Num turno automático a filha vira um cartão que o dono clica; com o Remote Control ligado, nem o cartão aparece. Fases em sequência pedem um toque do dono por fase; um grupo paralelo abre todas de uma vez.
- **Batimento da sessão principal.** A tarefa recorrente que acorda a sessão principal é uma instrução impressa pelo `scripts/phase-start.sh`; nenhum script confere que ela existe.
- **Ação do passo de fim negada pelo app.** O caminho (quadro de autorização ao dono) está nas skills e tem teste de texto, mas não apareceu em nenhuma rodada de validação.
- **Proteção de branch.** Sem ela (plano gratuito, repo privado) vale o modo sem proteção: o portão é de script e o GitHub não impede um merge feito à mão (veja Requisitos).

## Adotar num repositório que já existe

Para levar a este método um repositório que já tem código e usa outro processo (ou uma versão antiga deste), sem tocar no código da aplicação. Não existe script que faça a adoção: os passos abaixo são manuais, feitos pelo agente no clone do repositório, e cada um traz a frase a dizer a ele. O dono só aprova e faz o merge do passo 9.

Sinal de adoção bem feita: o PR de adoção muda só arquivos do processo; o código da aplicação (a pasta da aplicação, `package.json` ou equivalente) não aparece no diff.

1. **Pré-requisitos.** Diga: "confira os pré-requisitos da adoção". O agente confere: `gh auth status` com os escopos `gist`, `project`, `read:org`, `repo` e `workflow` (faltando, o dono roda o único comando da seção Requisitos); proteção de branch disponível (repositório público ou plano pago; sem ela o modo sem proteção só entra com ok do dono); e nenhuma fase do processo antigo em andamento: sem PR de fase aberto, sem branch de trabalho pendente, sem deploy do processo antigo rodando (`gh pr list`, `git branch -r`, `gh run list`). Termine o que estiver em andamento antes de seguir.
2. **Branch de adoção.** Diga: "abra a branch de adoção a partir da main". O agente roda `git switch -c chore/adopt-method` a partir da `main` atualizada. A adoção é um PR único; nada vai direto na `main`.
3. **O que sai.** Diga: "liste os arquivos do processo antigo e remova". O que é do processo antigo e some: o arquivo de instruções de agente (o novo é `AGENTS.md`, com o `CLAUDE.md` de uma linha), as regras de agente de outras ferramentas que o repositório tinha, os scripts do processo, os templates de issue, o template de PR e os workflows do processo (CI de processo, rotulagem, release). Não saem os workflows nem os scripts da aplicação, que o passo 6 e o passo 7 tratam. Confira cada remoção com `git diff --stat` antes de seguir.
4. **O que entra.** Diga: "traga do template os caminhos do método". O agente copia do template, pasta por pasta, exatamente estes caminhos:
   - raiz: `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md` e `.gitignore` (se o repositório já tem `.gitignore`, junte só as linhas `.worktrees/`, `.process/`, `.env`, `*.env`, `__pycache__/` e `*.pyc`);
   - `.claude/agents/`, `.claude/commands/`, `.claude/hooks/` (com `.claude/hooks/tests/`), `.claude/skills/` e `.claude/settings.json` no mesmo passo. Inventarie os hooks e os `deny` que o repositório já tinha e prove que cada bloqueio segue valendo (o hook antigo de mesmo nome fica ao lado, com outro nome, ligado no `.claude/settings.json`). Se o repositório já tem um `.claude/settings.json`, mostre o diff das permissões (`allow` e `deny`) e espere o ok do dono; só depois o arquivo novo é o que a sessão usa. O `allow` do método lista cada script pelo nome: não copie `Bash(scripts/*)` nem um `git push` genérico;
   - `.cursor/rules/`;
   - `.githooks/`: ativados depois, no passo 8, por `scripts/check-env.sh`;
   - `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md`, `.github/labels.tsv`, `.github/bots.tsv`, `.github/sensitive-paths`, `.github/workflows/ci.yml` e `.github/workflows/issues-label.yml`;
   - `docs/process-design.md`, `docs/BOTS.md`, `docs/STATE.md`, `docs/adr/` e `docs/diagrams/`;
   - `scripts/`: a pasta inteira, com `scripts/lib/` e `scripts/tests/`.
5. **O que NÃO se copia.** `app/` (é só o exemplo; a aplicação do repositório fica onde está), `.github/workflows/deploy-example.yml` (o passo 6 adapta o deploy que a aplicação já tem), `CHANGELOG.md` e `ROADMAP.md` (são gerados por `scripts/gen-docs.sh` no fim do primeiro grupo) e o conteúdo de `docs/specs/` (cada repositório escreve as suas; só a pasta existe). Troque o que é exemplo: os globs de `.github/sensitive-paths`, as labels `area:*` e `group:*` de `.github/labels.tsv` e os bots de `.github/bots.tsv` e `docs/BOTS.md`. Se o repositório já tinha labels que o método deve renomear, ponha o nome antigo na quarta coluna de `.github/labels.tsv`.
6. **Adaptar o deploy que a aplicação já tem.** Diga: "adapte o deploy da aplicação às regras do método". O agente reescreve o workflow de deploy existente como `.github/workflows/deploy-<alvo>.yml`, usando `.github/workflows/deploy-example.yml` como modelo, e confere com `python3 scripts/check-workflows.py`. As regras, todas conferidas por esse script: o nome é `deploy-<alvo>.yml`; o único gatilho é `workflow_dispatch` (nunca `pull_request`, `push` ou `schedule`: quem dispara é `scripts/deploy.sh`, uma vez por grupo, pela sessão principal); a linha `# deploy-paths:` lista o que o workflow publica; um job roda `scripts/validate.sh` e todos os outros dependem dele, antes do build; `permissions: {}` no topo, `concurrency`, `name` e `run-name`, e `name`, `runs-on` e `timeout-minutes` entre 5 e 30 em cada job. A parte que publica de verdade continua a da aplicação. Deploy que não cabe nessas regras fica fora do método: o agente descreve o que sobrou no PR.
7. **Ligar os testes da aplicação ao CI.** Diga: "ligue os testes e o build da aplicação ao CI". O CI é `.github/workflows/ci.yml` e já roda `scripts/validate.sh --lint` e `scripts/validate.sh --tests`. O agente faz duas coisas: acrescenta o comando de teste da aplicação a `scripts/validate.sh`, no bloco `--tests` (o próprio arquivo diz que "App tests join here once there is an app"); e troca, no job `tests` de `.github/workflows/ci.yml`, o passo de build do exemplo pelo build da aplicação, ajustando a regex da saída `app` do job `changes` para os caminhos da aplicação. Um workflow antigo de testes da aplicação passa a ser coberto pelo CI do método e é removido.
8. **Validar antes do PR.** Não rode a suíte antes de separar os scripts da aplicação dos scripts do método: o teste de ajuda percorre uma lista fechada dos scripts do método e não executa o resto de `scripts/`. Numa cópia anterior a essa separação, o mesmo teste percorria a pasta inteira e executava o que achava, inclusive script da aplicação. Diga: "rode a validação". O agente roda `scripts/validate.sh` e `scripts/check-docs.sh` e só segue com os dois saindo 0. As varreduras da suíte incluem os arquivos ainda não rastreados que não são ignorados. Roda também `scripts/check-env.sh`, que instala os hooks do git (`core.hooksPath=.githooks`). Corrija o que falhar na própria branch; a causa mais comum é um nome do exemplo ainda citado num doc.
9. **PR de adoção e merge pelo dono.** Diga: "abra o PR de adoção". O agente abre o PR com `gh pr create`, em português, listando o que saiu, o que entrou e o que foi adaptado. O PR não passa pelo portão do método, que ainda não existe: sem a proteção da `main` com `CI` e `review/independent`, e sem `scripts/close-phase.sh` em uso. Por isso o merge é do dono, pelo GitHub, depois de o check `CI` do PR passar. O agente não faz o merge.
10. **Configurar o repo.** Depois do merge, diga: "configurar o repo". A skill `setup` roda `scripts/setup-repo.sh` (labels, configurações e proteção da `main`) e faz as perguntas num quadro de escolha: nome e objetivo, stack, bots, segredos, runner, quadro do GitHub Projects e se o headless fica ligado (padrão: desligado). Num repositório que já tinha runner próprio (variável `CI_RUNS_ON`), o runner não é perguntado de novo.
11. **Issues abertas e labels antigas.** Diga: "rotule as issues abertas pelo método". O `scripts/setup-repo.sh` apaga só as labels padrão do GitHub e renomeia as que têm nome antigo em `.github/labels.tsv`; as outras labels antigas ficam como estão. O agente roda `scripts/triage.sh` para ver o que falta (tipo, prioridade, área), aplica com `scripts/label-issue.sh` e apaga as labels antigas que sobrarem com `gh label delete`, depois de conferir que nenhuma issue aberta ainda as usa.
12. **Primeira fase como teste.** Abra uma issue pequena por um template de `.github/ISSUE_TEMPLATE/` (a label `test` a tira do roadmap e do changelog) e diga "executar #n". Se a fase abrir, rodar e fechar pelo portão (`CI` mais `review/independent`), a adoção funcionou.

## Atualizar um repositório que já usa o método

As melhorias do template chegam como um PR de atualização, feito pelo agente. Diga: "traga as melhorias do template". Ele compara o repositório com o template e copia só o que é do método.

- **Traz de novo do template:** `scripts/` (inclusive `scripts/lib/` e `scripts/tests/`), `.claude/agents/`, `.claude/commands/`, `.claude/hooks/`, `.claude/skills/`, `.githooks/`, `.cursor/rules/`, `AGENTS.md`, `CLAUDE.md`, `docs/process-design.md`, `docs/adr/TEMPLATE.md`, `.github/ISSUE_TEMPLATE/`, `.github/pull_request_template.md`, `.github/workflows/ci.yml` e `.github/workflows/issues-label.yml`. Caminho sensível novo do método entra pelo código de `scripts/lib/sensitive_paths.py`, sem apagar as linhas de `.github/sensitive-paths` do repositório.
- **É do repositório e não se sobrescreve:** `docs/STATE.md`, `CONTEXT.md`, `docs/BOTS.md`, `docs/specs/`, `CHANGELOG.md` e `ROADMAP.md` (gerados), `.github/labels.tsv`, `.github/bots.tsv`, `.github/time-targets.tsv` (a meta de tempo do projeto), `.github/sensitive-paths`, `.github/required-checks` (checks extras da proteção), `.github/headless` (headless ligado ou não), `.claude/settings.json` (mostre o diff das permissões e espere o ok do dono antes de a sessão usar o settings novo), as ADRs do próprio repositório em `docs/adr/` (traga só as novas do método e some a linha em `docs/adr/INDEX.md`), os workflows `deploy-*.yml`, o passo de build de `.github/workflows/ci.yml` e o bloco de testes da aplicação em `scripts/validate.sh` (ao trazer esses dois arquivos, mantenha essas partes), e tudo da aplicação.
- Antes do PR, rode `scripts/validate.sh` e `scripts/check-docs.sh`. Se as `.github/labels.tsv` do template ganharam labels, rode `scripts/setup-repo.sh --only labels` depois do merge.

## Rodar e testar

- `scripts/validate.sh`: lint (shellcheck) e todos os testes.
- `scripts/check-docs.sh`: limites dos docs e o desenho contra o repositório.
- Limites da máquina (vagas de validação e de fase, tempo de espera, avisos de carga): `~/.config/ai-method/machine-limits.env`, criado na primeira execução. `scripts/machine-slots.sh --status` mostra quem ocupa as vagas e `--report` compara espera e duração. Mesma tabela de parâmetros no `docs/process-design.md` §6.4. `scripts/sessions.sh --list` mostra as sessões e os MCPs por repo; no fim da fase o `close-phase.sh --cleanup` encerra os processos do worktree, e a sessão do app só o dono arquiva (menu ⋯ → Archive, nunca deletar).

| Parâmetro | Padrão | Unidade | Efeito |
|---|---|---|---|
| `AI_METHOD_SLOTS_VALIDATE` | 2 | execuções | `validate.sh` ao mesmo tempo na máquina |
| `AI_METHOD_SLOTS_FASE` | 3 | fases | fases abertas ao mesmo tempo |
| `AI_METHOD_WAIT_TIMEOUT_SECONDS` | 1200 | segundos | espera máxima por vaga |
| `AI_METHOD_POLL_SECONDS` | 2 | segundos | pausa entre olhadas na fila |
| `AI_METHOD_WARN_LOAD1` | 8 | load de 1 min | aviso de carga |
| `AI_METHOD_WARN_FREE_MEM_MB` | 1024 | MB | aviso de memória livre baixa |
| `AI_METHOD_WARN_SWAP_MB` | 2048 | MB | aviso de swap alto |
| `AI_METHOD_LINT_BASE` | main | ref do git | base do lint incremental |
- Todo script tem `--help`.

## Idioma

Código, comentários no código, identificadores, nomes de arquivos, labels, nomes de workflows, jobs e checks, `--help`, saída dos scripts e mensagens de commit ficam em inglês. Docs, issues, PRs, comentários neles e a conversa com o dono do repo ficam em português (pt-BR). Detalhes na §1 do desenho.

## Onde está cada coisa

- Desenho do método: [docs/process-design.md](docs/process-design.md)
- Regras para agentes: [AGENTS.md](AGENTS.md) · estado atual: [docs/STATE.md](docs/STATE.md) · glossário: [CONTEXT.md](CONTEXT.md)
- Regras do projeto (nomes, medidas e o que não é do método): `docs/repo-notes.md`. O `AGENTS.md` aponta para esse arquivo e fica abaixo do teto de palavras, para o projeto poder acrescentar uma linha.
- Decisões herdadas do método: [docs/adr/INDEX.md](docs/adr/INDEX.md)
- Roadmap e changelog (gerados): [ROADMAP.md](ROADMAP.md) · [CHANGELOG.md](CHANGELOG.md)
