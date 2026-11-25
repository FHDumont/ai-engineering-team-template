# Spec: correções de scripts (issues #265, #266, #270)

Três fases paralelas, sem arquivo de código em comum. Modo de fim de todas: end:auto-close. Grupo: correcoes-scripts. Depois do merge, a gerenciadora faz o `integrate`.

## Fase #265 — testes de tempo que resistem à carga

Fecha: #265.

Arquivos: `scripts/tests/test_method_diff.sh`, `scripts/tests/test_validate.sh`, `scripts/tests/test_template_only.sh`, `scripts/tests/test_adopted_suite.sh`, `scripts/tests/lib.sh`.

Pronto quando:

- Cada verificação de tempo citada na issue (find-base rápido, série sem espera do limite do parâmetro, template-only) usa uma contagem (chamadas, leituras ou voltas) no lugar do tempo; onde só o tempo serve, o limite é escalado pela carga lida como em `machine-slots.sh`. Nenhum limite absoluto fica solto.
- O que cada teste verifica continua verificado: um teste com a regressão reintroduzida falha.
- Prova na parada: `validate.sh --full` com `AI_METHOD_TEST_JOBS` alto e outro `validate.sh` rodando ao mesmo tempo passa; `check-docs.sh` verde.

1. Trocar o tempo por contagem nos três testes, com a regressão reintroduzida a falhar. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (causa conhecida, três arquivos de teste)
2. Prova sob carga. modelo: sonnet · esforço: light · motivo: só roda e lê o resultado

## Fase #266 — o `--append` da pergunta espera só resposta nova

Fecha: #266.

Arquivos: `scripts/ask-*.sh` (o script de pergunta, a opção `--append`), `scripts/wait-reply.sh` e os testes de ambos em `scripts/tests/`. Os testes usam o `gh` falso, sem rede nem segredo.

Pronto quando:

- Teste que falha no código atual: pergunta, resposta do bot, `--append`; a espera do append não aceita a resposta anterior e só termina com um comentário `reply-to` posterior ao `<!-- ask-append:<bot>:<id> -->`.
- O `wait-reply.sh` ganha `--after <id do comentário>` (suposição: marcador do append, sem mudar o protocolo do bot); o o `--append` do script de pergunta o usa. `--help` de ambos atualizado.
- Sem `--append`, o comportamento é o de hoje.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. `--after` no `wait-reply.sh` e uso no `--append`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #270 — deploy não repete o validate com CI verde

Fecha: #270 (a parte do template). Área sensível: `.github/workflows` e `check-workflows.py`; o merge pede o ok do dono.

Arquivos: `scripts/check-workflows.py`, `scripts/tests/test_workflow_tools.py`, `docs/process-design.md` (§9.4), o aviso de atualização do método, `.github/workflows/deploy-example.yml` só se a regra exigir.

Pronto quando:

- O `check-workflows.py` reprova um `deploy-*.yml` que roda `scripts/validate.sh` sempre, sem gate de CI do SHA ou da mesma árvore (`ci-already-green.sh`), com teste que falha no código atual.
- Aceita o padrão do `deploy-example.yml` (gate e `validate.sh` só com `skip != true`) e o caminho de emergência (suíte completa se o CI não está verde).
- O §9.4 e o aviso de atualização pedem o gate e `permissions: checks: read` nos `deploy-*.yml` próprios dos adotantes.
- Uma issue aberta em FHDumont/fernando-com-br cobre `deploy-site.yml` e `deploy-religiao.yml`. A fase não edita o outro repo.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes. Pós-merge: a meta "deploy abaixo de 3 min" só se prova no fernando-com-br; a #270 fica aberta até essa prova.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (workflows, caminho sensível)
2. Regra no `check-workflows.py`, §9.4 e aviso de atualização. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (workflows, caminho sensível)
3. Issue no fernando-com-br com os dois workflows e os números da #270. modelo: sonnet · esforço: low · motivo: peso light de scripts/lib/weights.tsv (texto)
