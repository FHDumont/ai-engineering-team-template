# AGENTS.md

Método: `docs/process-design.md`. Estado em `docs/STATE.md`; decisões em `docs/adr/INDEX.md`; termos em `CONTEXT.md`; bots em `docs/BOTS.md`.

## Rodar e testar

- `scripts/validate.sh`: lint (shellcheck) e todos os testes. `scripts/check-docs.sh`: limites dos docs e desenho contra o repo.
- Todo script tem `--help`. Histórico: `scripts/search-history.sh "termo"`.

## Idioma

Código, comentários, identificadores, nomes de arquivos, labels, workflows/jobs/checks, `--help`, saída dos scripts e commits (Conventional Commits) em inglês. Docs, issues, PRs e seus comentários em português.

## Regras

1. O dono nunca roda script nem mexe em configuração. sem `scripts/setup-repo.sh --check` limpo nenhuma fase abre; em desvio, rode `scripts/setup-repo.sh`.
2. Toda decisão do dono é um quadro de escolha (`AskUserQuestion`) que começa por `Fase #n — título`, uma pergunta por decisão; nunca pedir número. Só a principal pergunta; a filha manda a dúvida e pede só o ok da ação sensível que executa (merge `needs-owner-ok`, `--abort --discard`), que não atravessa sessões. "Fechar fase" vale em qualquer sessão; a da fase fecha.
3. Toda parada e mensagem final de turno termina com o bloco de `scripts/status.sh` (Estado, Você precisa, Próximo passo); cole a saída como está, fora de bloco de código (exceto o batimento sem mudança). Estados: `trabalhando`, `esperando você`, `pronto` (`end-check.sh` limpo).
4. Paralelo é o preferido; skills carregam só na etapa (`triage`, `plan`, `execute`, `close-phase`, `integrate`, `ask-bot`, `setup`).
5. Arquivos guardam só o estado atual, nada que o git repete.
6. Nenhuma assinatura de IA em commits, PRs, issues ou comentários (coautoria, "Generated with", emoji). Comentário de agente ou bot leva o cabeçalho de autoria (`scripts/lib/author.sh`); sem ele é do dono.
7. Use o GitHub direto (`gh`); scripts só para fluxos repetidos.
8. Todo agente é aberto com `model` e `effort` explícitos.
9. "executar #n" passa pelo `plan`; a fase só abre por `scripts/phase-start.sh` (exige spec), sempre em sessão filha.
10. Do `gh auth`, só `status`; login e escopo: `process-design` §8.3.

## Execução

- Critério de sucesso verificável antes de codar.
- Verificar antes de declarar feito: saída 0 não prova "criado", "vinculado", "autorizado" nem "acabou"; leia o fato de volta (`process-design` §2.1); falhou, Estado `trabalhando` ou `esperando você`.
- Bug começa com um teste que falha no código antigo.
- Sem refatoração de carona nem over-engineering; preserve comentários.
- Um commit por etapa. Achados: `scripts/open-issue.sh --type finding` com `size:*`.

## Quando perguntar

- Sempre: ação destrutiva ou irreversível, gasto, dependência nova, arquitetura ou schema, segredos, cobrança, autenticação, migração, credenciais, infraestrutura de produção, lockfiles.
- Nunca: passo rotineiro e reversível de spec aprovada, setup, labels, issue de achado, branch e PR.
- Dúvida em passo reversível: siga e liste em "Decisões tomadas sem perguntar" no PR; nunca suponha em silêncio.

## Git

- Nunca commitar na `main`; cada fase tem branch e worktree (`scripts/phase-start.sh`).
- Nunca `git add -A`, `git add .`, `git commit -a`; adicione arquivos pelo nome.
- Merge só pelo portão (`CI` + `review/independent`) com `scripts/close-phase.sh --merge` (`--rebase`), nunca `--squash` ou `--admin`.
- Nunca `git push --force` nem `git reset --hard`.
- Fim do grupo: skill `integrate`, pela principal.
