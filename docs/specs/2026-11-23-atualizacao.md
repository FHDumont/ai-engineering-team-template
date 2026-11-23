# Spec: atualização e o que não espera (issues #101, #102, #103, #90, #115, #118, #119, #129, #147, #149, #104, #111, #112, #125, #145, #151 e #155)

Acompanhamento na #166. Uma fase, a #101, fecha as dezessete. O grupo F entra nesta fase. Sem alvo novo de produção no deploy (#104 é desenho e script). A #157 continua de fora. Esta fase não implementa o G nem fecha a #166; a gerenciadora abre o G depois do merge.

Modo de fim: end:auto-close.

## Fase #101 — atualizar sem editar o método na mão

Arquivos: os que cada issue nomeia em `scripts/`, `.github/`, `.claude/`, `docs/process-design.md` e `README.md`. Não reabre o portão da #138 nem o prazo da #141.

Pronto quando: a aplicação estende sem editar arquivo do método; ADR, workflow e comentário de bot não colidem com o que é do repo; a atualização sabe o commit de origem, o que revisar no que é do repo, e a revisão cobre o que veio do template; issue copiada não aponta para a issue errada nem nasce com needs-context; o deploy do método tem rollback e prova de imagem no desenho, sem alvo novo; status e filha não pedem ao dono o que é da gerenciadora; arquivar as filhas diz uma coisa só; spec aprovada tem emenda no meio da fase; a trava diz qual comando de leitura barrou.

1. Testes que falham no código anterior, um por issue. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (atualização)
2. A correção, um commit por issue. modelo: sonnet · esforço: medium · motivo: peso medium de scripts/lib/weights.tsv (atualização)
