#!/usr/bin/env bash
# The texts describe one path for the phase: child session only, how it is opened,
# what happens when start_session is refused, and who closes it.
# shellcheck source=scripts/tests/lib.sh
source "$(dirname "$0")/lib.sh"

plan="$(cat "$REPO/.claude/skills/plan/SKILL.md")"
close="$(cat "$REPO/.claude/skills/close-phase/SKILL.md")"
design="$(cat "$REPO/docs/process-design.md")"

# The announced subagent is gone from every text and script.
for f in AGENTS.md docs/process-design.md docs/STATE.md scripts/close-phase.sh \
  .claude/skills/plan/SKILL.md .claude/skills/execute/SKILL.md .claude/skills/close-phase/SKILL.md; do
  assert_not_contains "$(cat "$REPO/$f")" "subagent-phases" "$f does not cite .process/subagent-phases"
  assert_not_contains "$(cat "$REPO/$f")" "anunciad" "$f has no announced subagent"
done

# plan: exact start_session fields, every child in the turn of "executar", one path when refused.
for field in 'initiation: "user_asked"' 'context: "fresh"' 'use_worktree: false' '`background`' '`title`'; do
  assert_contains "$plan" "$field" "plan names the start_session field $field"
done
assert_contains "$plan" "mesmo turno" "plan opens every child session in the turn of the request"
assert_contains "$plan" 'initiation: "own_initiative"' "plan says what to do when start_session is refused"
assert_contains "$plan" "--state esperando" "plan stops waiting for the owner after a refusal"
assert_not_contains "$plan" "Tentar de novo" "plan has no second path after a refusal"
assert_contains "$design" 'initiation: "own_initiative"' "the design has the same path for a refused start_session"
assert_not_contains "$design" "Tentar de novo" "the design has no second path after a refusal"

# close-phase: the session that opened the phase forwards and stops; the owner's ok is asked in the phase session.
assert_contains "$close" "repasse e pare" "close-phase has the forward-and-stop step"
assert_contains "$close" "saída 9" "close-phase names the exit code of the opening session"
assert_contains "$close" "não atravessa sessões" "close-phase says the owner's ok does not cross sessions"

# Conflict: one path, redo-phase.sh, in every text; nobody is asked and no rebase is offered.
integration="$(cat "$REPO/.claude/skills/integrate/integration.md")"
for name in .claude/skills/close-phase/SKILL.md .claude/skills/integrate/SKILL.md .claude/skills/integrate/integration.md docs/process-design.md; do
  text="$(cat "$REPO/$name")"
  assert_contains "$text" "redo-phase.sh" "$name names redo-phase.sh for a conflicting PR"
  assert_contains "$text" "gen-docs.sh" "$name names gen-docs.sh for the generated files"
  assert_not_contains "$text" "rebase sobre" "$name offers no rebase onto main"
  assert_not_contains "$text" "com cherry-pick** e PR novo" "$name has no choice of ways out"
  assert_not_contains "$text" "conflito de comportamento" "$name sends no conflict to a choice card"
done
assert_not_contains "$close" "Quadro ao dono: **rebase" "close-phase does not ask the owner about a conflict"
assert_not_contains "$close" "regera" "close-phase does not regenerate files in the phase"
assert_not_contains "$design" "Regera \`CHANGELOG.md\`" "the design does not regenerate files in the phase"
assert_contains "$close" "posterior ao último push" "close-phase says a review needs a round after the last push"
assert_contains "$integration" "só espera" "integration says integrate-parallel.sh only waits"
# Deploy: one path, scripts/deploy.sh by the main session; no text sends the phase or
# close-phase.sh --merge to dispatch it.
for name in .claude/skills/close-phase/SKILL.md .claude/skills/integrate/SKILL.md .claude/skills/integrate/integration.md \
  docs/process-design.md docs/STATE.md app/README.md; do
  text="$(cat "$REPO/$name")"
  assert_contains "$text" "deploy.sh" "$name names deploy.sh for the deploy"
  assert_not_contains "$text" "dispara na fase solo" "$name has no deploy by the solo phase"
  assert_not_contains "$text" "dispara uma vez o" "$name has no dispatch by close-phase.sh --merge"
  assert_not_contains "$text" "dispara o deploy único" "$name has no dispatch outside deploy.sh"
  assert_not_contains "$text" 'ou `close-phase.sh --merge`' "$name has no second dispatcher"
