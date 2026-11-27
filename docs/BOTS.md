# Bots (caminho B)

Opcional. O `.method/scripts/ask-bot.sh` comenta a pergunta na issue e chama o webhook do bot. A resposta é reconhecida pela marca `<!-- bot:<slug> reply-to:<id> -->`, não pelo autor: funciona mesmo quando todos usam a mesma conta do GitHub.

Os bots abaixo são exemplos: troque pelos do seu time, com os mesmos slugs em `.github/bots.tsv` e uma label `ask:<slug>` por bot (linha-modelo de `.github/labels.tsv`).

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

**Arquivos (`DUMONTECH_HOME`, padrão `~/.dumontech`; pastas 700, arquivos 600):** `shared/bots.env` (`BOT_WEBHOOK_<SLUG>_URL`, `_SECRET`, `GH_APP_<SLUG>_TOKEN`, para todos os repos) e `projetos/<repo>/.env`. O `.env` do repo é o primeiro que existe de `PROCESS_ENV_FILE`, `projetos/<repo>/.env`, `~/.<repo>/.env`, `~/.config/<repo>/.env` (legado). O `init-env.sh` cria chaves vazias. O repo só lê os bots do seu `bots.tsv`. Com o `shared/bots.env` presente, bot declarado ausente é erro, sem cair no `.env` do repo; sem ele, vale o `.env` do repo. O método nunca cria nem edita o `shared/bots.env`. Ver `.env.example`.

**Pastas antigas do `.env`:** o método não apaga nem move nada; avisa no stderr, uma vez por execução (o `init-env.sh` também), e mostra o comando pronto. Pasta antiga junto do caminho novo: não é mais lida, o aviso traz `rm -r <pasta>`. Só a pasta antiga: ainda é lida, o aviso traz o comando que cria a pasta nova (700), move o `.env` (600) e remove a antiga. Com `PROCESS_ENV_FILE` não há aviso.

**Gerenciador de senhas (opcional):** conta de serviço lida pelo CLI `op`: uma conta só de leitura, um item por bot, `op://<cofre>/<item>` em `.github/bots.tsv`. O token fica no cofre do sistema.

## Identidade

Todo comentário de agente ou bot abre com `**De:** bot <nome> · **Para:** <papel> · **Pedido:** <ask_id> · **Responde a:** <link>`; sem o cabeçalho, é do dono. Pedido a bot só pelo `ask-bot.sh`. Toda resposta começa com `**<Nome> (bot do time)**`.

O dono cria a GitHub App do bot (`<slug>[bot]`, issues e pull requests em escrita). O token de instalação é `GH_APP_<SLUG>_TOKEN` no ambiente ou nos arquivos acima. Com ele, o bot comenta como a App. Sem ele, o comentário do método usa o `gh` do dono. `ROLE_APP_REQUIRE=1` recusa até a App existir.
