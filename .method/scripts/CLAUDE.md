# Regras da pasta scripts/

- Todo script tem `--help` (o bloco de comentário do topo), um teste em `scripts/tests/test_*.sh|py` e comentários em inglês. Saída e mensagens em inglês, curtas, para a IA ler.
- Texto e YAML em Python (só biblioteca padrão; YAML via `yq`); o resto em Bash compatível com bash 3.2 (macOS): nada de `mapfile`, arrays associativos ou `${var,,}`.
- Um nome por ferramenta: nada de `.sh` que só chama um `.py`. Código comum em `scripts/lib/`.
- Testes não usam rede: o `gh` é o falso de `scripts/tests/fakes/gh`, com um handler por teste (`use_fake_gh`).
- Teste que precisa dos scripts num repo temporário copia com `copy_scripts` (`scripts/tests/lib.sh`), que troca `validate.sh` e `check-docs.sh` por stubs; o `validate.sh` recusa (saída 3) ser chamado de dentro dos próprios testes.
- Rode `scripts/validate.sh` antes de commitar; o shellcheck só roda ali.