done
assert_contains "$close" "A fase não faz deploy" "close-phase says the phase never deploys"
assert_contains "$design" 'tem `phase_session` no trace' "the design lists the phase-session refusal of deploy.sh"

# End of the phase: one text for who asks, how a card starts and the end step.
agents="$(cat "$REPO/AGENTS.md")"
execute="$(cat "$REPO/.claude/skills/execute/SKILL.md")"
integrate="$(cat "$REPO/.claude/skills/integrate/SKILL.md")"
assert_contains "$agents" 'começa por `Fase #n — título`' "AGENTS says how every card starts"
assert_contains "$agents" "Só a principal pergunta" "AGENTS says only the main session asks"
assert_contains "$agents" "não atravessa sessões" "AGENTS says the owner's ok does not cross sessions"
assert_not_contains "$agents" "Pergunta só a sessão que precisa da resposta" "AGENTS has no second rule for who asks"
assert_contains "$execute" "mande à gerenciadora" "execute sends a doubt to the manager"
assert_not_contains "$execute" "Pergunta ao dono: só quem precisa" "execute does not ask the owner for information"
assert_not_contains "$execute" "Grande: quadro de escolha ao dono" "execute sends a large finding to the manager"
assert_contains "$execute" 'Fase #<n> — <título>:' "execute says how its only card starts"
assert_not_contains "$close" "faça um quadro de escolha ao dono" "close-phase sends the third round to the manager"
assert_contains "$close" 'esta sessão, que roda o `--merge`, pede o ok nela mesma' "the session that runs --merge asks for the merge ok"
assert_contains "$close" 'Fase #<n> — <título>:' "close-phase says how the merge card starts"
assert_contains "$close" "--abort --discard" "close-phase describes the safe abort"
assert_contains "$close" "end-check.sh --issue" "close-phase says pronto runs end-check.sh"
assert_contains "$design" "block-card-title.sh" "the design lists the card hook"
assert_contains "$design" "end-check.sh" "the design lists end-check.sh"
# The end step is one text, in the integrate skill, the same for a solo and a parallel group;
# the other texts point to it.
assert_eq "scripts/gen-docs.sh scripts/deploy.sh archive_session scripts/end-check.sh" \
  "$(printf '%s\n' "$integrate" | grep -oE 'scripts/gen-docs\.sh|scripts/deploy\.sh|archive_session|scripts/end-check\.sh' | awk '!seen[$0]++' | paste -sd' ' -)" \
  "integrate has the end step in order: gen-docs.sh, deploy.sh, archiving, end-check.sh"
assert_contains "$integrate" "solo ou paralelo" "the end step is the same for a solo and a parallel group"
assert_contains "$integrate" "tente de novo uma vez" "the main session retries the archiving by itself"
assert_contains "$integrate" "sessão fixada ou em uso" "a pinned or busy session becomes a card"
assert_contains "$integrate" '--state esperando --need "arquivar a sessão' "the session left open shows in Você precisa"
for name in AGENTS.md .claude/skills/plan/SKILL.md .claude/skills/close-phase/SKILL.md docs/process-design.md docs/STATE.md; do
  assert_contains "$(cat "$REPO/$name")" 'skill `integrate`' "$name points to the end step of the integrate skill"
done
for name in .claude/skills/close-phase/SKILL.md .claude/skills/integrate/SKILL.md .claude/skills/integrate/integration.md docs/process-design.md; do
  text="$(cat "$REPO/$name")"
  assert_not_contains "$text" "só após duas recusas" "$name has no archiving by the owner after two refusals"
  assert_not_contains "$text" "o script chamou" "$name has no deploy by integrate-parallel.sh"
  assert_not_contains "$text" '`integrate-parallel.sh` o chama' "$name has no deploy called by integrate-parallel.sh"
  assert_not_contains "$text" "chama o \`scripts/deploy.sh\`" "$name has no script that calls deploy.sh"
  assert_not_contains "$text" "sai do registro à mão" "$name edits no registry by hand"
