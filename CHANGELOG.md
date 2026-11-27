# Changelog

<!-- Gerado por .method/scripts/gen-changelog.py; não editar à mão. -->

## Funcionalidades

- feat: warn about old .env folders with the command to migrate or remove them ([#333](https://github.com/FHDumont/ai-engineering-team-template/pull/333)) · 2026-11-27
- feat(secret): honor DUMONTECH_HOME for the repo .env and shared bots.env ([#331](https://github.com/FHDumont/ai-engineering-team-template/pull/331)) · 2026-11-27
- fix(close-phase): keep the PR body under the limit and let the spec ok cover the merge ([#314](https://github.com/FHDumont/ai-engineering-team-template/pull/314)) · 2026-11-26
- fix: harden rerun-ci count, sensitive subfolder globs and deploy gate permission ([#313](https://github.com/FHDumont/ai-engineering-team-template/pull/313)) · 2026-11-26
- refactor: move method script paths to .method/scripts and drop the scripts link ([#293](https://github.com/FHDumont/ai-engineering-team-template/pull/293)) · 2026-11-26
- refactor: move the method scripts to .method/scripts behind a scripts link ([#289](https://github.com/FHDumont/ai-engineering-team-template/pull/289)) · 2026-11-26
- feat(close-phase): --save-review saves the reviewer opinion from the transcript ([#263](https://github.com/FHDumont/ai-engineering-team-template/pull/263)) · 2026-11-25
- feat: open the phase group in waves when fewer slots are free ([#255](https://github.com/FHDumont/ai-engineering-team-template/pull/255)) · 2026-11-24
- feat: method-diff outdated class, new destination files and --notice ([#224](https://github.com/FHDumont/ai-engineering-team-template/pull/224)) · 2026-11-24
- fix: close the remaining method gaps ([#178](https://github.com/FHDumont/ai-engineering-team-template/pull/178)) · 2026-11-23
- feat(setup): ask the time target and the machine limits in setup ([#64](https://github.com/FHDumont/ai-engineering-team-template/pull/64)) · 2026-11-21
- feat(scripts): per-project time targets, lab-test without owner scripts, close-phase progress ([#51](https://github.com/FHDumont/ai-engineering-team-template/pull/51)) · 2026-11-21
- feat(scripts): visible progress of long scripts, headless spec from worktree, CI read failure ([#49](https://github.com/FHDumont/ai-engineering-team-template/pull/49)) · 2026-11-21
- feat: heartbeat only writes when the state changed ([#21](https://github.com/FHDumont/ai-engineering-team-template/pull/21)) · 2026-11-21
- feat: unprotected branch mode for private repos on a free plan ([#14](https://github.com/FHDumont/ai-engineering-team-template/pull/14)) · 2026-11-21
- feat: require the repository setup before a phase or an issue ([#5](https://github.com/FHDumont/ai-engineering-team-template/pull/5)) · 2026-11-21
- docs: add the adoption chapter to the README ([#2](https://github.com/FHDumont/ai-engineering-team-template/pull/2)) · 2026-11-21

## Correções

- fix: fetch-template.sh --apply survives replacing itself ([#329](https://github.com/FHDumont/ai-engineering-team-template/pull/329)) · 2026-11-27
- test: accept an app scripts/lib folder in test_method_folder ([#325](https://github.com/FHDumont/ai-engineering-team-template/pull/325)) · 2026-11-27
- fix: read files from the logical root in check-env and machine-slots ([#291](https://github.com/FHDumont/ai-engineering-team-template/pull/291)) · 2026-11-26
- fix: require the CI gate in deploy workflows ([#274](https://github.com/FHDumont/ai-engineering-team-template/pull/274)) · 2026-11-25
- fix: ask-bot --append waits only for replies posted after the follow-up ([#271](https://github.com/FHDumont/ai-engineering-team-template/pull/271)) · 2026-11-25
- fix: close-phase --check redoes a PR with a commit the base already has ([#267](https://github.com/FHDumont/ai-engineering-team-template/pull/267)) · 2026-11-25
- fix: --merge --wait leaves when CI or the review turns red ([#257](https://github.com/FHDumont/ai-engineering-team-template/pull/257)) · 2026-11-24
- feat(ci): runner without actions or gh via CI_CHECKOUT_CMD ([#252](https://github.com/FHDumont/ai-engineering-team-template/pull/252)) · 2026-11-24
- fix: phase-start exits at once when the group exceeds the fase slot limit ([#253](https://github.com/FHDumont/ai-engineering-team-template/pull/253)) · 2026-11-24
- fix(tests): scan only the files of the method ([#250](https://github.com/FHDumont/ai-engineering-team-template/pull/250)) · 2026-11-24
- fix: method-diff and fetch-template --apply cover the method docs ([#232](https://github.com/FHDumont/ai-engineering-team-template/pull/232)) · 2026-11-24
- fix: fetch-template --apply brings outdated files outside the manifest ([#229](https://github.com/FHDumont/ai-engineering-team-template/pull/229)) · 2026-11-24
- feat: fetch-template.sh and allow list for the headless update child ([#225](https://github.com/FHDumont/ai-engineering-team-template/pull/225)) · 2026-11-24
- fix: close-phase merge creates the gate label and refuses an edited opinion ([#223](https://github.com/FHDumont/ai-engineering-team-template/pull/223)) · 2026-11-24
- fix: status of reopened phases, bots name scan set and work time in the slots report ([#222](https://github.com/FHDumont/ai-engineering-team-template/pull/222)) · 2026-11-24
- fix: cancelled CI job is rerunnable and the merge wait leaves on it ([#210](https://github.com/FHDumont/ai-engineering-team-template/pull/210)) · 2026-11-24
- fix: update brings repo files with a template default and find-base is fast ([#208](https://github.com/FHDumont/ai-engineering-team-template/pull/208)) · 2026-11-24
- fix: friction stops of the previous group (end-check skipped CI, review path, stale base, slot wait, light finding) ([#205](https://github.com/FHDumont/ai-engineering-team-template/pull/205)) · 2026-11-24
- feat: validate.sh runs only the tests the diff reaches in a phase ([#204](https://github.com/FHDumont/ai-engineering-team-template/pull/204)) · 2026-11-24
- fix: find-base no longer dies silent with exit 128 ([#200](https://github.com/FHDumont/ai-engineering-team-template/pull/200)) · 2026-11-24
- fix: keep the update path from stopping on missing records (#188 #190 #191 #193 #194 #195) ([#198](https://github.com/FHDumont/ai-engineering-team-template/pull/198)) · 2026-11-24
- fix: label gate and owner paths by class and read the review verdict in the script ([#197](https://github.com/FHDumont/ai-engineering-team-template/pull/197)) · 2026-11-23
- fix: run the method tests on any adopter and any locale ([#196](https://github.com/FHDumont/ai-engineering-team-template/pull/196)) · 2026-11-23
- fix: stop work that proves no new fact ([#175](https://github.com/FHDumont/ai-engineering-team-template/pull/175)) · 2026-11-23
- fix: gate a pull request that is not a phase ([#174](https://github.com/FHDumont/ai-engineering-team-template/pull/174)) · 2026-11-23
- fix: make the suite pass on an adopted repository ([#173](https://github.com/FHDumont/ai-engineering-team-template/pull/173)) · 2026-11-22
- fix: keep the first CI green and record a PR-only mode ([#172](https://github.com/FHDumont/ai-engineering-team-template/pull/172)) · 2026-11-22
- fix: open a phase without installing product dependencies ([#171](https://github.com/FHDumont/ai-engineering-team-template/pull/171)) · 2026-11-22
- fix: keep the merge gate from failing open ([#169](https://github.com/FHDumont/ai-engineering-team-template/pull/169)) · 2026-11-22
- fix: keep adoption from widening permissions ([#168](https://github.com/FHDumont/ai-engineering-team-template/pull/168)) · 2026-11-22
- fix(tests): the series case of test_validate.sh waits a short explicit limit ([#79](https://github.com/FHDumont/ai-engineering-team-template/pull/79)) · 2026-11-22
- feat(ci): run CI on push to main and let phase-start wait for it ([#61](https://github.com/FHDumont/ai-engineering-team-template/pull/61)) · 2026-11-21
- fix: accept a main base without CI when its merged PR had green CI and the same tree ([#37](https://github.com/FHDumont/ai-engineering-team-template/pull/37)) · 2026-11-21

## Manutenção

- perf(validate): show where the time goes and record validate-repo ([#260](https://github.com/FHDumont/ai-engineering-team-template/pull/260)) · 2026-11-25
- feat: extend the method without editing it by hand ([#177](https://github.com/FHDumont/ai-engineering-team-template/pull/177)) · 2026-11-23
- perf: measure phase time and cut the CI and prepare reruns ([#48](https://github.com/FHDumont/ai-engineering-team-template/pull/48)) · 2026-11-21
- feat: stop leftover processes and add sessions.sh at the end of a phase ([#25](https://github.com/FHDumont/ai-engineering-team-template/pull/25)) · 2026-11-21
- feat: machine-wide slots, queue and history for validations and phases ([#15](https://github.com/FHDumont/ai-engineering-team-template/pull/15)) · 2026-11-21
- feat: open phase children as headless claude when start_session is refused ([#13](https://github.com/FHDumont/ai-engineering-team-template/pull/13)) · 2026-11-21

## Outros

- fix(status): ignore .DS_Store when checking for pending edits on main ([#327](https://github.com/FHDumont/ai-engineering-team-template/pull/327)) · 2026-11-27
- test: make the method tests load-proof and lint the load patterns ([#319](https://github.com/FHDumont/ai-engineering-team-template/pull/319)) · 2026-11-27
- feat: versioned method releases by tag ([#318](https://github.com/FHDumont/ai-engineering-team-template/pull/318)) · 2026-11-27
- feat: open all waves on spec approval, no heartbeat ([#317](https://github.com/FHDumont/ai-engineering-team-template/pull/317)) · 2026-11-27
- fix: test the update path from real old origins ([#315](https://github.com/FHDumont/ai-engineering-team-template/pull/315)) · 2026-11-27
- fix: escape the dot in the check-docs method scripts filter ([#296](https://github.com/FHDumont/ai-engineering-team-template/pull/296)) · 2026-11-26
- test: build the files of three tests in a copy, never in the real scripts ([#286](https://github.com/FHDumont/ai-engineering-team-template/pull/286)) · 2026-11-26
- fix: compare the saved review opinion with its own reviewer stop ([#284](https://github.com/FHDumont/ai-engineering-team-template/pull/284)) · 2026-11-25
- test: stop test_setup_repo.sh writing the real required-checks ([#282](https://github.com/FHDumont/ai-engineering-team-template/pull/282)) · 2026-11-25
- test: make the time-based tests robust under machine load ([#276](https://github.com/FHDumont/ai-engineering-team-template/pull/276)) · 2026-11-25
- fix: hash the close-reviewer opinion from its transcript ([#243](https://github.com/FHDumont/ai-engineering-team-template/pull/243)) · 2026-11-24
- feat: time is informative, never a cut for the owner ([#240](https://github.com/FHDumont/ai-engineering-team-template/pull/240)) · 2026-11-24
- fix: apply and notice follow the destination method-diff ([#239](https://github.com/FHDumont/ai-engineering-team-template/pull/239)) · 2026-11-24
- fix: correct phase time, CI reruns, and deadlines ([#176](https://github.com/FHDumont/ai-engineering-team-template/pull/176)) · 2026-11-23
- fix(process): bind merge notes, reviewer text and phase_session ([#170](https://github.com/FHDumont/ai-engineering-team-template/pull/170)) · 2026-11-22
- fix: keep phase cleanup inside the worktree it created ([#167](https://github.com/FHDumont/ai-engineering-team-template/pull/167)) · 2026-11-22
- perf(tests): cut the fixed cost per test and split the largest tests ([#86](https://github.com/FHDumont/ai-engineering-team-template/pull/86)) · 2026-11-22
- perf(tests): split phase-start and hook tests, make the headless test load-proof ([#84](https://github.com/FHDumont/ai-engineering-team-template/pull/84)) · 2026-11-22
- perf(tests): split test_close_phase.sh into parallel files ([#82](https://github.com/FHDumont/ai-engineering-team-template/pull/82)) · 2026-11-22
- feat(close-phase): notes to the headless child and cheap pre-review ([#80](https://github.com/FHDumont/ai-engineering-team-template/pull/80)) · 2026-11-22
- fix: tests never fail by time under load and the orphan scan is cheap ([#77](https://github.com/FHDumont/ai-engineering-team-template/pull/77)) · 2026-11-22
- fix(tests): no process of the method outlives its creator ([#73](https://github.com/FHDumont/ai-engineering-team-template/pull/73)) · 2026-11-21
- fix: detach the headless child from the caller pipes and process group ([#72](https://github.com/FHDumont/ai-engineering-team-template/pull/72)) · 2026-11-21
- fix(phase-start): wait for the workflow run of main before the CI job exists ([#70](https://github.com/FHDumont/ai-engineering-team-template/pull/70)) · 2026-11-21
- fix(ci): run the tests on PRs of generated ROADMAP and CHANGELOG ([#69](https://github.com/FHDumont/ai-engineering-team-template/pull/69)) · 2026-11-21
- docs(process): ask the owner only on sensitive actions ([#60](https://github.com/FHDumont/ai-engineering-team-template/pull/60)) · 2026-11-21
- feat: run the validate.sh test suite in parallel ([#58](https://github.com/FHDumont/ai-engineering-team-template/pull/58)) · 2026-11-21
- perf: faster phase opening and loose spec only for pending phases ([#57](https://github.com/FHDumont/ai-engineering-team-template/pull/57)) · 2026-11-21
- docs: close-reviewer reads the CI Tests check instead of rerunning the suite ([#56](https://github.com/FHDumont/ai-engineering-team-template/pull/56)) · 2026-11-21
- feat(bots): visible authorship header on agent and bot comments ([#38](https://github.com/FHDumont/ai-engineering-team-template/pull/38)) · 2026-11-21
- feat: open phases without the test suite and undo a failed opening ([#30](https://github.com/FHDumont/ai-engineering-team-template/pull/30)) · 2026-11-21
- fix(skills): use unique temp files for PR, issue and review texts ([#28](https://github.com/FHDumont/ai-engineering-team-template/pull/28)) · 2026-11-21
- feat: list BOT_WEBHOOK keys when a bot secret is missing ([#27](https://github.com/FHDumont/ai-engineering-team-template/pull/27)) · 2026-11-21
- feat: name the missing dependency in validate.sh ([#23](https://github.com/FHDumont/ai-engineering-team-template/pull/23)) · 2026-11-21
