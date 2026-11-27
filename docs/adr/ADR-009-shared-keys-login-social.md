# ADR-009: Chaves comuns a várias aplicações ficam em shared/, e o método não interfere na subida

- Situação: vigente
- Data: 27/11/2026
- Fase/PR: fase #337

## Contexto

Uma primeira versão desta fase criou um script que carregava o `.env` na subida das aplicações e grupos declarados por repo. O dono a descartou sem merge: o escopo estava errado. Cada aplicação sobe do próprio jeito, com o próprio `.env`, em qualquer ambiente. Faltava só dizer onde ficam as chaves que a mesma máquina usa em várias aplicações, hoje as de login social.

## Decisão

- O método não interfere na subida de nenhuma aplicação: o `.env` de cada aplicação não muda e nenhum script do método carrega chaves para ela.
- `$DUMONTECH_HOME` (padrão `~/.dumontech`) é do processo de desenvolvimento e do CI/CD: `shared/bots.env` e `projetos/<repo>/.env`.
- Única exceção: chave comum a várias aplicações da máquina fica em `$DUMONTECH_HOME/shared/`, hoje `login-social.env`; no futuro `smtp.env`, `pagamento.env`.
- Formato `NOME=valor`, como o `.env` do repo, com os nomes que as aplicações já usam; pasta 700, arquivo 600.
- Cada aplicação lê o arquivo compartilhado do jeito dela; o `.env` da aplicação vence o compartilhado.
- Regra de uso: o segredo de uma só aplicação fica no `.env` dela; só o mesmo valor em várias aplicações vai para `shared/`.
- Suposição (o dono não fechou): um arquivo por assunto, em vez de um arquivo único.

## Consequências

Nada muda em produção nem no deploy. Quem quiser, lê o compartilhado na aplicação (por exemplo, um `env_file` a mais no compose, antes do `.env` dela); é opcional e de cada repo. O método não cria, não edita e não lê esses arquivos.
