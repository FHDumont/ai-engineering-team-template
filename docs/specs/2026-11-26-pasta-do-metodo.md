# Spec: scripts do método em .method/scripts/ (issues #269, #288)

Duas fases em sequência, decisão do dono: mover para `.method/scripts/` com um atalho, sem migração automática nos adotantes. Modo de fim de ambas: end:auto-close. Grupo: pasta-do-metodo. A #288 só abre depois do merge da #269: o CI lê os verificadores da base (`base/scripts/...`), que precisa já ter `.method/scripts/`.

## Fase #269 — mover os scripts e deixar o atalho

Fecha: #269. Área sensível: move `scripts/close-phase.sh`, `scripts/ci-gate.sh`, `scripts/check-attribution.sh`, `scripts/check-docs.sh` e `scripts/lib/sensitive_paths.py` (portão); o merge pede o ok do dono, digitado na sessão da fase.

Arquivos: `scripts/` inteiro vira `.method/scripts/` (`git mv`); `scripts` passa a ser um link simbólico versionado para `.method/scripts`; `.github/method-files.txt` e `.github/sensitive-paths` ganham os caminhos novos, mantendo os antigos enquanto o atalho existir; `scripts/lib/common.sh` e o que resolve `HERE` só mudam se o link quebrar a resolução.

Pronto quando:

- `git ls-files scripts` mostra só o link; os 149 arquivos estão em `.method/scripts/`.
- Todo comando de hoje (`scripts/validate.sh`, `scripts/status.sh`, hooks de `.claude/settings.json`, `ci.yml` lendo `base/scripts/...`) segue funcionando pelo link, sem trocar a referência ainda.
- Teste que falha no código atual: `.method/scripts/validate.sh --help` existe e `scripts` é link para `.method/scripts`.
- O `ci.yml` não muda nesta fase (a base ainda tem `scripts/` real).
- Prova na parada: `validate.sh`, `check-docs.sh` e o CI do PR verdes.

1. Teste que falha no código atual. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (arquitetura, portão)
2. `git mv` para `.method/scripts/`, link e manifestos. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (arquitetura, portão)

## Fase #288 — trocar os caminhos e remover o atalho

Fecha: #288. Área sensível: `ci.yml` e os verificadores do portão; o merge pede o ok do dono. Abre só depois do merge da #269.

Arquivos: `.github/workflows/ci.yml` (lê `base/.method/scripts/...`), `.claude/` (hooks, skills, agentes, `settings.json`), `.github/method-files.txt`, `.github/sensitive-paths`, `.github/update-notice.md`, `docs/`, `AGENTS.md`, `CONTEXT.md`, `.method/scripts/` (comentários, `--help`, testes).

Pronto quando:

- `git grep -n "scripts/"` só acha `.method/scripts/` ou menção histórica; o link `scripts` sai do repositório.
- O `update-notice.md` avisa os adotantes da troca manual dos caminhos, com a lista do que muda (sem migração automática).
- Prova na parada: `validate.sh`, `check-docs.sh` e o CI do PR verdes, com o portão lendo `base/.method/scripts/`.

1. Trocar os caminhos em lotes por área (CI, `.claude/`, docs, scripts). modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (arquitetura, portão)
2. Remover o link e escrever o aviso aos adotantes. modelo: sonnet · esforço: medium · motivo: peso strong de scripts/lib/weights.tsv (arquitetura, portão)
