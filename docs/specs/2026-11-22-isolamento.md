# Spec: isolamento de processo (issues #88, #91, #92, #120, #109 e #126)

Acompanhamento na #166. Uma fase só, a #88, fecha as seis. A #92 entra aqui, e não numa fase paralela: o `--prepare` roda a suíte, e a suíte ainda mata processo alheio ou executa script da aplicação enquanto qualquer uma das quatro (#88, #91, #92, #120) seguir aberta neste worktree.

Modo de fim: `end:auto-close`. Área sensível: `scripts/close-phase.sh`, `scripts/lib/procs.sh`, `scripts/sessions.sh`. Solo.

Ninguém roda `scripts/validate.sh`, `close-phase.sh --cleanup` nem `sessions.sh --close-idle` antes dos commits que corrigem #88, #91, #92 e #120. O teste vermelho usa `ps`, `lsof` e `kill` falsos. Ninguém prova o defeito de verdade. Cada issue fecha com o commit e a prova. Repositório público: nenhum nome de projeto privado.

## Fase #88 — a suíte e a limpeza não saem do que a fase criou

Arquivos previstos: `scripts/lib/procs.sh`, `scripts/sessions.sh`, `scripts/close-phase.sh`, `scripts/tests/test_orphans.sh`, `scripts/tests/test_sessions.sh`, `scripts/tests/test_cleanup.sh`, `scripts/tests/test_misc_scripts.sh`, `scripts/tests/lib.sh`, `.claude/skills/integrate/SKILL.md`, `.claude/skills/close-phase/SKILL.md`, `docs/process-design.md` §6.4, `README.md`.

Pronto quando: o das issues #88, #91, #92, #120, #109 e #126, mais os critérios somados nos comentários. Em especial: nenhum teste sinaliza processo que não criou; `--under` só estreita e pasta fora do repositório sai 2 sem sinal; a suíte percorre uma lista fechada de scripts do método; cada processo encerrado fica no trace antes do sinal; o `gh` não repassa o aviso e a skill proíbe pipe no `--merge` e no `--check`.

1. Teste da #88 que falha em `c1b76da`: `ps` e `lsof` falsos listam dois órfãos criados pelo teste (um em `tmp.*`, outro num worktree apagado) e `procs_cleanup_worktree` sobre um worktree inexistente tem de deixá-los vivos. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (encerra processo)`
2. Correção da #88: o `--cleanup` encerra só o worktree da fase e a filha headless do trace; órfão de fora é no máximo listado. `AI_METHOD_ORPHAN_ROOT`, se continuar, também limita o ramo do worktree apagado. A §6.4 diz o alcance novo. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (encerra processo)`
3. Teste da #91 que falha em `c1b76da`: `--close-idle` sem `--under`, com `ps`, `lsof` e `kill` falsos, e `--under` de pasta fora do repositório sai 2 sem sinal. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (encerra sessão)`
4. Correção da #91: o padrão é o checkout e os worktrees deste repositório; `--under` só estreita, a pasta é canonizada e fora do checkout sai 2 antes de qualquer sinal. A skill `integrate` e a tabela do desenho dizem o alcance. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (encerra sessão)`
5. Teste da #120 que falha em `c1b76da`: `--cleanup` com a saída num pipe cujo outro processo está no worktree termina a limpeza (saída 0, branch local apagada no caso de teste). `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (mata o pipe de quem chamou)`
6. Correção da #120: poupa o grupo ou a sessão de quem chamou e quem só observa; grava no trace, antes do sinal, pid, comando e pasta; o script não repassa o aviso do `gh` e a última linha é o resultado; a skill proíbe pipe no `--merge` e no `--check` e mostra a forma com arquivo. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (caminho sensível)`
7. Teste da #92 que falha em `c1b76da`: um script sentinela em `scripts/` não é executado. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (executa script da aplicação)`
8. Correção da #92: o teste percorre uma lista fechada dos scripts do método. O README avisa para não rodar a suíte antes dessa separação. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (executa script da aplicação)`
9. Teste da #109 que falha em `c1b76da`: `lsof` falso que sai 1 não derruba `sessions.sh`; o caso 4 de `test_orphans.sh` não depende das sessões reais da máquina. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (processo que some na listagem)`
10. Correção da #109: processo que some é pulado e a saída é 0. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (processo que some na listagem)`
11. Teste da #126 que falha em `c1b76da`: o filho `sleep` do `claude` falso sobrevive ao trap. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (órfão do próprio teste)`
12. Correção da #126: o trap encerra os descendentes lidos antes de sinalizar o pai. `modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (órfão do próprio teste)`