done
# Archiving the child sessions: the child leaves no live work behind, and the manager
# archives in one order: Remote Control off, read back, archive, repeat once with the field
# the app returns, ask the child to stop its tasks, and only then a card to the owner.
for name in execute close-phase; do
  text="$(cat "$REPO/.claude/skills/$name/SKILL.md")"
  assert_contains "$text" "Antes da parada final da fase" "$name has the step before the final stop"
  assert_contains "$text" "liste as suas tarefas em segundo plano e pare cada uma" "$name stops its own background tasks"
  assert_contains "$text" "liste as suas tarefas recorrentes e apague cada uma" "$name deletes its own recurring tasks"
  assert_contains "$text" "leia de volta que as duas listas estão vazias" "$name reads back that no task is left"
  assert_contains "$text" "\`Tarefas em segundo plano e recorrentes: nenhuma\`" "$name says in the final message that it left no task"
done
arch="$(printf '%s\n' "$integrate" | awk '/Arquive cada sessão filha/{p=1} /Apague o batimento/{p=0} p')"
assert_eq "set_remote_control remoteControlState archive_session trabalho vivo quadro ao dono" \
  "$(printf '%s\n' "$arch" | grep -oE 'set_remote_control|remoteControlState|archive_session|trabalho vivo|quadro ao dono' | awk '!seen[$0]++' | paste -sd' ' -)" \
  "integrate archives in one order: Remote Control off, read back, archive, live work, card"
