# Notas de versão

O que mudou em cada geração do app. Os APKs para instalar no Android ficam em
[Releases](https://github.com/Mouretz/app-barber-java/releases).

Cada vez que o workflow **CortaAqui APK** roda na `main` (ou na mão, em Actions),
sai uma release `cortaaqui-apk-N` com dois arquivos, em modo mock (sem servidor):

- `CortaAqui-cliente.apk` — quem marca o horário
- `CortaAqui-casa.apk` — gerente e profissional

A versão no `pubspec` continua `0.1.0+1` até a primeira tela de verdade. O número
que importa para baixar é o da release.

## App Cliente — cadastrar o próprio telefone

O app não abre mais com o telefone do João preenchido.

- Sem número salvo, o Início e o Menu mostram **Cadastrar telefone**.
- A pessoa digita o nome e o celular dela. Nada vem mockado.
- O número do João e o do Rafael continuam no seed, presos a outro aparelho. Se alguém digitar esses números no agendamento, a barbearia recusa.

## cortaaqui-apk-21 — app Cliente (22 out 2026)

Este é o APK para testar o MVP do cliente. Saiu do merge do
[PR #9](https://github.com/Mouretz/app-barber-java/pull/9).
Baixar: [cortaaqui-apk-21](https://github.com/Mouretz/app-barber-java/releases/tag/cortaaqui-apk-21).

No `CortaAqui-cliente.apk`, em modo mock, sem servidor:

- Menu de baixo: Início, Horários e Menu.
- Introdução na primeira abertura.
- Escolher a barbearia, o serviço, o profissional, o dia e o horário.
- Continuar, confirmar nome e telefone, e ver "Horário marcado".
- Os horários ficam na aba Horários. Dá para cancelar até 2 horas antes.
- No Menu: ver a introdução de novo e, só no mock, entrar como cliente novo.

O `CortaAqui-casa.apk` desta release ainda é a casca antiga. O app da Casa
está no [PR #12](https://github.com/Mouretz/app-barber-java/pull/12), aberto.

## Servidor — PR #8 na main (8 out 2026)

O [PR #8](https://github.com/Mouretz/app-barber-java/pull/8) entrou na `main`.

- Expediente só entre 08:00 e 21:00, na grade de 30 minutos.
- Duração de serviço de 30 a 480, em múltiplos de 30.
- Só o gerente edita ficha de cliente.
- Profissional desativado perde o acesso naquela barbearia. Se não tiver outra, o token recebe 401. O gerente continua vendo o histórico dele no caixa.

## cortaaqui-apk-17 — 8 out 2026

Merge do PR #5. `DATA_SOURCE` só aceita `mock` ou `api`. Valor errado abre a tela de erro.
Ainda sem o fluxo de agendamento. Não use este para testar o cliente.

## cortaaqui-apk-11 — 8 out 2026, 00:22

Primeira release. Dois flavors (Cliente e Casa), tema preto e amarelo, modo mock.
