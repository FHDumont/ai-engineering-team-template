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
2. Abra o repositório no Claude Code e diga "configurar o repo". O agente roda `scripts/setup-repo.sh` (labels, proteção da `main`, configurações do repo) e faz as perguntas do setup num quadro de escolha. Você não roda script nem mexe em configuração.
3. Abra a primeira issue por um [template](../../issues/new/choose).
4. Diga "executar #n" (o número da issue). O agente planeja, pede o seu ok na spec, abre a fase numa sessão filha e fecha pelo portão.

Antes da primeira fase, troque o que é exemplo: a pasta `app/`, o passo de deploy de `.github/workflows/deploy-example.yml`, os globs de `.github/sensitive-paths`, as labels `area:*` de `.github/labels.tsv` e os bots de `docs/BOTS.md`.

## Requisitos

- **Claude Code** no app desktop: o método usa sessões filhas abertas pela sessão de planejamento.
- **`gh`** (GitHub CLI) autenticado, com os escopos `gist`, `project`, `read:org`, `repo` e `workflow`. Faltou escopo: o único comando a rodar é `gh auth login -h github.com -p https -w -s gist,project,read:org,repo,workflow`.
- **`git`**, **`bash`** (3.2 ou mais novo), **`jq`**, **`shellcheck`**, **`python3`** e **`curl`**.
- **Proteção de branch:** o portão exige a proteção da `main` com `CI` e `review/independent`. O GitHub só oferece proteção de branch em repositório público ou em plano pago. Sem ela, o `scripts/setup-repo.sh` sai 6 e o `scripts/close-phase.sh --merge` recusa todo merge.
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
- **Proteção de branch.** Sem ela o portão recusa todo merge (veja Requisitos).

## Rodar e testar

- `scripts/validate.sh`: lint (shellcheck) e todos os testes.
- `scripts/check-docs.sh`: limites dos docs e o desenho contra o repositório.
- Todo script tem `--help`.

## Idioma

Código, comentários no código, identificadores, nomes de arquivos, labels, nomes de workflows, jobs e checks, `--help`, saída dos scripts e mensagens de commit ficam em inglês. Docs, issues, PRs, comentários neles e a conversa com o dono do repo ficam em português (pt-BR). Detalhes na §1 do desenho.

## Onde está cada coisa

- Desenho do método: [docs/process-design.md](docs/process-design.md)
- Regras para agentes: [AGENTS.md](AGENTS.md) · estado atual: [docs/STATE.md](docs/STATE.md) · glossário: [CONTEXT.md](CONTEXT.md)
- Decisões herdadas do método: [docs/adr/INDEX.md](docs/adr/INDEX.md)
- Roadmap e changelog (gerados): [ROADMAP.md](ROADMAP.md) · [CHANGELOG.md](CHANGELOG.md)
