# Spec: recado para a filha headless e pré-revisão barata (issues #74 e #75)

Fase solo do grupo `estrutura`, `end:auto-close`, em paralelo com a #71 (sem arquivo em comum). Pedido do dono: entrar antes de liberar os repos, porque cada melhoria depois da liberação vira uma nova atualização em cada repo.

## Fase #74 — recados e pré-revisão

Arquivos previstos: `.claude/skills/execute/SKILL.md` (#74), `.claude/skills/close-phase/SKILL.md` (#75), `.claude/agents/close-reviewer.md` (#75), `scripts/close-phase.sh` (a recusa do `--merge` com recado pendente, da #74, e o aviso do `--prepare` sem `pre_review`, da #75), `scripts/tests/` (teste de textos e do `close-phase.sh`), `docs/process-design.md` §10.2. Não toca `scripts/tests/lib.sh`, `scripts/tests/test_validate.sh` nem `scripts/lib/machine-limits.env.example` (são da #71).

Pronto quando: o das issues #74 e #75. O PR fecha #74 e #75.

1. #74: a filha headless lê, antes de cada etapa e antes do `--merge`, os comentários novos da issue com o cabeçalho `Para: fase #n`; o `--merge` recusa com recado sem resposta. Com testes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (close-phase.sh é caminho sensível)`
2. #75: pré-revisão do `close-reviewer` só com a issue e o diff, antes do `--prepare`, registrada no trace como `pre_review`; aviso no `--prepare` sem ela. Com testes. `modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (portão do merge)`
3. Textos das skills, do agente e do `process-design` §10.2. `modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv`