assert_contains "$arch" "nesta ordem única" "integrate says the archiving has one order"
assert_contains "$arch" "\`set_remote_control\` \`false\`. Sempre" "integrate always turns Remote Control off"
assert_contains "$arch" "\`remoteControlState\` \`off\`" "integrate reads back that Remote Control is off"
assert_contains "$arch" "Nunca arquive com ele ligado" "integrate never archives with Remote Control on"
assert_contains "$arch" "repita uma vez, exatamente com esse campo" "integrate repeats the archiving once with the field the app returns"
assert_contains "$arch" "mande mensagem à filha (\`send_message\`)" "integrate asks the child to stop its tasks on live work"
assert_contains "$arch" "Só depois disso" "integrate opens the card only after the other tries"
assert_contains "$arch" "quadro ao dono (\`AskUserQuestion\`) que começa por \`Fase #n — título\`" "integrate says how the archiving card starts"
# Manager heartbeat: plan creates it and says what it reads, integrate deletes
# it in the end step, the design has the rule and the reason and names no app tool.
assert_contains "$plan" "**Batimento, depois das filhas:**" "plan creates the heartbeat after the sessions"
assert_eq 1 "$(($(grep -n -F '**Filhas:**' <<<"$plan" | cut -d: -f1) < $(grep -n -F '**Batimento' <<<"$plan" | cut -d: -f1)))" "plan puts the heartbeat after the child sessions"
assert_eq 1 "$(($(grep -n -F '**Filhas:**' <<<"$plan" | cut -d: -f1) < $(grep -n -F '**Recusado**' <<<"$plan" | cut -d: -f1)))" "plan puts the stop after the child sessions"
where="na barra lateral, dentro do agrupamento da sessão principal; se não aparecer, abra o agrupamento"
assert_contains "$plan" "$where" "plan has the sentence that says where the session is"
assert_contains "$plan" "título exato" "plan asks for the exact title of the session"
assert_contains "$plan" "só com \`list_sessions\` mostrando filha rodando" "plan creates the heartbeat only with a child running"
assert_contains "$plan" "só escreve, com o bloco, se o estado mudou" "plan says the heartbeat writes only on change"
assert_contains "$plan" "faz o próximo passo" "plan says what the heartbeat does"
assert_contains "$plan" "4 minutos" "plan gives the interval of the heartbeat"
assert_contains "$integrate" "4 minutos" "integrate gives the interval of the heartbeat"
assert_contains "$integrate" "Apague o batimento" "integrate deletes the heartbeat in the end step"
assert_contains "$integrate" "Nenhum script confere" "integrate says no lock checks the heartbeat"
hb="$(printf '%s\n' "$design" | grep -F '**batimento**')"
assert_eq 1 "$(printf '%s\n' "$hb" | grep -c .)" "the design states the heartbeat rule in one place"
assert_contains "$hb" "apaga o batimento, se criado, no passo único de fim" "the design says when the heartbeat goes away"
assert_contains "$hb" "Depois de abrir as filhas" "the design creates the heartbeat after the sessions"
assert_contains "$hb" "Com todas as filhas em cartão esperando, não há batimento" "the design creates no heartbeat while every child is a card"
assert_contains "$hb" "Só escreve ao dono quando o estado mudou" "the design says the heartbeat writes only on change"
assert_eq 1 "$(grep -c -F "$where" <<<"$design")" "the design has the sentence that says where the session is, in one place"
assert_eq 1 "$(($(grep -n -F 'abre todas as filhas do grupo' <<<"$design" | cut -d: -f1) < $(grep -n -F '**batimento**' <<<"$design" | cut -d: -f1)))" "the design puts the heartbeat after the child sessions"
assert_contains "$hb" "o aviso de fim da filha nem sempre chega" "the design gives the reason of the heartbeat"
assert_eq "" "$(printf '%s\n' "$design" | grep -n 'Cron' || true)" "the design names no tool of one app for the heartbeat"
assert_contains "$hb" "a cada 4 minutos" "the design gives the interval of the heartbeat"
# The interval is 4 minutes everywhere: no text, script or test keeps the old one.
# The old number is built here so that this file does not match its own search.
was=8
# ROADMAP.md and CHANGELOG.md are generated from issue titles, not heartbeat text: a title
# with the old number and minutes (#44 had one) must not fail the suite.
old_interval_in() { (cd "$1" && git grep -n -I --untracked -E "$was min|$was minutes|[*]/$was|every $was" -- . ':!ROADMAP.md' ':!CHANGELOG.md' || true); }
assert_eq "" "$(old_interval_in "$REPO")" "no file keeps the old interval of the heartbeat"
# An untracked file with the old interval is visible before it is committed (#117).
printf 'a cada %s minutos\n' "$was" >"$REPO/untracked-interval.md"
assert_contains "$(old_interval_in "$REPO")" "untracked-interval.md" "an untracked file with the old interval is found"
rm -f "$REPO/untracked-interval.md"
gen_repo="$(mktemp -d)"
git -C "$gen_repo" init -q
printf -- '- #44 Heartbeat every %s min\n' "$was" >"$gen_repo/ROADMAP.md"
printf -- '- fix: heartbeat of %s minutes\n' "$was" >"$gen_repo/CHANGELOG.md"
printf 'a cada %s minutos\n' "$was" >"$gen_repo/plan.md"
git -C "$gen_repo" add ROADMAP.md CHANGELOG.md plan.md
assert_contains "$(old_interval_in "$gen_repo")" "plan.md" "the old interval is still found in a text"
assert_eq "1" "$(old_interval_in "$gen_repo" | wc -l | tr -d ' ')" "an issue title with the old interval in the generated files does not count"
rm -rf "$gen_repo"
# End-step action denied by the app: one path, a choice card that authorizes and
# the session itself runs the action again; the owner never runs a script.
denied="$(printf '%s\n' "$integrate" | awk '/negada pelo app\. Caminho único/{p=1} /^[0-9]+\. /&&!/negada pelo app/{p=0} p')"
assert_contains "$denied" "\`scripts/deploy.sh\`" "integrate covers the deploy denied by the app"
assert_contains "$denied" "\`archive_session\`" "integrate covers the archiving denied by the app"
assert_contains "$denied" "quadro de escolha (\`AskUserQuestion\`) que começa por \`Fase #n — título\`" "integrate sends a denied action to a choice card"
assert_contains "$denied" '"Autorizar o deploy"' "integrate names the option that authorizes the deploy"
assert_contains "$denied" "esta sessão roda a mesma ação de novo" "integrate makes the session run the action after the ok"
assert_contains "$denied" '--state esperando --need "responder ao quadro' "integrate stops asking for the answer to the card"
assert_contains "$denied" "Nunca peça ao dono que rode script nem que arquive pela barra lateral" "integrate never sends the owner to run a script"
assert_contains "$integrate" "Negado pelo app: passo 4" "the deploy and the archiving point to the denied path"
assert_not_contains "$integrate" "arquivar a sessão\` e pare" "a session the app does not archive has no second card"
# Model and effort: one path. The pairs come from the weights file, the design no longer
# states a ceiling of start_session as a fact, and the texts send a divergence to check-env.sh.
execute="$(cat "$REPO/.claude/skills/execute/SKILL.md")"
sec3="$(printf '%s\n' "$design" | awk '/^## 3\. /{p=1; print; next} /^## /{p=0} p')"
assert_contains "$sec3" "scripts/lib/weights.tsv" "section 3 names the weights file"
assert_contains "$sec3" "o app não garante" "section 3 says the app does not guarantee the pair"
assert_contains "$sec3" "phase_pair_mismatch" "section 3 says what a divergence records"
assert_contains "$sec3" "trace-view.py --pairs" "section 3 says the script writes the PR table"
for name in docs/process-design.md docs/STATE.md AGENTS.md .claude/skills/plan/SKILL.md .claude/skills/execute/SKILL.md \
  .claude/skills/close-phase/SKILL.md .claude/skills/triage/SKILL.md .github/pull_request_template.md; do
  text="$(cat "$REPO/$name")"
  assert_eq "" "$(printf '%s\n' "$text" | grep -nwiE 'teto|opus|sonnet|haiku' || true)" "$name states no ceiling and names no model"
  assert_not_contains "$text" "108962" "$name cites no documented limit of start_session"
  assert_not_contains "$text" "forte+" "$name has no weight outside the file"
