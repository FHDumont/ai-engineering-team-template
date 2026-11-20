---
name: setup
description: Configura o repo pelo método num único quadro de escolha — nome e objetivo, stack, lab, bots, segredos, runner próprio e quadro do GitHub Projects. Use em "configurar o repo", "setup", "repo novo", depois do merge do PR de adoção ou na migração de um repo com processo parecido. Frases: "configurar o repo", "configurar o repositório".
---

# Setup

Roda na primeira sessão de um repo novo, depois do merge do PR de adoção e na migração de repo com processo parecido.

1. Rode `scripts/setup-repo.sh --dry-run` e `scripts/setup-repo.sh --offers` para ver o que falta. Na migração, rode `gh variable list`: se `CI_RUNS_ON` já existir, não faça a pergunta do runner.
2. Faça **um quadro de escolha** (`AskUserQuestion`, uma pergunta por decisão): nome e objetivo; stack; lab; bots; onde ficam os segredos; runner próprio na máquina do dono do repo; quadro do GitHub Projects. Para os segredos, a pergunta é só "Criar o `.env` para você?" (a alternativa opcional é a conta de serviço do gerenciador de senhas; veja `docs/BOTS.md`). Os segredos são um quadro só, com essa única pergunta; nunca uma pergunta de provedor seguida de outra de arquivo.
3. Nada é criado no GitHub sem um "sim" no quadro, e nada é dado como criado sem ler de volta (`process-design` §2.1). Aplique só o que foi aceito:
   - padrão do repo: `scripts/setup-repo.sh`;
   - quadro: confira `gh auth status`; sem `project` (que inclui a leitura), rode `gh auth refresh --scopes project,read:project` (abre o navegador; nunca o fluxo de digitar o código, nunca preencha o campo por agente) e pare em `esperando você` só com "fazer login e autorizar no navegador". Na volta, confira o escopo de novo e rode `scripts/setup-repo.sh --project` (idempotente: vincula, cria as views que faltam, lê os workflows). Cada linha `pending:` a sessão faz no mesmo navegador (view recusada, workflows nativos *Auto-add to project*, *Item added to project*, *Item closed* e *Pull request merged*); só declare pronto depois de ler de volta o quadro (`gh project view <n> --owner <dono>`), o vínculo no repo, as views pelo nome e layout e os workflows ligados;
   - recusas: `scripts/setup-repo.sh --decline project|runner|runner-trigger`;
   - runner: `scripts/setup-runner.sh --dry-run` mostra os passos. Com o "sim" do quadro, se você alcança a máquina do lab, rode você mesmo `scripts/setup-runner.sh --register` (`--dir`, `--name` e `--label` se couber) e só declare pronto depois de ler de volta `gh api repos/<slug>/actions/runners` (runner online) e `gh variable get CI_RUNS_ON`. Se o dono precisar rodar à mão (máquina que você não alcança), o passo a passo aponta só o script `scripts/setup-runner.sh --register`, nunca comandos soltos (`config.sh`, `svc.sh`, `curl` do pacote, token do `gh api`).
   - `.env` com "sim": rode `scripts/init-env.sh` (cria `~/.<repo-slug>/.env`, pasta 700 e arquivo 600, só com as chaves vazias `BOT_WEBHOOK_<SLUG>_URL=` e `_SECRET=`). Peça ao dono do repo para abrir o arquivo que o script imprimiu e colar os valores. O agente nunca lê nem escreve valores. Depois confira com `source scripts/lib/secret.sh; secret_ready BOT_WEBHOOK_<SLUG>_URL` de cada bot escolhido (só o código de saída, nada é impresso).
4. Registre nome, objetivo e stack em `docs/STATE.md`.
5. Termine com a saída de `scripts/status.sh` colada como está (três linhas em negrito, sem bloco de código).
