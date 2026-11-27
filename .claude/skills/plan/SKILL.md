---
name: plan
description: Planejamento nível 2 — lê por inteiro só as issues escolhidas na triagem, faz o grilling e escreve uma spec curta por fase com etapas, modelo/esforço/motivo e modo de fim. Frases: "planejar", "planejar a issue", "executar #n", "executar a issue".
---

# Planejar

1. `.method/scripts/setup-repo.sh --offers`: pendente, quadro.
2. Sem issue: grilling e `open-issue.sh`.
3. Leia só as issues escolhidas, `docs/STATE.md`, ADRs.
3a. **Par da sessão:** `light`/`medium` fica no atual; `strong`: quadro com os dois pares.
4. **Grilling único**: issues juntas, só o que muda a spec, num quadro só. Até 4 perguntas por quadro; acima disso, quadros seguidos no mesmo turno. O resto, suposição. "executar #<n>" cai aqui: sem spec, uma curta.
4a. §2.1: critério verificável.
5. Escreva `docs/specs/AAAA-MM-DD-<group>.md`, seção por fase:
   - issue, objetivo, pronto quando, arquivos;
   - etapas com `modelo: … · esforço: … · motivo: …` (`.method/scripts/weights.sh <peso>`);
   - modo de fim, área sensível, solo ou paralela (`integration.md`).
5b. Lab-test: a spec separa a prova da parada, a do fecho e a do pós-merge. O brief não pede na parada prova que só existe depois. Pós-merge escreve "issue fica aberta até a prova".
6. Ok da spec: quadro (ou label `approved`). Aplique `end:*` e `group:*`.
7. **Antes de `start_session`:** linha com o par atual e o da spec; nunca execute aqui. Abertura: só `.method/scripts/phase-start.sh <n> [<n>…]`.
   - **Filhas:** no mesmo turno do "executar", um `start_session` por fase, com: `initiation: "user_asked"`, `context: "fresh"`, `use_worktree: false`, `title`, `prompt`, `background`, `model`/`effort` da spec. O `check-env.sh` confere.
   - **Sem batimento, todas as ondas no ok:** nada recorrente; o fim de turno da filha acorda a gerenciadora. Abra as ondas no turno do ok: `phase-start.sh <n> --after <anterior>`, colando no `background` o texto que ele imprime (a filha espera o merge em tarefa própria).
   - **Sem vaga**: `phase-start.sh` espera; nunca cartão por vaga. Faltando: ondas; pendente: cartão ou batimento. Acima: 76.
   - **Recusado** (último recurso): `initiation: "own_initiative"` (cartão); pare com `--state esperando --need` do `phase-start.sh` ("abrir a #n" numa mensagem nova, vale pelo Remote Control). Headless só se o dono ligou; nunca subagente.
8. Vira a **gerenciadora**: não edita; nunca `cd` no worktree (`git -C`, caminho absoluto); só ela pergunta ao dono e repassa "fechar fase". Segurar o merge é comentário `Para: fase #n` na issue. Depois: skill `integrate`.
9. Feito: só lido.
10. Fim de turno: saída do `status.sh`, sem bloco de código.
