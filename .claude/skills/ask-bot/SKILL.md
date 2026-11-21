---
name: ask-bot
description: Pergunta a um bot do time (caminho B) numa issue e espera a resposta marcada. Use quando a spec ou a issue pede a opinião de um bot (seção Bots). Frases: "perguntar ao bot", "perguntar a um bot".
---

# Perguntar a um bot

1. Veja em `docs/BOTS.md` qual bot responde o quê e o que ele nunca pode fazer.
2. `scripts/ask-bot.sh <bot> <issue> "pergunta em português"` (rode em segundo plano; espera até 15 min).
2a. Informação nova para o bot durante a espera, ou complemento à pergunta já feita: `scripts/ask-bot.sh --append <id> "texto" --issue <n>`. Nunca `gh issue comment` solto para o bot: ele não é avisado, e o hook barra. Todo comentário seu abre com o cabeçalho de autoria (`scripts/lib/author.sh`).
3. Saída 4: o webhook falhou três vezes; a issue ficou com `ask:<bot>`. Avise o dono do repo no bloco de status e siga com o que não depende da resposta.
4. Saída 3: sem resposta no prazo; retome depois com `scripts/wait-reply.sh <issue> <id>`.
5. Só vale resposta com a marca `<!-- bot:<slug> reply-to:<id> -->`, nunca por autor.
6. Passou de ~10 comentários: escreva o resumo do que foi acordado e rode `scripts/summarize-thread.sh <issue> --summary-file <arquivo>` (arquivo de `mktemp` ou `.worktrees/issue-<n>/.process/`, nunca caminho fixo em `/tmp`).
