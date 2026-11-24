# Spec: achados dos adotantes na atualização para e9fb05b (issues #179 a #195)

Quatro fases em paralelo, separadas por arquivo. `docs/process-design.md` é tocado por todas, cada uma na sua seção; conflito no rebase é resolvido pela fase que mergeia depois. Modo de fim: end:auto-close. Grupo: adotantes. Paralelo (`integration.md`).

Ordem de merge: a #186 entra primeiro (troca a regra de caminho sensível); as outras rebaseiam sobre ela. A #186 é a última que pede o ok do dono pela regra antiga.

Decisões do dono (quadros de 2026-11-24):

- Modo `pr` da CI: só documentar a garantia (o PR seguinte testa a soma; o deploy roda `validate.sh`); os testes aceitam o modo `pr`.
- Veredito do revisor: `close-phase.sh` grava o `.verdict` a partir do parecer; o agente grava só o `.md`.
- Ok do dono só para migrações de banco, segredos e autenticação, cobrança e infra de produção. Dependências, lockfiles, `deploy-*.yml` e o portão passam por uma segunda revisão automática, focada em "enfraquece o portão?", sem ok do dono.
- A atualização não exige mais a fase `test` depois do merge: a prova é a primeira fase normal que abre e fecha pelo portão.
- Limites: `AGENTS.md` 300-800 palavras; `docs/STATE.md` até 800.
- O aviso de atualização exige uma prova local (atualização a partir da versão anterior), não três.

## Fase #179 — method-diff --find-base não morre calado

Fecha: #179, #181.

Arquivos: `scripts/method-diff.sh`, `scripts/tests/test_method_diff.sh`.

Pronto quando:

