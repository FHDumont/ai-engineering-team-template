---
name: plan
description: Planejamento nível 2 — lê por inteiro só as issues escolhidas na triagem, faz o grilling e escreve uma spec curta por fase com etapas, modelo/esforço/motivo e modo de fim. Use depois da triagem. Frases: "planejar", "planejar a issue", "executar #n", "executar a issue".
---

# Planejar

1. `scripts/setup-repo.sh --offers`: pendente, quadro.
2. Sem issue: grilling, `open-issue.sh`.
3. Leia só as issues escolhidas, `docs/STATE.md`, ADRs.
3a. **Par da sessão:** `light` ou `medium` fica no atual. Com item `strong` (§3) ou ambiguidade: quadro com o par atual e o do peso `strong`.
4. **Grilling único**: issues juntas, só o que muda a spec, quadro por decisão; o resto, suposição. Bot: `ask-bot`. "executar #<n>" cai aqui (também `size:small`, achado e `test`; esta pelo `triage.sh --issue <n>`): sem spec, uma curta.
4a. §2.1: critério verificável, escopo explícito, solução simples.
5. Escreva `docs/specs/AAAA-MM-DD-<group>.md`, seção por fase:
   - issue, objetivo, pronto quando, arquivos;
   - etapas (um commit cada) com `modelo: … · esforço: … · motivo: …`, o par que `scripts/weights.sh <peso>` imprime (`light`, `medium` ou `strong`, §3), nunca de memória;
   - modo de fim, área sensível, solo ou paralela (`integration.md`).
6. Ok da spec: quadro (ou label `approved`). Aplique `end:*` e `group:*`.
7. **Antes de qualquer `start_session`:** linha com o par atual e o da spec; nunca execute aqui. Fecho liberado: passo 6. Abertura: só `scripts/phase-start.sh <n> [<n>…]`; recusa sem spec ou issue fechada, commita a spec e imprime os campos do `start_session`.
   - **Filhas:** no mesmo turno do "executar", um `start_session` por fase, com: `initiation: "user_asked"`, `context: "fresh"`, `use_worktree: false`, `title`, `prompt`, `background`, `model`/`effort` da spec; o fecho vai no brief. O `check-env.sh` da filha confere o par real (§3); divergência avisada: `set_session_model`/`set_session_effort`, e ela roda o `check-env.sh` de novo.
   - **Recusado** (turno sem mensagem do dono): repita com `initiation: "own_initiative"` (cartão) e pare com `status.sh --state esperando`. Nunca subagente.
8. Vira a **gerenciadora**: não edita nem executa; só ela pergunta ao dono e repassa mensagens dele, inclusive "fechar fase". Atrasada: leia o estado da fase. Após o último merge: skill `integrate`.
   - **Batimento:** aberta a primeira filha, crie a tarefa recorrente que o `phase-start.sh` imprime (8 minutos): lê sessões ligadas e PRs e faz o próximo passo; o aviso de fim nem sempre chega. Sem ferramenta: "Você precisa". A `integrate` apaga.
9. Feito: só lido de volta.
10. Fim de turno: saída do `scripts/status.sh`, sem bloco de código.
