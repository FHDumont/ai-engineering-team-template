# Spec: aviso das pastas antigas do .env (issue #332)

Grupo: metodo. Uma fase solo, depois das quatro primeiras do grupo (todas já na `main`). Termina em `end:auto-close`.

Decisão do dono (27/11/2026, em duas mensagens na sessão principal): as pastas antigas não podem virar lixo na máquina, mas o método não apaga nem move nada sozinho; ele avisa o usuário e dá o comando pronto. "Já executa a issue" vale como ok desta spec.

Suposições (sem pergunta):

- O aviso vai para o stderr, em inglês como toda saída de script, e não muda o código de saída.
- O comando de remoção mostrado é `rm -r` da pasta antiga inteira (`~/.<slug>` ou `~/.config/<slug>`), com o caminho absoluto; o de migração cria a pasta nova com 700, move o `.env` e remove a pasta antiga.
- Com `PROCESS_ENV_FILE` definido não há aviso: o caminho é escolha explícita.

## Fase #332 — aviso das pastas antigas do .env com o comando para migrar ou remover

Fecha: #332.

Objetivo: quem ainda tem `~/.<slug>/` ou `~/.config/<slug>/` fica sabendo, a cada uso do método, se a pasta ainda é lida ou se já é sobra, e recebe o comando exato para resolver.

Arquivos: `.method/scripts/lib/secret.sh`, `.method/scripts/init-env.sh`, `.method/scripts/tests/test_env_file.sh`, `docs/BOTS.md`. Área sensível: leitura de segredos, sem caminho `owner-ok`. Nenhum valor de segredo em aviso, log ou teste; nenhum script apaga ou move arquivo da home.

Pronto quando:

- Testes que falham no código atual, com HOME temporário, para os três casos: só o caminho novo (sem aviso); novo e antigo juntos (aviso de sobra com o comando de remoção); só o antigo (aviso de caminho antigo em uso com o comando de migração).
- O aviso de sobra diz que a pasta antiga não é mais lida, cita o caminho dela e o comando exato para removê-la.
- O aviso de caminho antigo em uso vale para `~/.<slug>/.env` e para o legado `~/.config/<slug>/.env`, e o comando cria a pasta nova com 700, mantém 600 no arquivo e remove a pasta antiga.
- O aviso sai uma vez por execução e não muda o código de saída.
- `init-env.sh` imprime o mesmo aviso e o mesmo comando.
- Depois de cada chamada nos testes, as pastas antigas continuam no lugar, com o mesmo conteúdo.
- `docs/BOTS.md` explica os dois avisos e os comandos.
- Prova na parada: `validate.sh`, `check-docs.sh` e a CI do PR verdes.

1. Testes que falham e os dois avisos em `secret.sh` e `init-env.sh`. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (caminho de segredos, comando mostrado ao dono)
2. `docs/BOTS.md`. modelo: sonnet · esforço: low · motivo: peso light de .method/scripts/lib/weights.tsv (documentação)