- teste vermelho no código atual: repo sem `.github/method-origin` em nenhum commit (causa da #181, o `while` herda o 128 do `cat-file -e`) e repo cujo primeiro commit tem arquivo ausente nos commits antigos do template (causa da #179, `blob_at` sem tratar falha); nos dois, `--find-base` sai 0 e imprime a base certa;
- arquivo ausente num dos lados conta como diferente;
- falha real (template sem commits, caminho errado) sai com mensagem, nunca 128 calado.

1. Testes que falham no código atual, um por causa. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção, um commit por causa. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #183 — testes do método rodam em qualquer adotante e qualquer locale

Fecha: #183, #184 (parte de labels), #187, #189.

Arquivos: `scripts/lib/common.sh`, `scripts/auto-label.py`, `scripts/tests/test_phase_scripts.sh`, `scripts/tests/test_issue_tools.py`, `scripts/tests/test_label_issue.sh`, `scripts/tests/test_open_issue.sh`, `scripts/tests/test_phase_texts.sh`. Não toca `test_workflow_tools.py` (é da #186).

Pronto quando:

- `slug_ascii "por área"` dá `por-area` com `LC_ALL=C` e com `LANG`/`LC_ALL` vazios; teste roda nesse locale;
- `test_issue_tools.py` lê as labels de área de `.github/labels.tsv`/`.github/label-areas.tsv` do repo, sem fixar `area:auth`;
- `test_label_issue.sh` e `test_open_issue.sh` usam um rótulo de grupo próprio quando `labels.tsv` não tem `group:*`, e falham com mensagem, nunca calados;
- `test_phase_texts.sh` confere o ponteiro da `integrate` em `AGENTS.md` ou no desenho, não em `docs/STATE.md`;
- `auto-label.py` não põe `needs-context` em issue com o cabeçalho `**De:** … **Para:** …` (recado entre repos); teste cobre;
- a suíte passa num repo adotante de mentira com outro `labels.tsv`, sem `group:*`.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção, um commit por issue. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #190 — caminho da atualização sem parada

Fecha: #188, #190, #191, #193, #194, #195.

Arquivos: `README.md` (seção de atualização), `.github/update-notice.md`, `scripts/setup-repo.sh`, `scripts/phase-start.sh`, `scripts/check-env.sh`, `scripts/check-docs.sh`, `docs/repo-notes.md` (modelo), os testes deles, `docs/process-design.md` (§ da atualização e dos limites).

Pronto quando:

- #190: o PR de atualização traz `.github/ci-mode` com a escolha do dono (guia e `update-notice.md` dizem); `setup-repo.sh --check` falha, com o mesmo texto, quando o `phase-start.sh` recusaria pelo modo; a recusa cita `PROCESS_CI_MODE` e o passo do `setup-repo.sh`;
- #191: dependência de produto ausente no `python3` do sistema vira `warn:` no `check-env.sh`, sem instalar nada;
- #188: a mensagem do `check-docs.sh` diz que o script existe mas não está em `.github/method-files.txt` e como resolver; o guia diz que script só do repo entra no manifesto;
- #193: o guia de atualização manda criar `docs/repo-notes.md` (modelo com `## Nomes só deste repositório`); `check-docs.sh` avisa quando `AGENTS.md` aponta para ele e ele não existe;
- #194: a cópia solta da spec sai quando a outra fase da spec já teve `phase_opened` ou PR mergeado, mesmo com a issue aberta; teste cobre;
- #195: o aviso e o guia não pedem mais a fase `test` pós-merge; a issue de atualização fecha no merge com `validate.sh` e `check-docs.sh` verdes; a prova é a primeira fase normal;
- limites do `check-docs.sh`: `AGENTS.md` 300-800, `docs/STATE.md` até 800 (texto do `--help` e desenho concordam);
- o aviso de atualização pede uma prova local (atualização a partir da versão anterior), não três.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção, um commit por issue. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #186 — CI e portão: rótulo certo, veredito pelo script, ok só no risco real

Fecha: #180, #182, #184 (parte do filtro), #185, #186, #192.

Arquivos: `.github/workflows/ci.yml` (job `policy`), `scripts/lib/sensitive_paths.py`, `.github/sensitive-paths`, `.github/labels.tsv`, `scripts/close-phase.sh`, `.claude/skills/close-phase/SKILL.md`, `.claude/agents/close-reviewer.md`, `AGENTS.md` ("Quando perguntar"), `scripts/tests/test_workflow_tools.py`, testes do `close-phase.sh`, `docs/process-design.md` (§9.2, §10.3, portão). Área sensível: sim (portão).

Pronto quando:

- #186: com a base no `sensitive_paths.py` de `c1b76da`, o PR que toca `ci.yml` recebe a label; o passo não depende de o verificador da base entender `-z` (cai para a lista por linha); o guia diz o que acontece no PR de atualização;
- #192: o agente grava só `.process/reviewer-<sha>.md`; `close-phase.sh` lê a linha `Veredito:` e grava o `.verdict`; veredito passado diferente do parecer é recusado; a mensagem de falta diz que a sessão da fase grava a saída literal do `close-reviewer`;
- ok do dono: `.github/sensitive-paths` separa duas classes. `owner-ok` (migrações, `.env*`, `secrets/`, `credentials/`, `auth/`, `billing/`, `payments/`, `infra/production/`) mantém `needs-owner-ok` e `--owner-ok`. `gate` (dependências e lockfiles, `deploy-*.yml`, `ci.yml`, verificadores, `close-phase.sh`, a própria lista) recebe `needs-gate-review`: o `--merge` exige uma segunda revisão do `close-reviewer`, focada em "enfraquece o portão?", gravada como a primeira, e mergeia sem o dono; testes: gate sem a segunda revisão é recusado; com ela aprovada mergeia; `owner-ok` sem o ok segue recusado; repo adotante com o arquivo antigo (uma classe só) continua pedindo o ok em tudo;
- #180/#182/#185: o desenho (§9.2) e a pergunta do setup dizem a garantia do modo `pr` (o PR seguinte testa a soma; o deploy roda `validate.sh`); os testes de `ci.yml` leem `.github/ci-mode` e, no modo `pr`, afirmam a ausência do `push` em vez de quebrar;
- #184 (filtro): o teste do filtro lê o filtro de app do `ci.yml` do repo, sem fixar `app/`;
- `AGENTS.md` "Quando perguntar" concorda com as classes novas.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (portão e caminho sensível)
2. A correção, um commit por issue. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (portão e caminho sensível)
