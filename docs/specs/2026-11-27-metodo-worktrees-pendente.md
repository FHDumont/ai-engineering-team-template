# Spec: .worktrees/ não conta como edição pendente na main (issue #335)

Grupo: metodo. Uma fase solo, em `end:auto-close`. Ok do dono no quadro de 27/11/2026 ("executar agora").

Suposições (sem pergunta):

- O `status.sh` desconta `.worktrees/` do aviso do mesmo modo que já desconta `.process/`; o `end-check.sh` não muda e continua acusando o que sobrou no fim do grupo.
- O `setup-repo.sh` só acrescenta ao `.gitignore` as linhas `.worktrees/` e `.process/` que faltam, no fim do arquivo; nunca tira nem reordena linha do repo.

## Fase #335 — status.sh não conta .worktrees/ como edição pendente e o setup garante o .gitignore

Fecha: #335.

Objetivo: num repo adotante cujo `.gitignore` não ignora `.worktrees/`, as paradas deixam de imprimir "há edição de código pendente na main" por causa das pastas do próprio método, e o setup passa a garantir as duas linhas no `.gitignore`.

Arquivos: `.method/scripts/status.sh`, `.method/scripts/setup-repo.sh`, `.method/scripts/tests/test_status.sh` e o teste do `setup-repo.sh`. Área sensível: nenhuma.

Pronto quando:

- Teste que falha no código atual: na `main` de um repo de mentira cujo `.gitignore` não tem `.worktrees/`, com `.worktrees/issue-1/` e `.worktrees/parallel-active.tsv` presentes, o `status.sh` não imprime o aviso; com um arquivo de código não rastreado ao lado, imprime.
- `setup-repo.sh --check` acusa o `.gitignore` sem `.worktrees/` ou sem `.process/`, dizendo a linha que falta; `setup-repo.sh` acrescenta só as que faltam, com teste dos dois casos e de um `.gitignore` que já as tem (nada muda).
- O `end-check.sh` continua acusando worktree e registro que sobraram.
- Prova na parada: `validate.sh`, `check-docs.sh` e a CI do PR verdes.

1. Teste que falha e filtro no `status.sh`. modelo: sonnet · esforço: low · motivo: peso light de .method/scripts/lib/weights.tsv (achado pequeno, mesma linha da #324)
2. Conferência e acréscimo no `setup-repo.sh`, com testes. modelo: sonnet · esforço: medium · motivo: peso medium de .method/scripts/lib/weights.tsv (o --check trava a abertura de fase em todo adotante)
