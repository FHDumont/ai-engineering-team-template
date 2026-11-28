# Spec: origem curta, guia de adoção e log no progresso (issues #340, #341, #342)

Grupo: adotantes-e-progresso. Três fases em paralelo, todas em `end:auto-close`. Nenhuma compartilha arquivo de código com outra.

Ok do dono (28/11/2026): "Aprovar e executar" no quadro desta spec, com o pedido de seguir até o fim sem mais perguntas. Nenhuma fase toca caminho `owner-ok`. A fase #342 pode tocar `.method/scripts/close-phase.sh` (classe `gate`: segunda opinião do `close-reviewer`, sem o dono).

Suposições (sem pergunta; cada fase repete as suas em "Decisões tomadas sem perguntar" no PR):

- #340: prioridade alta, como a issue sugere (a triagem pôs `medium` só pelo título).
- #341, `method-origin`: o guia passa a mandar gravar a origem antes da validação; o `check-docs.sh` não muda (é verificador e caminho `gate`, e a tabela de arquivos continua valendo para todo repo).
- #341, `sensitive-paths`: os testes passam a usar uma lista própria deles, para o guia continuar dizendo "troque os globs".
- #341 fecha em `auto-close` (a issue não sugere fim; é texto de guia e teste).
- #342: os campos novos (`log`, `parent_pid`) são opcionais; o pedido do comentário (`parent_pid`) entra na mesma fase.

## Fase #340 — fetch-template.sh --apply resolve a origem curta de method-origin

Fecha: #340. Paralela.

Objetivo: o `--apply` usa a origem de `.github/method-origin` também quando ela é um SHA curto, e nunca cai em `--from <destino>` em silêncio.

Arquivos: `.method/scripts/fetch-template.sh` (o bloco que lê `.github/method-origin`), `.method/scripts/tests/test_fetch_template.sh` (ou um teste novo ao lado). Sem área sensível.

Pronto quando:

- Um teste novo monta um adotante falso com `method-origin` curto e falha no código antigo (nada copiado, tudo `adapted`); o commit do teste vem antes do da correção, ou a saída vermelha fica citada no PR.
- A origem curta é resolvida contra as branches do template, como o destino curto.
- Origem que não resolve é erro (saída diferente de 0) com o comando para corrigir (`setup-repo.sh --record-origin <sha>` ou `method-diff.sh --find-base`), sem diff com `--from` igual ao destino.
- `method-origin` vazio ou `template` continuam como hoje.
- Prova na parada: `validate.sh`, `check-docs.sh` e a CI do PR verdes.

1. Teste que falha e correção do bloco da origem. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #341 — a adoção pelo guia passa na validação sem ajuste à mão

Fecha: #341. Paralela.

Objetivo: quem segue "Adotar num repositório que já existe" do `README.md` chega ao passo da validação com `check-docs.sh` e a suíte verdes, mesmo trocando os globs de `.github/sensitive-paths`.

Arquivos: `README.md` (seção de adoção), `.method/scripts/tests/test_workflow_tools.py`, `.method/scripts/tests/test_close_phase_paths.sh` e, se precisar, um arquivo de lista de teste em `.method/scripts/tests/`. Não toca `.method/scripts/check-docs.sh` nem `.github/sensitive-paths`. Sem área sensível.

Pronto quando:

- O guia manda gravar `.github/method-origin` (`.method/scripts/setup-repo.sh --record-origin <sha>`) antes do passo da validação, e o passo que citava a gravação depois do merge não contradiz isso.
- Os testes citados na issue (`test_classes_of_the_list`, `test_repo_globs`, `test_policy_gate_paths_get_needs_gate_review_not_owner_ok`, `test_policy_sees_renamed_and_accented_sensitive_paths`, `test_close_phase_paths.sh`) usam uma lista própria e passam com um `.github/sensitive-paths` do repo sem os globs de exemplo. Prova: rodar esses testes com o arquivo do repo trocado por uma lista sem `**/auth/**`, `db/migrations/**` e os lockfiles, e citar a saída no PR (o arquivo volta ao original; não entra no diff).
- O comportamento da lista real do repo continua coberto por pelo menos um teste (as linhas `gate` do próprio método: `ci.yml`, `close-phase.sh`, `check-docs.sh`).
- Prova na parada: `validate.sh`, `check-docs.sh` e a CI do PR verdes.

1. Testes com lista própria. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (mudança de teste com regra do portão por trás)
2. Guia de adoção no `README.md`. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (texto que os agentes dos adotantes seguem ao pé da letra)

## Fase #342 — o evento de progresso leva o caminho do log e o pid do pai

Fecha: #342. Paralela.

Objetivo: quem lê `~/.cache/ai-method/progress/` acha a saída completa do script (ao vivo e depois de uma falha) e monta a árvore de chamadas sem inferir pelo tempo.

Arquivos: `.method/scripts/lib/progress.sh`, `.method/scripts/progress.sh`, `.method/scripts/validate.sh`, `.method/scripts/tests/test_progress.sh`, `docs/process-design.md` §6.4. Prefira resolver na lib e no `validate.sh`; `.method/scripts/close-phase.sh` e `.method/scripts/phase-start.sh` só entram se tiverem saída longa própria que não fique no log de quem eles chamam. Área sensível: `.method/scripts/close-phase.sh` (classe `gate`), só se for tocado; nesse caso a mudança é só de registro de progresso e não muda nenhuma regra do portão.

Pronto quando:

- A saída do `validate.sh` vai para `~/.cache/ai-method/logs/<repo>-<issue>-<script>-<pid>.log` (`AI_METHOD_CACHE` vale também aqui), e os eventos `start`, `end` e `fail` levam o campo `log` com o caminho absoluto. Script sem log não leva o campo.
- Os eventos levam `parent_pid` com o pid do script do método que chamou este, quando houver (variável exportada pela lib; ex.: `close-phase.sh` → `validate.sh`). Sem pai do método, o campo não aparece.
- Os logs intocados há mais de 7 dias somem na mesma poda do progresso.
- O que o agente vê na saída dos scripts não muda (resultado curto; em falha, o mesmo trecho de hoje).
- `test_progress.sh` cobre `log`, `parent_pid`, a poda dos logs e um evento sem os campos novos (consumidor atual não quebra; `progress.sh` mostra os eventos antigos e os novos).
- `docs/process-design.md` §6.4 descreve os dois campos, o caminho do log e a retenção; `docs/STATE.md` (linha "Progresso") cita o log.
- Prova na parada: `validate.sh`, `check-docs.sh` e a CI do PR verdes.

1. Lib, `validate.sh` e teste. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (feature comum em script com teste)
2. `process-design` §6.4 e `docs/STATE.md`. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (formato que ferramentas de fora leem)