done
assert_not_contains "$plan" "suba o par (quadro) ou abra" "plan has one path for a spec pair above the session's"
assert_not_contains "$plan" "get_session" "plan does not read the pair back by hand"
assert_contains "$plan" "check-env.sh" "plan leaves the check of the real pair to check-env.sh"
assert_contains "$execute" "nenhuma etapa começa" "execute stops before the first step on a divergence"
assert_contains "$execute" "par da principal" "execute has the one path for a pair above the main session's"
assert_contains "$execute" "close-phase.sh --prepare" "execute leaves the PR table to the script"
assert_not_contains "$execute" "nunca da memória" "execute fills no PR table by hand"
assert_contains "$close" "o \`--prepare\` escreve nela a tabela" "close-phase leaves the pair section to the script"
# The design says why the issue templates are Markdown and not issue forms.
templates="$(grep -F 'Templates em Markdown' "$REPO/docs/process-design.md" || true)"
assert_contains "$templates" "não issue forms" "the design keeps the rule of Markdown templates"
assert_contains "$templates" "modal pequeno, campo por campo" "the design says what the YAML form opens"
assert_contains "$templates" "editor grande" "the design says what the Markdown template opens"

# Texts never build PR, issue or review bodies at a fixed /tmp path (parallel sessions would overwrite it).
for f in .claude/skills/*/SKILL.md .claude/agents/*.md; do
  assert_not_contains "$(grep -E '/tmp/[A-Za-z0-9_.-]+' "$REPO/$f" || true)" "/tmp/" "$f has no fixed /tmp path"
done
for f in .claude/skills/execute/SKILL.md .claude/skills/close-phase/SKILL.md .claude/skills/ask-bot/SKILL.md .claude/agents/close-reviewer.md; do
  assert_contains "$(cat "$REPO/$f")" "mktemp" "$f says to use mktemp for temporary texts"
done
# lab-test stop (#46): the session runs the script checks itself; the owner is never asked to.
assert_contains "$execute" "rode nesta sessão cada verificação que é script" "execute runs the script checks in the session at lab-test"
for f in .claude/skills/*/SKILL.md; do
  lab="$(grep 'lab-test' "$REPO/$f" || true)"
  assert_not_contains "$lab" "rode scripts/" "$f lab-test text never asks the owner to run scripts/"
  case "$lab" in *"rode o scripts"*|*"rode o \`scripts"*) bad "$f lab-test text asks the owner to run a script" ;; *) ok ;; esac
