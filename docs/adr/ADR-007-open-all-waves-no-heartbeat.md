# ADR-007: Todas as ondas abrem no ok da spec, sem batimento

- Situação: vigente
- Data: 27/11/2026
- Fase/PR: fase #308

## Contexto

O dono ficava parado clicando em cartão ou digitando "abrir fase #n". Duas causas: o app recusa o `start_session` em turno que não começou por fala do dono (aviso de subagente, Remote Control), e o batimento da gerenciadora (tarefa recorrente) faz o app recusar todo `start_session` pelo Remote Control (#306). Headless na recusa foi testado de verdade em 26/11/2026: `PROCESS_HEADLESS=on start-headless.sh` logo depois da recusa foi negado pelo classificador do modo auto ("Undermining Oversight"). A espera em segundo plano presa a um pid acorda a sessão sem job agendado (prova de 27/11/2026: o `claude -p` de teste terminou e o aviso de término chegou à sessão em 6 s).

## Decisão

Sem batimento: a gerenciadora acorda pelo fim de turno da filha, pelo aviso de espera em segundo plano e pela fala do dono. No turno do ok da spec ela abre as fases de todas as ondas (`phase-start.sh <n> --after <anterior>`); a filha de onda posterior espera o merge da anterior na `origin/main`, em tarefa de segundo plano própria, e dá `git rebase origin/main` antes da primeira etapa. Headless continua desligado por padrão e o `start-headless.sh` não muda. O cartão é último recurso, e o `--need` pede "abrir a #n" numa mensagem nova, que vale pelo Remote Control. A filha espera o `validate.sh` pelo aviso de término da própria tarefa, nunca por `pgrep -f`, e para as próprias tarefas de shell antes de dizer que não deixou nenhuma (#309).

## Consequências

Mais sessões abertas ao mesmo tempo, esperando; cada uma ocupa uma vaga de fase (o limite continua e fase sem vaga espera). A espera sai por tempo (6 h) e avisa a gerenciadora. O caso do Remote Control só fica provado quando o dono estiver nele numa abertura.
