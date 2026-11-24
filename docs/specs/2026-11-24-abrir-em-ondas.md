# Spec: abrir o grupo em ondas quando faltam vagas (issue #249)

Fase solo, aberta depois do merge de #246 (mesmos arquivos: `phase-start.sh`, `open-parallel.sh`, `test_phase_start_slots.sh`). Modo de fim: end:auto-close. Grupo: abrir-em-ondas.

## Fase #249 — o grupo abre com as vagas que houver

Fecha: #249.

Arquivos: `scripts/phase-start.sh`, `scripts/open-parallel.sh`, `scripts/integrate-parallel.sh`, `scripts/tests/test_phase_start_slots.sh` (e o teste do `integrate-parallel.sh`), `.claude/skills/plan/SKILL.md`, `.claude/skills/integrate/SKILL.md`. Área sensível: nenhuma.

Suposições (sem grilling, passo reversível):

- O registro `.worktrees/parallel-active.tsv` ganha a linha da pendente com branch e caminho vazios (ou um marcador `pending`); o executor escolhe o formato e o lê de volta em todos os leitores do registro.
- Grupo de N issues com N acima do limite segue saindo 76, como #246 deixou.
- O batimento da gerenciadora (texto impresso pelo `phase-start.sh`) ganha o passo de abrir a pendente quando há vaga; a sessão filha dela pode virar cartão, e a skill `plan` diz isso.

Pronto quando:

- Com limite 3, 1 vaga livre e 3 fases pedidas, o `phase-start.sh` abre 1 fase, registra as 3 no grupo (2 pendentes), sai 0 e imprime as pendentes e o comando para abri-las.
- Sem vaga nenhuma, o comportamento de hoje fica (espera até o prazo e sai 75 sem criar nada).
- Uma segunda chamada `phase-start.sh <pendente>` com vaga livre abre a pendente no mesmo grupo, sem recusar o registro por "leftover".
- `integrate-parallel.sh` não dá o grupo por integrado enquanto houver linha pendente.
- Teste que falha no código atual para o primeiro item.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Teste que falha no código atual (1 vaga, 3 fases). modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (comportamento novo em script do método)
2. Abertura parcial e pendentes no registro (`open-parallel.sh`, `phase-start.sh`). modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (comportamento novo em script do método)
3. `integrate-parallel.sh` espera as pendentes e o texto do batimento e das skills. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (comportamento novo em script do método)
