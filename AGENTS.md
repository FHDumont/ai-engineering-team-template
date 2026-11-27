# AGENTS.md

Método: `docs/process-design.md`. Estado em `docs/STATE.md`; decisões em `docs/adr/INDEX.md`; termos em `CONTEXT.md`; bots em `docs/BOTS.md`. Regras do projeto: `docs/repo-notes.md`.

## Rodar e testar

- `.method/scripts/validate.sh`: lint (shellcheck) e todos os testes. `.method/scripts/check-docs.sh`: limites dos docs e desenho contra o repo.
- Todo script tem `--help`. Histórico: `.method/scripts/search-history.sh "termo"`.

## Idioma

Código novo e o do método, comentários, identificadores, nomes de arquivos, labels, workflows/jobs/checks, `--help`, saída dos scripts e commits (Conventional Commits) em inglês. Docs, issues, PRs e seus comentários em português.

## Regras

1. O dono nunca roda script do método nem mexe na configuração do método. Setup pré-aprovado e obrigatório: sem `.method/scripts/setup-repo.sh --check` limpo nenhuma fase abre; em desvio, rode `.method/scripts/setup-repo.sh`.
2. Toda decisão do dono é um quadro de escolha (`AskUserQuestion`) que começa por `Fase #n — título`. Só a principal pergunta; a filha pede só o ok da ação sensível (merge `needs-owner-ok`, `--abort --discard`), que não atravessa sessões. O ok da spec aprovada que declara a área sensível vale como ok do merge dessa área (ADR-006). "Fechar fase" vale em qualquer sessão.
3. Toda parada e mensagem final de turno termina com o bloco de `.method/scripts/status.sh` (Estado, Você precisa, Próximo passo); cole a saída como está, fora de bloco de código. Estados: `trabalhando`, `esperando você`, `pronto` (`end-check.sh` limpo).
4. Paralelo é o preferido; skills carregam só na etapa (`triage`, `plan`, `execute`, `close-phase`, `integrate`, `ask-bot`, `setup`).
5. Arquivos guardam só o estado atual, nada que o git repete.
6. Nenhuma assinatura de IA em commits, PRs, issues ou comentários (coautoria, "Generated with", emoji). Comentário de agente ou bot leva o cabeçalho de autoria (`.method/scripts/lib/author.sh`); sem ele é do dono.
7. Use o GitHub direto (`gh`); scripts só para fluxos repetidos.
8. Todo agente é aberto com `model` e `effort` explícitos.
9. "executar #n" passa pelo `plan`; a fase só abre por `.method/scripts/phase-start.sh` (exige spec), sempre em sessão filha.
10. Do `gh auth`, só `status`; login e escopo: `process-design` §8.3.

## Execução

- Critério de sucesso verificável antes de codar.
- Verificar antes de declarar feito: leia o fato de volta (`process-design` §2.1).
- Bug começa com um teste que falha no código antigo.
- Sem refatoração de carona.
- Um commit por etapa. Achados: `.method/scripts/open-issue.sh --type finding` com `size:*`.

## Quando perguntar

- Sempre: ação destrutiva ou irreversível, gasto, dependência nova, arquitetura ou schema, segredos, cobrança, autenticação, migração, credenciais, infraestrutura de produção.
- Nunca: passo rotineiro e reversível de spec aprovada, setup, labels, issue de achado, branch e PR.
- Dúvida em passo reversível: siga e liste em "Decisões tomadas sem perguntar" no PR; nunca suponha em silêncio.

## Git

- Nunca commitar na `main`; cada fase tem branch e worktree (`.method/scripts/phase-start.sh`).
- Nunca `git add -A`, `git add .`, `git commit -a`; adicione arquivos pelo nome.
- Merge só pelo portão (`CI` + `review/independent`) com `.method/scripts/close-phase.sh --merge`, por rebase (o script faz), nunca `--squash` ou `--admin`.
- Nunca `git push --force` nem `git reset --hard`.
- Fim do grupo: skill `integrate`, pela principal.
