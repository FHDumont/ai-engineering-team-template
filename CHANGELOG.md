# Changelog

<!-- Gerado por scripts/gen-changelog.py; não editar à mão. -->

## Funcionalidades

- feat(setup): ask the time target and the machine limits in setup ([#64](https://github.com/FHDumont/ai-engineering-team-template/pull/64)) · 2026-11-21
- feat(scripts): per-project time targets, lab-test without owner scripts, close-phase progress ([#51](https://github.com/FHDumont/ai-engineering-team-template/pull/51)) · 2026-11-21
- feat(scripts): visible progress of long scripts, headless spec from worktree, CI read failure ([#49](https://github.com/FHDumont/ai-engineering-team-template/pull/49)) · 2026-11-21
- feat: heartbeat only writes when the state changed ([#21](https://github.com/FHDumont/ai-engineering-team-template/pull/21)) · 2026-11-21
- feat: unprotected branch mode for private repos on a free plan ([#14](https://github.com/FHDumont/ai-engineering-team-template/pull/14)) · 2026-11-21
- feat: require the repository setup before a phase or an issue ([#5](https://github.com/FHDumont/ai-engineering-team-template/pull/5)) · 2026-11-21
- docs: add the adoption chapter to the README ([#2](https://github.com/FHDumont/ai-engineering-team-template/pull/2)) · 2026-11-21

## Correções

- feat(ci): run CI on push to main and let phase-start wait for it ([#61](https://github.com/FHDumont/ai-engineering-team-template/pull/61)) · 2026-11-21
- fix: accept a main base without CI when its merged PR had green CI and the same tree ([#37](https://github.com/FHDumont/ai-engineering-team-template/pull/37)) · 2026-11-21

## Manutenção

- perf: measure phase time and cut the CI and prepare reruns ([#48](https://github.com/FHDumont/ai-engineering-team-template/pull/48)) · 2026-11-21
- feat: stop leftover processes and add sessions.sh at the end of a phase ([#25](https://github.com/FHDumont/ai-engineering-team-template/pull/25)) · 2026-11-21
- feat: machine-wide slots, queue and history for validations and phases ([#15](https://github.com/FHDumont/ai-engineering-team-template/pull/15)) · 2026-11-21
- feat: open phase children as headless claude when start_session is refused ([#13](https://github.com/FHDumont/ai-engineering-team-template/pull/13)) · 2026-11-21

## Outros

- docs(process): ask the owner only on sensitive actions ([#60](https://github.com/FHDumont/ai-engineering-team-template/pull/60)) · 2026-11-21
- feat: run the validate.sh test suite in parallel ([#58](https://github.com/FHDumont/ai-engineering-team-template/pull/58)) · 2026-11-21
- perf: faster phase opening and loose spec only for pending phases ([#57](https://github.com/FHDumont/ai-engineering-team-template/pull/57)) · 2026-11-21
- docs: close-reviewer reads the CI Tests check instead of rerunning the suite ([#56](https://github.com/FHDumont/ai-engineering-team-template/pull/56)) · 2026-11-21
- feat(bots): visible authorship header on agent and bot comments ([#38](https://github.com/FHDumont/ai-engineering-team-template/pull/38)) · 2026-11-21
- feat: open phases without the test suite and undo a failed opening ([#30](https://github.com/FHDumont/ai-engineering-team-template/pull/30)) · 2026-11-21
- fix(skills): use unique temp files for PR, issue and review texts ([#28](https://github.com/FHDumont/ai-engineering-team-template/pull/28)) · 2026-11-21
- feat: list BOT_WEBHOOK keys when a bot secret is missing ([#27](https://github.com/FHDumont/ai-engineering-team-template/pull/27)) · 2026-11-21
- feat: name the missing dependency in validate.sh ([#23](https://github.com/FHDumont/ai-engineering-team-template/pull/23)) · 2026-11-21
