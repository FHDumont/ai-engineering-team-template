# Estado atual

## Onde estamos

Repositório criado a partir do template do método (`docs/process-design.md`). Nenhuma fase rodou ainda.

- **Projeto:** nome, objetivo e stack ainda não registrados; a skill `setup` registra aqui.
- **Método:** scripts, hooks, skills, agentes e CI vêm do template, sem alteração. As decisões herdadas estão em `docs/adr/INDEX.md`.
- **Modelo e esforço:** os pares de `scripts/lib/weights.tsv` são o padrão do template; ajuste o arquivo ao plano da conta.
- **App:** `app/` é só um marcador para o workflow de exemplo; troque pelo código do projeto.
- **Deploy:** `deploy-example.yml` é um exemplo que builda `app/` e guarda o artefato, sem publicar nada. Roda só por `workflow_dispatch`, disparado pelo `scripts/deploy.sh` na sessão principal.
- **Fim do grupo:** passo único da sessão principal (skill `integrate`): `gen-docs.sh`, `deploy.sh`, arquivamento das sessões filhas, `end-check.sh`.
- **CI:** um run por rodada; verificadores lidos da base do PR; o job `tests` roda em todo PR. `ci.yml`, verificadores, `deploy-*.yml` e `close-phase.sh` são caminho sensível.
- **Runner:** hospedado pelo GitHub (`ubuntu-latest`); a variável `CI_RUNS_ON` não está definida.
- **Bots (caminho B):** nenhum webhook configurado; `docs/BOTS.md` e `.github/bots.tsv` trazem só exemplos.
- **Projects:** sem quadro.
- **Progresso:** `validate.sh`, `phase-start.sh` e `new-phase.sh` gravam o andamento em `~/.cache/ai-method/progress/` (formato na `process-design` §6.4); `scripts/progress.sh` mostra ao dono, `status.sh` cita o passo. O `close-phase.sh` ainda não grava (#39).

## Pendente

- Rodar a skill `setup` ("configurar o repo"): labels, proteção da `main`, configurações do repo e as ofertas opcionais.
- Trocar `app/` e o passo de deploy do `deploy-example.yml` pelos do projeto, e ajustar `.github/sensitive-paths` e as labels `area:*`.
- Pacote do método (`process-design` §11).

## Pontos de atenção

- Sem a proteção da `main` o merge só passa no modo sem proteção (`PROCESS_BRANCH_MODE`, repo privado em plano gratuito): `close-phase.sh --merge` lê `CI` e `review/independent` pela API (saída 11 se não verdes) e o hook `pre-push` recusa push na `main`; o servidor não impede merge à mão.
- `close-phase.sh --abort` sai 10 com perda; `--discard` confirma.
- `close-phase.sh --check`: conflito real no cherry-pick sai 4; `mergeable` UNKNOWN após 5 leituras sai 8; sem check no HEAD em ~180 s sai 7.
