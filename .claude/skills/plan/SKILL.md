---
name: plan
description: Planejamento nível 2 — lê por inteiro só as issues escolhidas na triagem, faz o grilling e escreve uma spec curta por fase com etapas, modelo/esforço/motivo e modo de fim. Frases: "planejar", "planejar a issue", "executar #n", "executar a issue".
---

# Planejar

1. `scripts/setup-repo.sh --offers`: pendente, quadro.
2. Sem issue: grilling e `open-issue.sh`.
3. Leia só as issues escolhidas, `docs/STATE.md`, ADRs.
3a. **Par da sessão:** `light` ou `medium` fica no atual. Com item `strong`: quadro com o par atual e o do peso `strong`.
4. **Grilling único**: issues juntas, só o que muda a spec, num quadro só. Até 4 perguntas por quadro; acima disso, quadros seguidos no mesmo turno. O resto, suposição. "executar #<n>" cai aqui: sem spec, uma curta.
4a. §2.1: critério verificável.
5. Escreva `docs/specs/AAAA-MM-DD-<group>.md`, seção por fase:
   - issue, objetivo, pronto quando, arquivos;
   - etapas com `modelo: … · esforço: … · motivo: …` (`scripts/weights.sh <peso>`);
   - modo de fim, área sensível, solo ou paralela (`integration.md`).
5b. Lab-test: a spec separa a prova da parada, a do fecho e a do pós-merge. O brief não pede na parada prova que só existe depois. Pós-merge escreve "issue fica aberta até a prova".
6. Ok da spec: quadro (ou label `approved`). Aplique `end:*` e `group:*`.
7. **Antes de `start_session`:** linha com o par atual e o da spec; nunca execute aqui. Abertura: só `scripts/phase-start.sh <n> [<n>…]`.
   - **Filhas:** no mesmo turno do "executar", um `start_session` por fase, com: `initiation: "user_asked"`, `context: "fresh"`, `use_worktree: false`, `title`, `prompt`, `background`, `model`/`effort` da spec. O `check-env.sh` confere.
   - **Batimento, depois das filhas:** só com `list_sessions` mostrando filha rodando. 4 minutos: faz o próximo passo; só escreve, com o bloco, se o estado mudou. apague o batimento neste turno; volta a trabalhar. sem "Sem mudança.".
   - **Sem vaga**: o `phase-start.sh` espera; nunca cartão por vaga.
   - **Recusado**: `initiation: "own_initiative"` (cartão) ou esperar; pare com o `--state esperando --need` do `phase-start.sh` (título exato e onde: "na barra lateral, dentro do agrupamento da sessão principal; se não aparecer, abra o agrupamento"). Headless só se o dono ligou; nunca subagente.
8. Vira a **gerenciadora**: não edita; nunca `cd` no worktree (`git -C`, caminho absoluto); só ela pergunta ao dono e repassa "fechar fase". Segurar o merge é comentário `Para: fase #n` na issue. Depois: skill `integrate`.
9. Feito: só lido.
10. Fim de turno: saída do `status.sh`, sem bloco de código.
