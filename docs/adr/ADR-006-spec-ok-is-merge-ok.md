# ADR-006: O ok da spec que declara a área sensível vale como ok do merge

- Situação: vigente
- Data: 26/11/2026
- Fase/PR: fase #307

## Contexto

O dono aprova a spec, que já nomeia a área sensível que a fase toca (`Área sensível:`). Mesmo assim a filha abria um segundo quadro no merge, e "o ok do dono não atravessa sessões" deixava a fase parada. Decisão do dono no grilling da fase #307.

## Decisão

O ok da spec aprovada (quadro ou label `approved` na issue da fase) vale como ok do merge para a área que ela declara. O `close-phase.sh --prepare` grava `spec_ok` no trace (SHA do HEAD, palavras declaradas na linha `Área sensível:` da seção `## Fase #n`). O `--merge` dispensa o quadro quando cada caminho `owner-ok` tocado e cada label de área sensível estão entre as palavras declaradas, para aquele HEAD. As palavras vêm da spec em `origin/main`, o texto que o dono aprovou: spec só na branch, ou linha editada na branch, não declara nada. O `needs-owner-ok` sozinho, sem caminho nem área por trás, não é coberto. Caminho ou área não declarado sai 5 e o quadro continua. `--abort --discard` continua pedindo o ok. A classe `gate` não muda: segue pedindo o segundo parecer do `close-reviewer`.

## Consequências

Menos um quadro por fase sensível. O ok vale só para o HEAD gravado: commit novo exige novo `--prepare`. A spec precisa declarar a área com as palavras certas (caminho, nome do arquivo ou label); declaração vaga não cobre nada. Palavra sem diretório (`AGENTS.md`) cobre o arquivo de mesmo nome em qualquer pasta. O trace é local à sessão que roda o portão, como os demais eventos.
