# Spec: estabilização do método (issues #298 a #312)

Grupo: estabilizacao. Seis fases em quatro ondas, sem funcionalidade nova fora do que as issues pedem. A ordem existe porque fases de ondas diferentes tocam os mesmos arquivos:

| Onda | Fases | Modo |
|---|---|---|
| 1 | #310, #302, #307 | paralelo (sem arquivo em comum) |
| 2 | #308 | solo (usa o `close-phase.sh` e as skills que a #307 mudou) |
| 3 | #311 | solo (usa o teste da #310 e os docs que a #308 mudou) |
| 4 | #312 | solo, por último (varre todos os testes, inclusive os novos) |

Cada onda abre por um `phase-start.sh` próprio e fecha com a skill `integrate`.

Decisões do dono (grilling de 26/11/2026):

- Versões: tag automática no fim de cada grupo, só com CI e teste de atualização verdes; o adotante atualiza para a última tag.
- Ok do merge: aprovar a spec que declara a área sensível vale como ok do merge da fase; sem quadro novo no fim.
- Abertura de fase: sem batimento; quando o app recusa o `start_session`, a filha abre headless e as perguntas dela chegam ao dono pela sessão principal.

Suposições (sem pergunta): nome da tag `vAAAA.MM.DD-N`; #298 e #300 são a mesma falha e fecham juntas; as issues `type:feature` de #302 a #309 são defeitos e ficam com o rótulo que têm.

## Fase #310 — o caminho de atualização é testado aqui, a partir de origens antigas reais

Fecha: #298, #299, #300, #301 e #310.

Objetivo: a atualização de um repo adotante a partir de uma origem anterior à pasta `.method/` funciona seguindo o aviso, e um teste do template prova isso com commits reais.

Arquivos: `.method/scripts/fetch-template.sh`, `.method/scripts/method-diff.sh`, `.github/update-notice.md`, `.method/scripts/tests/test_method_folder.sh`, um teste novo de atualização em `.method/scripts/tests/` e a lista de origens que ele lê. Área sensível: nenhuma. O `ci.yml` já busca o histórico inteiro (`fetch-depth: 0`); esta fase não o toca. Se o teste novo passar da meta de tempo do `validate.sh`, ele entra só no `--full` e a fase diz isso no PR.

Pronto quando:

