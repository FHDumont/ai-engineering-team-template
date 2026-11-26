# Integração de fases paralelas

- Cada fase paralela tem branch, worktree e PR próprios e fecha pelo portão sem deploy.
- Fases do mesmo grupo não tocam os mesmos arquivos; se uma precisar de algo da outra, ela vira dependente e sai do paralelo (avise o planejamento).
- Arquivos gerados (`CHANGELOG.md`, `ROADMAP.md`): nenhuma fase gera; a gerenciadora roda `.method/scripts/gen-docs.sh` uma vez, depois do último merge.
- `docs/STATE.md`: a fase muda só a sua parte, e só quando o estado atual mudou.
- O `integrate-parallel.sh` espera todas as fases do registro; a fase que entra sai do registro no `close-phase.sh --cleanup`, e a fase cancelada, no `close-phase.sh --abort`.
- Um build e um deploy por grupo, depois do último merge: o `integrate-parallel.sh` faz o build e a gerenciadora roda o `.method/scripts/deploy.sh` no passo único de fim, depois do `.method/scripts/gen-docs.sh`; ele espera o run e lê o resultado.
- PR em conflito depois do merge de outra fase: a sessão da fase refaz com `.method/scripts/redo-phase.sh`, chamado pelo `close-phase.sh --check` (branch nova da `main`, cherry-pick, PR novo `Closes #n`, PR antigo fechado, branch remota antiga apagada, linha do registro regravada, CI e revisão de novo). Conflito real no cherry-pick (saída 4): a sessão da fase resolve os arquivos e roda o `redo-phase.sh` de novo. PR só atrasado, sem conflito, não é refeito. O `integrate-parallel.sh` só espera.
- Ordem: cada fase entra pelo portão na sua sessão; a gerenciadora espera todas e só no fim o `.method/scripts/deploy.sh` faz o deploy único.
- Espera ou trabalho acima de ~2 min: diga o quê e onde ("revisão local, nada no GitHub"; "aguardando CI run <link>") e cite o run e o estado reais.
- Enquanto a fase é refeita: Estado `trabalhando, refazendo a fase #n sobre a main`; Você precisa: nada.
