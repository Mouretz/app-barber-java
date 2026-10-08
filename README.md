# CortaAqui

Agendamento para barbearias, com dois apps e um servidor:

- **CortaAqui** (app Cliente): quem marca o horário.
- **CortaAqui Casa**: gerente e profissional (agenda, balcão, clientes, preços, caixa).
- **Servidor**: Spring Boot + Postgres, multi-barbearia.

## Estrutura

| Pasta | O que tem |
|---|---|
| `api/openapi.yaml` | Contrato da API. Vem antes de qualquer tela ou endpoint; mudou o contrato, muda aqui no mesmo PR. |
| `app/` | Projeto Flutter único com 2 flavors: `cliente` e `casa`. |
| `app/lib/theme/` | Pacote de tema (cores, fontes Inter, menu de linha fina). Telas importam `theme/theme.dart`. |
| `server/` | Spring Boot 3.4 / Java 21 / Flyway / Postgres 17. |
| `docs/` | Documentos do time (ex.: plano de testes da QA). |
| `docs/versoes/CHANGELOG.md` | Notas de versão: o que mudou em cada APK. |

## App

```bash
cd app
flutter pub get
flutter run --flavor cliente -t lib/main_cliente.dart   # app Cliente
flutter run --flavor casa -t lib/main_casa.dart         # app Casa
```

Por padrão roda em **modo mock**, sem servidor. Para ligar na API:
`--dart-define=DATA_SOURCE=api --dart-define=API_BASE_URL=http://10.0.2.2:8080/api/v1`.

### Regra do amarelo (`#E6B325`)

Só na aba ativa (e no ponto ativo da introdução), no profissional escolhido e no botão
principal, com texto preto. O resto é branco e cinza. Texto secundário: `#8E8E93` sobre
`#000000`/`#1C1C1E`, e `#AEAEB2` sobre `#2C2C2E`.

## APK

Workflow **CortaAqui APK** (aba Actions). Em PR que mexe no `app/` ele só gera os APKs como
artifact. Na `main` (ou rodando na mão em Actions > CortaAqui APK > Run workflow) também
publica uma release com `CortaAqui-cliente.apk` e `CortaAqui-casa.apk`, em
[Releases](https://github.com/Mouretz/app-barber-java/releases).

O que entrou em cada geração está em [docs/versoes/CHANGELOG.md](docs/versoes/CHANGELOG.md).

## Servidor

```bash
cd server
docker network create barber-shop-net   # só na primeira vez
docker compose up
```

## Regras do time

Nada de push direto na `main`: sempre branch + PR, com OK da QA e do tech lead, e CI verde.
