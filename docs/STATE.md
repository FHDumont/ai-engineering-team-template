# Estado atual

## Onde estamos

Repositório criado a partir do template do método (`docs/process-design.md`). Nenhuma fase rodou ainda.

- **Projeto:** nome, objetivo e stack ainda não registrados; a skill `setup` registra aqui.
- **Método:** scripts, hooks, skills, agentes e CI. Decisões em `docs/adr/INDEX.md`.
- **Modelo e esforço:** os pares de `scripts/lib/weights.tsv` são o padrão do template; ajuste o arquivo ao plano da conta.
- **App:** `app/` é só um marcador para o workflow de exemplo; troque pelo código do projeto.
- **Deploy:** `deploy-example.yml` é um exemplo que builda `app/` e guarda o artefato, sem publicar nada. Roda só por `workflow_dispatch`, disparado pelo `scripts/deploy.sh` na sessão principal.
- **Fim do grupo:** passo único da sessão principal (skill `integrate`): `gen-docs.sh`, `deploy.sh`, arquivamento das sessões filhas, `end-check.sh`.
- **CI:** um run por rodada; verificadores da base do PR. Docs gerados são inertes; push na `main` só com eles não abre run. Reaproveitamento usa o resultado mais novo. Árvore já testada grava `no-new-fact:` e não sobe o agregador. `ci.yml` e `close-phase.sh` são caminho sensível.
- **Runner:** hospedado pelo GitHub (`ubuntu-latest`); a variável `CI_RUNS_ON` não está definida.
- **Bots (caminho B):** nenhum webhook configurado; `docs/BOTS.md` e `.github/bots.tsv` trazem só exemplos.
- **Projects:** sem quadro.
- **Progresso:** scripts longos gravam o andamento em `~/.cache/ai-method/progress/`; `scripts/progress.sh` mostra ao dono.

## Pendente

- Rodar a skill `setup` ("configurar o repo"): labels, proteção da `main`, configurações do repo e as ofertas opcionais.
- Trocar `app/` e o passo de deploy do `deploy-example.yml` pelos do projeto, e ajustar `.github/sensitive-paths` e as labels `area:*`.
- Pacote do método (`process-design` §11).

## Pontos de atenção

- Sem a proteção da `main` o merge só passa no modo sem proteção (`PROCESS_BRANCH_MODE`, repo privado em plano gratuito): `close-phase.sh --merge` lê `CI` e `review/independent` pela API (saída 11 se não verdes) e o hook `pre-push` recusa push na `main`; o servidor não impede merge à mão.
- `close-phase.sh --abort` sai 10 com perda; `--discard` confirma.
- `close-phase.sh --check`: conflito real no cherry-pick sai 4; `mergeable` UNKNOWN após 5 leituras sai 8; sem check no HEAD em ~180 s sai 7.
- **Meta de tempo:** padrão do método (fase 45 min, `validate.sh` 240 s); o projeto sobrepõe em `.github/time-targets.tsv` (a atualização do template não sobrescreve). `machine-slots.sh --report` imprime `over-target:`; a skill `integrate` abre quadro ao dono no fim do grupo.
- **Headless:** desligado por padrão. Recusa por falta de fala do dono vira cartão ou espera, não `start-headless.sh`. Fase sem `phase_session` aparece como "aberta, sem sessão".
- **Recado à filha:** comentário na issue com `Para: fase #n` (app e headless, além da mensagem); a filha o relê antes de cada etapa, da parada de lab-test e do `--merge`, que sai 12 até ela responder com `De: fase #n`. O ok do dono no merge vale para um SHA (`--owner-ok <sha>`). Commit de etapa sem `phase_session` é recusado.
- **Pré-revisão:** antes do `--prepare`, `close-reviewer` só com issue e diff; `close-phase.sh --pre-review --verdict clean|findings` grava `pre_review` no trace; o `--prepare` só avisa sem ela no HEAD.
