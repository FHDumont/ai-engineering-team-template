# Spec: hash do parecer pelo texto do parecer (issue #241)

Fase solo, achada no fim do grupo linha-de-corte. Modo de fim: end:auto-close. Grupo: linha-de-corte. Depois do merge, a gerenciadora faz a prova da atualização nos repos de mentira e avisa os adotantes.

## Fase #241 — o hash do close-reviewer é o do parecer

Fecha: #241.

Arquivos: `.claude/hooks/trace-event.sh`, `.claude/agents/close-reviewer.md`, `.claude/hooks/tests/test_trace_event.sh`. Área sensível: `.claude/hooks/` (classe `owner-ok`): o merge pede o ok do dono, digitado na sessão da fase.

Pronto quando:

- No `SubagentStop` do `close-reviewer`, o hook grava em `output_sha` o hash do último texto do revisor que tem uma linha começando por `Veredito:`. Ele lê a transcrição do subagente (`agent_transcript_path`, ou o caminho derivado de `transcript_path` e `agent_id`, como o hook já faz para o modelo). Conta tanto um bloco de texto do assistente quanto o campo `message` de uma ferramenta que entrega o relatório. Sem esse texto, vale o `last_assistant_message`, como hoje.
- O `close-reviewer.md` diz que a última mensagem é o parecer inteiro, sem nada depois e sem tarefa em segundo plano.
- Teste que falha no código atual: uma transcrição em que o parecer vem seguido de uma frase curta. O `output_sha` é o do parecer, e o `close-phase.sh` aceita o parecer salvo literal.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. A correção no hook e a regra no `close-reviewer.md`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
