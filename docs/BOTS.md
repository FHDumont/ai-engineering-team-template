# Bots (caminho B)

Opcional. O `.method/scripts/ask-bot.sh` comenta a pergunta na issue e chama o webhook do bot. A resposta é reconhecida pela marca `<!-- bot:<slug> reply-to:<id> -->`, não pelo autor: funciona mesmo quando todos usam a mesma conta do GitHub.

Os bots abaixo são exemplos. Troque as linhas pelos bots do seu time, com os mesmos slugs em `.github/bots.tsv`; as labels `ask:<slug>` saem da linha-modelo de `.github/labels.tsv`, uma por bot.

| Slug | Nome | Papel | Quando perguntar | Nunca pode |
|---|---|---|---|---|
| `bot-a` | Bot A | coordena o time e o processo | dúvida sobre o processo, prioridade, qual bot consultar | mexer em código, aprovar spec, repassar ok do dono |
| `bot-b` | Bot B | especialista de uma área (exemplo: texto do produto) | texto e tom de página, posicionamento | publicar algo, decidir pelo dono |

Bot sem webhook configurado: o `notify-bot.sh` põe `ask:<slug>` na issue e o agente segue.

## Segredos dos webhooks

O `.method/scripts/lib/secret.sh` procura a URL e o segredo de cada bot nesta ordem (sem nenhum provedor, o `ask-bot.sh` para antes de postar):

1. variáveis de ambiente `BOT_WEBHOOK_<SLUG>_URL` e `BOT_WEBHOOK_<SLUG>_SECRET` (CI);
2. opcional: conta de serviço do gerenciador de senhas;
3. padrão: `$DUMONTECH_HOME/shared/bots.env` (bots) e o `.env` do repo.

**Arquivos (`DUMONTECH_HOME`, padrão `~/.dumontech`; pastas 700, arquivos 600):** `shared/bots.env` (`BOT_WEBHOOK_<SLUG>_URL`, `_SECRET`, `GH_APP_<SLUG>_TOKEN`, para todos os repos) e `projetos/<repo>/.env`. O `.env` do repo é o primeiro que existe de `PROCESS_ENV_FILE`, `projetos/<repo>/.env`, `~/.<repo>/.env`, `~/.config/<repo>/.env` (legado). O `init-env.sh` cria chaves vazias e não move `.env` antigo. O repo só lê os bots do seu `bots.tsv`. Com o `shared/bots.env` presente, bot declarado ausente é erro (slug, caminho, chaves, chmod 600), sem cair no `.env` antigo; sem ele, vale o `.env` do repo. O método nunca cria nem edita o `shared/bots.env`. Ver `.env.example`.

**Gerenciador de senhas (opcional):** o código aceita uma conta de serviço lida pelo CLI `op`. Crie uma conta só de leitura no cofre dos webhooks, um item por bot, e ponha `op://<cofre>/<item>` em `.github/bots.tsv`. O token da conta fica no cofre do sistema; o agente só chama o `op` pelos scripts.

## Identidade

Todo comentário de agente ou bot abre com `**De:** bot <nome> · **Para:** <papel> · **Pedido:** <ask_id> · **Responde a:** <link>`; sem o cabeçalho, é do dono. Pedido a bot só pelo `ask-bot.sh`. Toda resposta começa com `**<Nome> (bot do time)**`.

O dono cria a GitHub App do bot (`<slug>[bot]`, issues e pull requests em escrita). O token de instalação é `GH_APP_<SLUG>_TOKEN` no ambiente ou nos arquivos acima. Com ele, o bot comenta como a App. Sem ele, o comentário do método usa o `gh` do dono. `ROLE_APP_REQUIRE=1` recusa até a App existir.

**Pastas antigas do `.env`:** o método nunca apaga nem move nada da sua home; ele avisa no stderr (uma vez por execução, sem valor de segredo, sem mudar o código de saída; o `init-env.sh` imprime o mesmo) e mostra o comando pronto, que você roda se quiser. Sem aviso com `PROCESS_ENV_FILE`.
- Caminho novo e pasta antiga juntos: "a pasta antiga não é mais lida", com `rm -r <pasta>` (`~/.<repo>` ou `~/.config/<repo>`, a segunda é a legada).
- Só a pasta antiga: o `.env` dela ainda é lido e o aviso traz o comando que cria a pasta nova (700), move o `.env` (600) e remove a pasta antiga: `mkdir -p <DUMONTECH_HOME>/projetos/<repo> && chmod 700 <DUMONTECH_HOME> <DUMONTECH_HOME>/projetos <DUMONTECH_HOME>/projetos/<repo> && mv <pasta-antiga>/.env <DUMONTECH_HOME>/projetos/<repo>/.env && chmod 600 <DUMONTECH_HOME>/projetos/<repo>/.env && rm -r <pasta-antiga>`.
