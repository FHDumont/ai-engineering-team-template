---
name: plan
description: Planejamento nível 2 — lê por inteiro só as issues escolhidas na triagem, faz o grilling e escreve uma spec curta por fase com etapas, modelo/esforço/motivo e modo de fim. Use depois da triagem. Frases: "planejar", "planejar a issue", "executar #n", "executar a issue".
---

# Planejar

1. `scripts/setup-repo.sh --offers`: pendente vai num quadro.
2. Sem issue: grilling, `open-issue.sh`.
3. Leia só as issues escolhidas, `docs/STATE.md` e as ADRs.
3a. **Par da sessão:** `light` ou `medium` fica no atual. Com item `strong` (§3) ou ambiguidade: quadro com o par atual e o do peso `strong`.
4. **Grilling único**: pergunte das issues juntas, só o que muda a spec, um quadro por decisão; o resto, suposição. Bot: `ask-bot`. "executar #<n>" sempre cai aqui (também `size:small`, achado e `test`; esta pelo `triage.sh --issue <n>`): sem spec, uma curta na hora.
4a. §2.1: critério verificável, escopo explícito, solução simples.
5. Escreva `docs/specs/AAAA-MM-DD-<group>.md`, uma seção por fase:
   - issue, objetivo, pronto quando verificável, arquivos previstos;
   - etapas (um commit cada) com `modelo: … · esforço: … · motivo: …`, o par que `scripts/weights.sh <peso>` imprime para o peso da etapa (`light`, `medium` ou `strong`, §3); nenhum par é escrito de memória;
   - modo de fim, área sensível, solo ou paralela (`integration.md`).
6. Ok da spec num quadro (ou label `approved`). Aplique `end:*` e `group:*`.
7. **Antes de qualquer `start_session`:** linha com o par atual e o da spec; nunca execute aqui. Fecho liberado: passo 6. Abertura: só `scripts/phase-start.sh <n> [<n>…]`; ele recusa sem spec ou issue fechada, commita a spec e imprime os campos do `start_session`.
   - **Filhas:** no mesmo turno do "executar", um `start_session` por fase, com: `initiation: "user_asked"`, `context: "fresh"`, `use_worktree: false`, `title`, `prompt`, `background`, `model`/`effort` da spec; o fecho vai no brief. O `check-env.sh` da filha confere o par real (§3); ela avisou divergência: `set_session_model`/`set_session_effort`, e ela roda o `check-env.sh` de novo.
   - **Recusado** (turno sem mensagem do dono): repita com `initiation: "own_initiative"` (cartão que o dono abre) e pare com `status.sh --state esperando`. Nunca subagente.
8. Vira a **gerenciadora**: não edita nem executa; só ela pergunta ao dono e repassa as mensagens dele, inclusive "fechar fase". Atrasada: leia o estado da fase. Após o último merge: skill `integrate`.
9. Verificar: só após ler de volta.
10. Mensagem final de turno: saída de `scripts/status.sh` como está, fora de bloco de código.
