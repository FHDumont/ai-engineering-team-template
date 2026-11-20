# Estado atual

## Onde estamos

Repositório criado a partir do template do método (`docs/process-design.md`). Nenhuma fase rodou ainda.

- **Projeto:** nome, objetivo e stack ainda não registrados; a skill `setup` registra aqui.
- **Método:** scripts, hooks, skills, agentes e CI vêm do template, sem alteração. As decisões herdadas estão em `docs/adr/INDEX.md`.
- **Modelo e esforço:** os pares de `scripts/lib/weights.tsv` são o padrão do template; ajuste o arquivo ao plano da conta.
- **App:** `app/` é só um marcador para o workflow de exemplo; troque pelo código do projeto.
- **Deploy:** `deploy-example.yml` é um exemplo que builda `app/` e guarda o artefato, sem publicar nada. Roda só por `workflow_dispatch`, disparado pelo `scripts/deploy.sh` na sessão principal.
- **Fim do grupo:** passo único da sessão principal (skill `integrate`): `gen-docs.sh`, `deploy.sh`, arquivamento das sessões filhas, `end-check.sh`.
- **Runner:** hospedado pelo GitHub (`ubuntu-latest`); a variável `CI_RUNS_ON` não está definida.
- **Bots (caminho B):** nenhum webhook configurado; `docs/BOTS.md` e `scripts/lib/bots.tsv` trazem só exemplos.
- **Projects:** sem quadro.

## Pendente

- Rodar a skill `setup` ("configurar o repo"): labels, proteção da `main`, configurações do repo e as ofertas opcionais.
- Trocar `app/` e o passo de deploy do `deploy-example.yml` pelos do projeto, e ajustar `.github/sensitive-paths` e as labels `area:*`.
- Pacote do método (`process-design` §11).

## Pontos de atenção

- Sem a proteção da `main` (`CI` + `review/independent`) não há merge: o `close-phase.sh --merge` recusa. Repo privado em plano sem proteção de branch: o `setup-repo.sh` sai 6.
- `close-phase.sh --abort` sai 10 com perda; `--discard` confirma.
- `close-phase.sh --check`: conflito real no cherry-pick sai 4; `mergeable` UNKNOWN após 5 leituras sai 8; sem check no HEAD em ~180 s sai 7.
