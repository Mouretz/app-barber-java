# Notas de versão

O que mudou em cada geração do app. Os APKs para instalar no Android ficam em
[Releases](https://github.com/Mouretz/app-barber-java/releases).

Cada vez que o workflow **CortaAqui APK** roda na `main` (ou na mão, em Actions),
sai uma release `cortaaqui-apk-N` com dois arquivos, em modo mock (sem servidor):

- `CortaAqui-cliente.apk` — quem marca o horário
- `CortaAqui-casa.apk` — gerente e profissional

A versão no `pubspec` continua `0.1.0+1` até a primeira tela de verdade. O número
que importa para baixar é o da release.

## Em geração — merge do PR #5

O app na `main` passou a só aceitar `DATA_SOURCE` igual a `mock` ou `api`.
Valor errado abre a tela de erro de configuração, em vez de fingir que é mock.
Sem `--dart-define` continua mock. O APK publicado por este Actions é esse app,
ainda sem servidor.

O que continua só no servidor (não aparece no APK de teste):

- Caixa do mês e porcentagem do profissional (PR #4).
- Horário duplicado responde 409, não 500.
- Bloqueio não apaga agendamento.
- PR #8 (regras do PO: expediente 08:00–21:00, duração em blocos de 30,
  ficha só o gerente edita, profissional desativado perde a barbearia)
  entra junto desta atualização do servidor. O gerente continua vendo o
  histórico no caixa; o token do profissional desativado recebe 401.

## cortaaqui-apk-16 — 8 out 2026

Mesma casca do APK 11. A pasta `app/` ainda não tinha o PR #5.
Servidor já tinha os PRs #3, #4, #6 e #7.

## cortaaqui-apk-11 — 8 out 2026, 00:22

Primeira release. Dois flavors (Cliente e Casa), tema preto e amarelo, modo mock.
