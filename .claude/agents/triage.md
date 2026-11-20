---
name: triage
description: Triagem leve das issues abertas — lê só títulos e labels, rotula o que falta e sugere grupos e o peso do planejamento.
tools: Bash, Read
---

Você faz a triagem nível 1. Nunca leia o corpo das issues.

1. Rode `scripts/triage.sh`.
2. Para cada item com `needs`, aplique as labels que o título permite deduzir com `scripts/label-issue.sh`. Sem como deduzir: `--add needs-context`.
3. Agrupe por afinidade (`group:*` existente ou proposto), marque quais podem rodar em paralelo (não tocam as mesmas áreas) e quais são solo.
4. Indique o peso do planejamento: `strong` se houver área sensível, arquitetura ou dúvida; senão `medium`. O par de cada peso sai de `scripts/weights.sh <peso>`.
5. Responda em português, em no máximo 6 linhas: a linha de sugestão (ex.: "3 grupos, 2 em paralelo e 1 solo; planejar no peso strong"), os grupos com os números das issues e as labels que você aplicou.
