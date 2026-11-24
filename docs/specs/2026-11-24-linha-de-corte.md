# Spec: linha de corte da atualização (issues #234, #235, #236, #237, #227)

Grupo paralelo de duas fases, sem arquivo em comum. Modo de fim: end:auto-close. Grupo: linha-de-corte. Objetivo: a próxima atualização `eaeaaea`/`7421a8f` → `main` termina sem ajuste à mão e sem issue nova para o template. Por isso o tempo passa a ser só informativo: não abre quadro nem issue em nenhum repositório. Depois do merge, a gerenciadora repete a prova `eaeaaea` → `main` e `7421a8f` → `main` com os casos das issues e atualiza as issues dos adotantes.

## Fase #234 — uma lista só para o que falta, a aplicar e a juntar

Fecha: #234, #235, #236.

Causa comum: o `--apply` do `fetch-template.sh` decide sozinho o que copia, com o `lib/common.sh` velho do repositório. O `method-diff.sh` decide por outra regra o que falta, e o `--notice` lista como `adapted` o que o template nem mudou.

Arquivos: `scripts/fetch-template.sh`, `scripts/method-diff.sh`, `.github/update-notice.md`, `docs/process-design.md` (só as linhas de `method-diff.sh` e `fetch-template.sh` da tabela de scripts), `scripts/tests/test_fetch_template.sh`, `scripts/tests/test_method_diff.sh`, `scripts/tests/test_update_notice.sh` (se o texto testado mudar). Não toca a §6 do `process-design.md`. Área sensível: nenhuma do dono.

Pronto quando:

- O `--apply` roda o `method-diff.sh` do destino, de `.process/template`, com o `lib` do destino e `REPO_ROOT` no worktree. Ele copia só as linhas `outdated` e `missing`, acrescenta ao fim do `.github/labels.tsv` cada `missing-label` com a linha do destino, roda o `--remove` (`removed` e `template-only`) e termina imprimindo o `--notice`. Ele nunca sobrescreve um `adapted` nem um `repo-owned`. Rodado avulso, com o `common.sh` antigo do repositório, não imprime `command not found`, e a primeira passada copia o mesmo que a segunda (#236).
- Arquivo que a origem e o destino têm, o repositório não tem e não está no `method-files.txt` nem entre os `repo-owned` sai como `deleted`: o repositório o apagou de propósito. Ele não é `missing`, o `--apply` não o recria e o `--notice` não o lista. Exemplos: `deploy-example.yml` e `.github/gh-pin` (#235).
- O `--notice` lista `adapted` só quando o template mudou o arquivo no intervalo (blob da origem diferente do destino) e nunca lista `.github/method-origin` (#234).
- O `.github/update-notice.md` fica curto: o passo único é `scripts/fetch-template.sh <destino> --apply`. Depois vêm só os `adapted` do `--notice`, juntados à mão, o ok do dono sobre o `settings.json` e o `--record-origin`. Ganha a seção **Linha de corte**: a fase de atualização só abre issue no template quando, seguido o guia, o `validate.sh --full` ou o `check-docs.sh` fica vermelho, ou um script do método sai com erro. Ajuste à mão, observação e medida de tempo vão para "Decisões tomadas sem perguntar" do PR e nunca viram issue.
- Testes que falham no código atual:
  - repo na origem sem `deploy-example.yml`, com um `deploy-x.yml` próprio: o `--apply` não recria o exemplo, e o `method-diff.sh` e o `--apply` listam os mesmos faltantes;
  - repo com um `common.sh` sem `is_method_doc`: o `--apply` sai limpo;
  - repo com um `labels.tsv` próprio que o template não mudou no intervalo: o `--notice` não o lista, nem o `method-origin`.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes. A prova nos repos de mentira é da gerenciadora, depois do merge.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. `method-diff.sh`: classe `deleted` e o `--notice` sem `adapted` parado. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
3. `fetch-template.sh --apply` pelo `method-diff.sh` do destino, com labels e `--remove`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
4. Guia `update-notice.md` com o passo único e a linha de corte, mais as linhas da tabela do `process-design.md`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)

## Fase #237 — tempo só informativo

Fecha: #237 e #227. A #227 é fechada pela gerenciadora no fim, com o motivo: o tempo vira informativo, e a meta não muda.

Arquivos: `scripts/machine-slots.sh`, `.claude/skills/integrate/SKILL.md`, `.claude/skills/setup/SKILL.md`, `docs/process-design.md` (só a §6: meta de tempo e prazo de desempenho), `docs/STATE.md` (linha da meta de tempo), `.github/time-targets.tsv` (só o comentário), `scripts/tests/test_machine_slots.sh`, `scripts/tests/test_phase_texts.sh`, `scripts/tests/template/test_readme_adoption.sh` (se a frase testada mudar). Não toca `.github/update-notice.md` nem `scripts/method-diff.sh`. Área sensível: nenhuma do dono.

Pronto quando:

- `machine-slots.sh --report` troca `over-target:` por uma linha `info: time <medida> median <n> s, target <v> <unidade>` por medida, acima ou abaixo da meta, com `(above)` quando passa. A saída é sempre 0.
- A skill `integrate` não abre quadro nem issue por tempo: nem por `over-target`/`info: time`, nem por `over-expected`. Ela cita essas linhas uma vez na mensagem final e segue com o `gen-docs.sh`, o deploy e o `end-check.sh`. Nenhuma skill nem guia manda abrir issue de tempo, no repositório ou no template.
- A skill `setup` não pergunta mais a meta de tempo: o padrão vale, e o dono edita `.github/time-targets.tsv` se quiser. A frase "o dono só é chamado quando o fim do grupo acusa over-target" sai.
- `process-design` §6.4 e o parágrafo do prazo de desempenho dizem que tempo é só informativo, e o `STATE.md` acompanha.
- Teste que falha no código atual: com a meta de 240 s e a mediana de 243 s ou de 300 s, o `--report` dá `info: time validate ...` e nenhuma linha `over-target`. Os testes de texto conferem que a `integrate` não pergunta sobre tempo.
- Prova na parada: `validate.sh` e `check-docs.sh` verdes.

1. Testes que falham no código atual. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
2. `machine-slots.sh --report` informativo. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
3. Skills `integrate` e `setup`, `process-design` §6 e `STATE.md`. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (bug com causa conhecida)
