# Notas de versão

O que mudou em cada geração do app. Os APKs para instalar no Android ficam em
[Releases](https://github.com/Mouretz/app-barber-java/releases).

Cada vez que o workflow **CortaAqui APK** roda na `main` (ou na mão, em Actions),
sai uma release `cortaaqui-apk-N` com dois arquivos, em modo mock (sem servidor):

- `CortaAqui-cliente.apk` — quem marca o horário
- `CortaAqui-casa.apk` — gerente e profissional

A versão no `pubspec` continua `0.1.0+1` até a primeira tela de verdade. O número
que importa para baixar é o da release.

## Servidor — PR #8 na main (8 out 2026)

O [PR #8](https://github.com/Mouretz/app-barber-java/pull/8) entrou na `main`.

- Expediente só entre 08:00 e 21:00, na grade de 30 minutos.
- Duração de serviço de 30 a 480, em múltiplos de 30.
- Só o gerente edita ficha de cliente.
- Profissional desativado perde o acesso naquela barbearia. Se não tiver outra, o token recebe 401. O gerente continua vendo o histórico dele no caixa.

Isso não muda o APK. O app de teste continua em modo mock, sem falar com o servidor.

## cortaaqui-apk-17 — 8 out 2026

Merge do PR #5. `DATA_SOURCE` só aceita `mock` ou `api`. Valor errado abre a tela de erro.
Baixar: [cortaaqui-apk-17](https://github.com/Mouretz/app-barber-java/releases/tag/cortaaqui-apk-17).

## cortaaqui-apk-16 — 8 out 2026

Mesma casca do APK 11. A pasta `app/` ainda não tinha o PR #5.

## cortaaqui-apk-11 — 8 out 2026, 00:22

Primeira release. Dois flavors (Cliente e Casa), tema preto e amarelo, modo mock.
