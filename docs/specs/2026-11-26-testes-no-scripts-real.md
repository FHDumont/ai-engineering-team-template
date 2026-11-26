# Spec: testes que escrevem em scripts/ real (issue #281)

Fase solo, achada na #272. Modo de fim: end:auto-close. Grupo: testes-no-scripts-real.

## Fase #281 — cada teste cria seus arquivos numa cópia

Fecha: #281.

Arquivos: `scripts/tests/test_phase_start_slots.sh`, `scripts/tests/test_settings_allow.sh`, `scripts/tests/test_machine_slots.sh` (e `scripts/tests/lib.sh` só se faltar um auxiliar de cópia).

Pronto quando:

- Os três testes criam e removem seus arquivos temporários numa cópia feita com `copy_scripts`, nunca em `scripts/` real; um teste ou guarda falha no código antigo se um deles volta a escrever em `scripts/` real.
- `test_machine_slots.sh` não conta execuções de outro teste concorrente (1 execução, não 2).
- Prova na parada: duas rodadas seguidas de `validate.sh --full` com `AI_METHOD_TEST_JOBS` alto e outro `validate.sh` ao mesmo tempo passam; `check-docs.sh` verde.

1. Guarda que falha no código antigo e a cópia nos três testes. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (causa conhecida, três testes)
2. Prova sob carga, duas rodadas. modelo: sonnet · esforço: light · motivo: só roda e lê o resultado