done

# Reviewer reads the CI result (#43): the suite only runs when the Tests check of the SHA is missing or failed.
reviewer="$(cat "$REPO/.claude/agents/close-reviewer.md")"
assert_contains "$reviewer" "check-runs" "close-reviewer reads the Tests check of the SHA through the API"
assert_contains "$reviewer" "só rode a suíte se o check \`Tests\` faltar ou falhar" "close-reviewer runs the suite only when the Tests check is missing or failed"
assert_contains "$close" "revisor lê o check \`Tests\` do SHA" "close-phase says the reviewer reads the CI result"

# Questions to the owner: only the sensitive list stops a phase; the rest goes to the PR.
agents="$(cat "$REPO/AGENTS.md")"
execute="$(cat "$REPO/.claude/skills/execute/SKILL.md")"
plan="$(cat "$REPO/.claude/skills/plan/SKILL.md")"
design="$(cat "$REPO/docs/process-design.md")"
for t in "$agents" "$execute" "$design"; do
  assert_contains "$t" "Decisões tomadas sem perguntar" "a reversible doubt is listed in the PR section"
done
assert_contains "$plan" "num quadro só" "plan grilling puts every question in one card"
assert_not_contains "$plan" "quadro por decisão" "plan grilling has no card per decision"
assert_not_contains "$agents" "relate." "AGENTS no longer reports a doubt only in the status"

# setup: the time target and the machine limits are explained and asked only here.
setup="$(cat "$REPO/.claude/skills/setup/SKILL.md")"
assert_contains "$setup" ".github/time-targets.tsv" "setup writes the time target file"
assert_contains "$setup" "Meta de tempo" "setup asks the time target"
assert_contains "$setup" "machine-limits.env" "setup shows the machine limits"
assert_contains "$setup" "# setup: confirmed" "setup asks the machine limits only the first time on a machine"
assert_contains "$setup" "AI_METHOD_SLOTS_FASE" "setup explains each machine limit"
assert_contains "$setup" "over-target" "setup says the owner is called again only on over-target"
assert_contains "$(cat "$REPO/README.md")" "meta de tempo" "the quick start mentions the time target"

# Notes to the headless child (#74) and the cheap pre-review (#75).
execute="$(cat "$REPO/.claude/skills/execute/SKILL.md")"
reviewer="$(cat "$REPO/.claude/agents/close-reviewer.md")"
assert_contains "$execute" "Para: fase #<n>" "execute makes the child read the notes addressed to the phase"
assert_contains "$execute" "Filha do app e headless" "execute reads notes in the app child and the headless child"
assert_contains "$execute" "antes de cada etapa, da parada de lab-test e do \`close-phase.sh --merge\`" "execute reads them before each step, lab-test and --merge"
assert_contains "$plan" "Segurar o merge é comentário" "plan holds a merge with a note on the issue"
assert_contains "$close" "--owner-ok <sha>" "close-phase binds the owner ok to a SHA"
assert_contains "$close" "close-phase.sh --pre-review" "close-phase records the pre-review before --prepare"
assert_contains "$close" "no máximo 2 vezes" "close-phase limits the pre-review fixes to 2"
assert_contains "$reviewer" "Pré-revisão" "close-reviewer knows the pre-review mode"
assert_contains "$design" "Pré-revisão" "the design describes the pre-review"
assert_contains "$design" "Recado à filha" "the design describes the note to the child"

finish
