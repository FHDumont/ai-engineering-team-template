# ADR-008: O método tem versões marcadas por tag

- Situação: vigente
- Data: 27/11/2026
- Fase/PR: fase #311

## Contexto

O template não tinha nenhuma tag e recebeu cerca de 100 commits por dia entre 21 e 24/11/2026. O adotante atualizava para a ponta da `main`, e cada correção chegava junto com tudo o que mudou no dia, sem um ponto que se saiba bom.

## Decisão

Usamos tags `vAAAA.MM.DD-N` (data UTC; N conta as tags do dia, desde 1). A tag sai automaticamente no fim de cada grupo, no passo único da skill `integrate`, depois do `end-check.sh` limpo, pelo `.method/scripts/tag-release.sh`, e só quando o check `CI` da ponta da `main` está verde: a CI roda a suíte inteira, inclusive o teste de atualização a partir de origens antigas (fase #310). Sem CI verde o script sai 3 e não cria nada; no mesmo commit não cria uma segunda tag. Só o template marca versão. O `fetch-template.sh` sem destino traz a última tag, escolhida pela data e por N, nunca a ponta; sha ou tag dados explicitamente seguem como são, e o aviso de atualização cita a tag.

## Consequências

O adotante só vê o que passou pela CI. Uma correção urgente espera o fim do grupo, ou o adotante passa o sha à mão. A tag é enviada ao GitHub pelo script, que o `.claude/settings.json` libera por nome (área sensível declarada na spec).
