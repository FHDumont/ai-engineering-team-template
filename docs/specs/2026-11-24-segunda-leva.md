# Spec: segunda leva dos adotantes (issues #213 a #221)

Achados das atualizações `e9fb05b` → `eaeaaea`. Modo de fim: end:auto-close. Grupo: segunda-leva. Três fases em paralelo, com arquivos separados; a #215 abre só depois do merge da #213, porque as duas tocam `.github/update-notice.md`. Depois de todas, a gerenciadora prova a atualização de `eaeaaea` para o commit novo num repo de mentira e avisa os adotantes nas issues de atualização deles.

## Fase #213 — aviso de atualização gerado pelo intervalo

Fecha: #213, #216, #217.

Arquivos: `scripts/method-diff.sh`, `.github/update-notice.md`, `.github/method-files.txt`, `scripts/tests/test_method_diff*.sh`, `scripts/tests/test_update_notice.sh`, `docs/process-design.md` (atualização). Área sensível: nenhuma do dono.

Pronto quando:

- `method-diff.sh` tem a classe `outdated` (repo = origem ≠ destino); `adapted` fica só para repo ≠ origem e ≠ destino; teste cobre os dois;
- arquivo novo do destino dentro das pastas do método (menos `scripts/tests/template/` e `docs/specs/`) sai `missing`, mesmo fora do manifest; teste: repo na origem sem um teste novo do destino;
- `method-diff.sh --notice` imprime o aviso só com os itens que valem no intervalo: `settings.json` mudou, `ci-mode` falta (arquivo nem variável `PROCESS_CI_MODE`), cada `missing`/`missing-label`, arquivos removidos, frase antiga do STATE presente, e a label que o PR de atualização recebe conforme o verificador da origem (`needs-owner-ok` antes das classes, `needs-gate-review` depois); teste: origem `e9fb05b` com settings igual ao destino não pede ok de permissões nem `ci-mode`;
- o aviso diz que a label nova do portão entra no merge pelo `close-phase.sh` (#220), sem passo manual;
- #216: o aviso (e o `--notice`) manda conferir os docs também com o `check-docs.sh` da origem quando a origem tem limite menor, e o `method-diff.sh` imprime o comando exato (`git show <origem>:scripts/check-docs.sh`); teste: STATE de 600 palavras com a origem `e9fb05b` dá o aviso;
- #217: `.github/update-notice.md` deixa de ser repo-owned (é texto do método e entra em `method-files.txt`); teste: repo com o aviso antigo sai `outdated`, e o guia manda trazer o do destino.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (feature comum)
2. A mudança, um commit por item. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (feature comum)

## Fase #220 — merge da atualização e parecer com ressalva

Fecha: #220, #219.

Arquivos: `scripts/close-phase.sh`, `.claude/agents/close-reviewer.md`, `.claude/skills/close-phase/SKILL.md`, os testes de `close_phase`. Área sensível: gate (segunda revisão).

Pronto quando:

- #220: `close-phase.sh --merge` cria a label do portão que falta no repositório a partir do `labels.tsv` do HEAD do PR antes de pô-la no PR; teste no gh falso: label ausente e `--merge` não para por isso;
- #219: o `close-reviewer.md` deixa a linha `Veredito:` só com `aprovado` ou `mudanças pedidas`, a ressalva noutra linha, com exemplo;
- #219: a recusa do `--publish-review` diz "rode o close-reviewer de novo; nunca edite o parecer"; teste com o sufixo;
- #219: o `--publish-review` recusa o parecer alterado depois de salvo (hash gravado no trace quando o parecer é salvo, conferido na publicação); teste.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção, um commit por item. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #214 — status.sh da fase reaberta, nomes do repo-notes e tempo de trabalho

Fecha: #214, #218, #221.

Arquivos: `scripts/status.sh`, `scripts/tests/test_bots.sh`, `scripts/machine-slots.sh` (`--report`), os testes deles, `docs/process-design.md` (§6.4). Área sensível: nenhuma do dono.

Pronto quando:

- #214: `status.sh` só lê `phase_status` e `phase_session` depois do último `phase_opened` da issue; sem sessão depois dele, a fase sai "aberta, sem sessão" e sem par; teste com o trace da issue reaberta;
- #214: `status.sh` conta uma fase por branch de fase, não por worktree sob `.worktrees/issue-<n>`; teste;
- #218: `test_bots.sh` procura os nomes só deste repositório no mesmo conjunto do `check-docs.sh` (desenho, `AGENTS.md`, skills, scripts e hooks do método), fora `docs/STATE.md`, `docs/BOTS.md`, `CONTEXT.md` e ADRs; teste: nome no STATE passa, o mesmo nome num script do método falha;
- #221: `machine-slots.sh --report` mostra a duração da fase pelo relógio e a de trabalho, que desconta os intervalos com o último `phase_status` em `esperando` e o intervalo entre um `phase_closed` e o `phase_opened` seguinte da mesma issue; o `over-target` usa a de trabalho; teste: 30 min de trabalho e 20 h esperando não dão `over-target` com meta de 45 min.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção, um commit por item. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #215 — filha headless da atualização

Fecha: #215. Abre depois do merge da #213.

Arquivos: `scripts/fetch-template.sh` (novo), `scripts/start-headless.sh`, `.claude/settings.json`, `.claude/skills/execute/SKILL.md`, `.github/update-notice.md`, `.github/method-files.txt`, os testes deles. Área sensível: owner-ok (`settings.json`, `start-headless.sh`).

Pronto quando:

- `scripts/fetch-template.sh <sha> [--url <template>]` busca o destino e o extrai em `.process/template` do worktree, sem worktree registrado nem clone; `--apply` copia os caminhos do método do destino (a lista do `method-diff.sh`) para o worktree; teste com um template local;
- o allow list de `.claude/settings.json` tem `fetch-template.sh` e `Bash(git add *)` (o hook segue barrando `-A` e `.`); `test_settings_allow` cobre;
- o aviso e a skill `execute` dizem que o checkout do template da filha é `.process/template`, trazido por `fetch-template.sh`;
- uma filha headless de atualização chega ao `method-diff.sh` e ao commit sem pergunta nem desvio; prova por dry-run do `start-headless.sh` e pelo teste do script.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (feature comum)
2. A mudança, um commit por item. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (feature comum)
