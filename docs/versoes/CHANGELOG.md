# Notas de versão

O que mudou em cada geração do app. Os APKs para instalar no Android ficam em
[Releases](https://github.com/Mouretz/app-barber-java/releases).

Cada vez que o workflow **CortaAqui APK** roda na `main` (ou na mão, em Actions),
sai uma release `cortaaqui-apk-N` com dois arquivos, em modo mock (sem servidor):

- `CortaAqui-cliente.apk` — quem marca o horário
- `CortaAqui-casa.apk` — gerente e profissional

A versão no `pubspec` continua `0.1.0+1` até a primeira tela de verdade. O número
que importa para baixar é o da release.

## Em geração — main de 8 out 2026

Base: `d80674c` (depois dos PRs #3, #4, #6 e #7).
APK anterior publicado: [cortaaqui-apk-11](https://github.com/Mouretz/app-barber-java/releases/tag/cortaaqui-apk-11), no commit `ff4d789`.

### No celular

A pasta `app/` **não mudou** desde o APK 11. Instalar de novo traz a mesma casca:
tema preto e amarelo, menu, tela de entrada dos dois flavors. Caixa, comissão e
as regras novas **não aparecem no APK**. Elas estão no servidor. O app ainda roda
em mock, sem falar com a API.

### No servidor (isto entrou na main)

- Domínio multi-barbearia: Spring Boot 3.4, Java 21, Flyway, Postgres 17 (PR #3).
- Caixa do mês e gerência das porcentagens, histórias 8 e 20 (PR #4). A porcentagem
  fica gravada na conclusão. Profissional vê só a própria linha. Gerente vê a casa.
- Dois horários marcados ao mesmo tempo não derrubam o servidor: o segundo recebe
  horário ocupado (409), não erro 500.
- Bloqueio não apaga agendamento. Agendamento em cima de bloqueio é recusado.
  Bloqueio em cima de agendamento entra e a agenda da Casa marca o conflito.
- Código de cliente desconhecido no histórico responde 401.
- Liberar aparelho continua travado sempre. A senha de desenvolvimento saiu do
  comentário do seed (PR #6).
- Plano de testes da QA atualizado: caixa, deadlock e DATA_SOURCE (PR #7).

### Ainda não está nesta geração

- PR #5: o app só aceita `DATA_SOURCE` igual a `mock` ou `api`. Valor errado mostra
  tela de erro. O Actions desse PR gera APK só como artifact, sem release.
- PR #8: regras do PO no servidor (expediente 08:00–21:00, duração em blocos de
  30 minutos, ficha só o gerente edita, profissional desativado perde a barbearia).

## cortaaqui-apk-11 — 8 out 2026, 00:22

Primeira release publicada pelo Actions.

- Dois flavors Flutter no mesmo projeto: Cliente e Casa.
- Tema (preto, amarelo `#E6B325`, fonte Inter) e menu.
- Workflow que gera os APKs em modo mock e publica na release quando roda na `main`.