- Teste que falha no código atual: para cada origem `c1b76da`, `e3c157e` e `4791675`, monta um repo adotante de mentira naquele commit, com um `scripts/<script-da-aplicação>.sh` rastreado, segue o comando que o `update-notice.md` manda até a ponta, e depois `validate.sh` e `check-docs.sh` passam nesse repo.
- O `fetch-template.sh` antigo não pode ser corrigido (ele mora no repo adotante): o aviso dá, para origem anterior à `.method/`, o comando que roda o `fetch-template.sh` do próprio destino, com o SHA completo (#298, #300).
- O `fetch-template.sh` atual resolve SHA curto (`git fetch` e `rev-parse`) e acha o `method-diff.sh` do destino nos dois lugares.
- O `method-diff.sh --notice` imprime o caminho do `check-docs.sh` que existe na origem (#301).
- O `test_method_folder.sh` recusa só o link antigo e a cópia de arquivo do método em `scripts/`, não um script da aplicação (#299).
- A lista de origens fica num arquivo só.
- Prova na parada: `validate.sh --full`, `check-docs.sh` e a CI do PR verdes.

1. Teste de atualização que falha no código atual, com a lista de origens. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (bug com causa conhecida)
2. Aviso, SHA curto e caminho do `method-diff.sh` e do `check-docs.sh`. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (bug com causa conhecida)
3. `test_method_folder.sh` aceita `scripts/` da aplicação. modelo: sonnet · esforço: low · motivo: peso light de .method/scripts/lib/weights.tsv (ajuste pequeno de teste)

## Fase #302 — três correções pequenas de CI e configuração

Fecha: #302, #303 e #304.

Objetivo: o `rerun-ci.sh` não conta pedido recusado, o modelo de caminhos sensíveis pega infraestrutura em subpasta e o gate do deploy de exemplo lê os PRs do commit.

Arquivos: `.method/scripts/rerun-ci.sh`, `.method/scripts/tests/test_rerun_ci.sh`, `.github/sensitive-paths`, o teste do `sensitive_paths`, `.github/workflows/deploy-example.yml`. Área sensível: `.github/sensitive-paths` e `deploy-example.yml` (arquivos do portão); o merge segue o que o `close-phase.sh` pedir. A fase não toca `.method/scripts/lib/sensitive_paths.py`.

Pronto quando:

- Teste que falha no código atual: com o `gh` falso devolvendo 500, o `rerun-ci.sh` não conta o rerun e mostra o erro na saída (#302).
- `.github/sensitive-paths` usa `**/compose*.yml` e `**/Dockerfile`, e o teste cobre um `app/compose.yml` (#303).
- O job do gate do `deploy-example.yml` tem `pull-requests: read`, e só ele (#304).
- Prova na parada: `validate.sh`, `check-docs.sh` e a CI do PR verdes.

1. Teste que falha e correção do `rerun-ci.sh`. modelo: sonnet · esforço: low · motivo: peso light de .method/scripts/lib/weights.tsv (achado pequeno)
2. Globs de subpasta e teste. modelo: sonnet · esforço: low · motivo: peso light de .method/scripts/lib/weights.tsv (achado pequeno)
3. Permissão no gate do deploy de exemplo. modelo: sonnet · esforço: low · motivo: peso light de .method/scripts/lib/weights.tsv (achado pequeno)

## Fase #307 — close-phase.sh: corpo do PR dentro do limite e ok do merge junto com a spec

Fecha: #307. Refs #308 (a parte do merge; a #308 fecha na fase dela).

Objetivo: o `--prepare` abre o PR mesmo com muitas specs citando a issue, e a filha deixa de abrir quadro no merge quando o dono já aprovou a spec que declara a área sensível.

Arquivos: `.method/scripts/close-phase.sh`, `.method/scripts/tests/test_close_phase_specs.sh`, `.method/scripts/tests/test_close_phase_classes.sh` (ou um teste novo), `.claude/skills/close-phase/SKILL.md`, `docs/process-design.md` (§2 item do quadro da filha e §10.3), `AGENTS.md` (regra 2), `docs/adr/ADR-006-*.md` e `docs/adr/INDEX.md`. Área sensível: `close-phase.sh` é arquivo do portão (classe `gate`): o merge pede o segundo parecer do `close-reviewer` ("enfraquece o portão?").

Pronto quando:

- Teste que falha no código atual: com specs falsas que somam mais de 60.000 caracteres, o corpo fica abaixo de 65.536 e cita cada spec (link para o blob do commit no lugar do texto).
- O `--prepare` mostra o erro do `gh pr create` com a causa.
- O ok da spec fica registrado no trace com a área sensível declarada (label `approved` na issue da fase). Com esse registro, `close-phase.sh --merge` aceita o PR com `needs-owner-ok` sem quadro, para o HEAD da fase.
- O ok da spec não cobre caminho sensível que a spec não declarou: nesse caso o `--merge` sai 5 e o quadro continua. Teste dos dois casos.
- `--abort --discard` continua pedindo o ok.
- ADR-006 registra a troca de "o ok do dono não atravessa sessões" pela regra nova; `AGENTS.md` e `process-design` dizem o mesmo que o código.
- Prova na parada: `validate.sh`, `check-docs.sh` e a CI do PR verdes.

1. Teste que falha e limite do corpo do PR. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (bug com causa conhecida)
2. Testes do ok junto com a spec (declarado e não declarado). modelo: sonnet · esforço: medium · motivo: peso strong de .method/scripts/lib/weights.tsv (regra do portão)
3. Registro do ok da spec e leitura dele no `--merge`. modelo: sonnet · esforço: medium · motivo: peso strong de .method/scripts/lib/weights.tsv (regra do portão)
4. ADR-006, `AGENTS.md`, `process-design` e skill `close-phase`. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (docs do desenho)

## Fase #308 — fase abre sem pedir nada ao dono: sem batimento, headless na recusa

Fecha: #306, #308 e #309.

Objetivo: depois do ok da spec, nenhuma fase fica parada esperando o dono clicar num cartão ou digitar "abrir fase", também pelo Remote Control; e a filha não deixa laço de espera vivo depois do fecho.

Arquivos: `.method/scripts/phase-start.sh` (texto dos passos da gerenciadora), `.method/scripts/start-headless.sh`, `.method/scripts/tests/test_phase_start_*.sh`, `.method/scripts/tests/test_start_headless.sh`, `.claude/skills/plan/SKILL.md`, `.claude/skills/execute/SKILL.md`, `.claude/skills/close-phase/SKILL.md`, `.claude/skills/integrate/SKILL.md`, `docs/process-design.md` (§2, §4.3), `docs/STATE.md`, `docs/adr/ADR-007-*.md` e `docs/adr/INDEX.md`. Área sensível: `start-headless.sh` (classe `owner-ok`); esta spec declara, então o ok dela vale para o merge se a fase #307 já tiver entrado.

Pronto quando:

- Primeiro a prova, antes de mudar o fluxo: a sessão da fase abre um `claude -p` headless de teste e uma espera em segundo plano presa ao pid dele, e mostra que é acordada quando ele termina, sem job agendado. Se a prova falhar, a fase para em `esperando você` com o que viu e não muda nada.
- O batimento sai: `phase-start.sh`, as skills `plan` e `integrate` e o `process-design` não mandam mais criar tarefa recorrente. A gerenciadora acorda pelo fim de turno da filha do app e pela espera em segundo plano da filha headless.
- App recusou o `start_session` (turno sem fala do dono, Remote Control): a gerenciadora roda `start-headless.sh` na hora, sem cartão e sem parada. Headless na recusa passa a ser o padrão; `.github/headless` com `off` desliga. Cartão só com saída 3 ou 4 do `start-headless.sh`.
- Pergunta da filha headless: comentário na issue; a gerenciadora repassa ao dono num quadro `Fase #n — título` e devolve a resposta. O `--need` nunca manda o dono clicar em cartão quando ele está no Remote Control.
- Espera do `validate.sh` (#309): as skills `execute` e `close-phase` mandam esperar pelo aviso de término da tarefa ou por pid ou arquivo da própria rodada, nunca `pgrep -f validate.sh`; antes de dizer "tarefas em segundo plano: nenhuma", a filha lista e para as próprias tarefas de shell; a `integrate` cita o caso no arquivamento.
- Teste que falha no código atual: o texto impresso pelo `phase-start.sh` não cita batimento nem cartão por recusa, e o `start-headless.sh` roda sem `.github/headless`.
- ADR-007 registra a decisão; `docs/STATE.md` (Headless, Fim do grupo) diz o estado novo.
- Prova na parada (lab-test): a prova do primeiro item, `validate.sh`, `check-docs.sh` e a CI do PR verdes.
- Prova do fecho: o dono diz "fechar fase" depois de ler a prova da parada.
- Prova do pós-merge: a onda 3 (#311) abre num turno que não começou por fala do dono, e a filha sobe headless sem pedir nada. A issue #308 fica aberta até a prova. O caso do Remote Control só fica provado quando o dono estiver nele numa abertura; até lá, não verificado.

1. Prova de que a espera em segundo plano acorda a sessão. modelo: sonnet · esforço: medium · motivo: peso strong de .method/scripts/lib/weights.tsv (arquitetura do fluxo de sessões)
2. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso strong de .method/scripts/lib/weights.tsv (arquitetura do fluxo de sessões)
3. `phase-start.sh` e `start-headless.sh`: sem batimento, headless na recusa. modelo: sonnet · esforço: medium · motivo: peso strong de .method/scripts/lib/weights.tsv (arquitetura do fluxo de sessões)
4. Skills `plan`, `execute`, `close-phase` e `integrate`. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (texto das skills)
5. ADR-007, `process-design` e `STATE.md`. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (docs do desenho)

## Fase #311 — versões marcadas do método

Fecha: #311.

Objetivo: o adotante atualiza para a última tag do método, e a tag só sai no fim de um grupo com a CI da `main` verde, incluído o teste de atualização da fase #310.

Arquivos: um script novo `.method/scripts/tag-release.sh` e o teste dele, `.method/scripts/fetch-template.sh`, `.method/scripts/method-diff.sh` (só o texto do `--notice`), `.github/update-notice.md`, `.claude/skills/integrate/SKILL.md`, `.github/method-files.txt`, `.claude/settings.json` (allow do script novo), `docs/process-design.md` (§6 e a tabela de scripts), `README.md` (adoção e atualização), `docs/adr/ADR-008-*.md` e `docs/adr/INDEX.md`. Área sensível: `.claude/settings.json` (classe `owner-ok`), declarada aqui.

Pronto quando:

- `tag-release.sh` cria e envia a tag `vAAAA.MM.DD-N` no HEAD da `main` só quando o check `CI` desse commit está verde; senão sai diferente de zero com o motivo e não cria nada. Rodar duas vezes no mesmo commit não cria tag nova.
- A skill `integrate` chama o script no passo único de fim, depois do `end-check.sh` limpo, e só no repo do template (repo adotante não marca versão do método).
- `fetch-template.sh` sem destino usa a última tag do template; com SHA ou tag explícitos, segue como hoje. O aviso de atualização cita a tag.
- Teste que falha no código atual: com um template falso de duas tags e commits depois da última, o `fetch-template.sh` sem destino traz a última tag, não a ponta.
- ADR-008 registra a decisão e a regra da tag.
- Prova na parada: `validate.sh`, `check-docs.sh` e a CI do PR verdes.
- A primeira tag real sai no `integrate` desta onda; a gerenciadora lê a tag de volta no GitHub.

1. Testes que falham no código atual (tag e destino padrão). modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (funcionalidade com decisão tomada)
2. `tag-release.sh`, manifesto e allow. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (funcionalidade com decisão tomada)
3. `fetch-template.sh` e aviso pela última tag. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (funcionalidade com decisão tomada)
4. Skill `integrate`, ADR-008, `process-design` e README. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (docs do desenho)

## Fase #312 — testes do método não falham por carga

Fecha: #305 e #312.

Objetivo: nenhum teste de `.method/scripts/tests/` falha por causa da carga da máquina, e um teste novo recusa os padrões conhecidos em teste futuro.

Arquivos: `.method/scripts/tests/` (os testes com ocorrência e um teste novo de lint dos testes). Área sensível: nenhuma. Sem mudança de comportamento em script fora de `tests/`.

Pronto quando:

- Varredura dos três padrões em todos os testes: pipe para `grep -q` com `pipefail`, limite de tempo fixo e escrita em caminho real compartilhado. Cada ocorrência corrigida ou com o motivo escrito na linha.
- `test_settings_allow.sh` não usa pipe com `grep -q` (#305).
- Teste que falha no código atual: o lint dos testes acusa as ocorrências de hoje e passa depois da varredura.
- A suíte passa 3 vezes seguidas com a máquina carregada (load acima de 8, gerado pela própria fase); a saída das três rodadas vai no PR.
- Prova na parada: `validate.sh --full`, `check-docs.sh` e a CI do PR verdes.

1. Lint dos testes que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (classe de bug com causa conhecida)
2. Varredura e correção dos três padrões. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (classe de bug com causa conhecida)
3. Três rodadas sob carga. modelo: sonnet · esforço: low · motivo: peso light de .method/scripts/lib/weights.tsv (só rodar e registrar)
