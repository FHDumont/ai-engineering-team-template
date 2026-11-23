# Bots (caminho B)

Opcional. O `scripts/ask-bot.sh` comenta a pergunta na issue e chama o webhook do bot. A resposta é reconhecida pela marca `<!-- bot:<slug> reply-to:<id> -->`, não pelo autor: funciona mesmo quando todos usam a mesma conta do GitHub.

Os bots abaixo são exemplos. Troque as linhas pelos bots do seu time e mantenha os mesmos slugs em `.github/bots.tsv` (slug, nome e referência do webhook); as labels `ask:<slug>` saem da linha-modelo de `.github/labels.tsv`, uma por bot.

| Slug | Nome | Papel | Quando perguntar | Nunca pode |
|---|---|---|---|---|
| `bot-a` | Bot A | coordena o time e o processo | dúvida sobre o processo, prioridade, qual bot consultar | mexer em código, aprovar spec, repassar ok do dono |
| `bot-b` | Bot B | especialista de uma área (exemplo: texto do produto) | texto e tom de página, posicionamento | publicar algo, decidir pelo dono |

Bot sem webhook configurado: o `notify-bot.sh` põe `ask:<slug>` na issue e o agente segue.

## Segredos dos webhooks

O `scripts/lib/secret.sh` procura a URL e o segredo de cada bot nesta ordem (sem nenhum provedor, o `ask-bot.sh` para antes de postar):

1. variáveis de ambiente `BOT_WEBHOOK_<SLUG>_URL` e `BOT_WEBHOOK_<SLUG>_SECRET` (CI);
2. opcional: conta de serviço do gerenciador de senhas;
3. padrão: `.env` fora do repo.

**`.env` (padrão):** fica em `~/.<nome-do-repo>/.env` (pasta 700, arquivo 600; `PROCESS_ENV_FILE` troca o caminho). O agente cria o arquivo só com as chaves vazias (`scripts/init-env.sh <slug>...`); o dono do repo o abre e cola os valores. O script recusa permissão aberta, e o arquivo fica fora do git.

**Gerenciador de senhas (opcional):** o código aceita uma conta de serviço lida pelo CLI `op`. Crie uma conta só de leitura no cofre dos webhooks, um item por bot (campos `url` e `secret`), e ponha `op://<cofre>/<item>` em `.github/bots.tsv`. O token da conta fica no cofre do sistema, nunca no repo. O agente só chama o `op` pelos scripts.

## Identidade

Todo comentário de agente ou bot abre com `**De:** bot <nome> · **Para:** <papel> · **Pedido:** <ask_id> · **Responde a:** <link>` (a resposta também; o papel não é assinatura de IA); sem o cabeçalho, é do dono. Pedido a bot só pelo `ask-bot.sh`. Toda resposta começa com `**<Nome> (bot do time)**`, sem emoji nem assinatura de IA.

O dono cria a GitHub App do bot (`<slug>[bot]`, issues e pull requests em escrita). O token de instalação é `GH_APP_BOT_<SLUG>_TOKEN` no ambiente ou no `.env`. Com ele, o bot comenta como a App. Sem ele, o comentário do método usa o `gh` do dono. `ROLE_APP_REQUIRE=1` recusa até a App existir. Nada é criado na conta pelo agente.
