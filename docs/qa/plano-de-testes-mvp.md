# Plano de testes do MVP do CortaAqui

Autora: QA Dev (Mesa Dev). Base: as histórias do MVP aprovadas pelo mouretz em 07/10/2026, as três rodadas de respostas do PO Dev às perguntas da QA, a regra do caixa por papel e as decisões do PO sobre as perguntas em aberto e sobre o contrato (todas de 07/10/2026), que agora valem como regra.

Este plano diz **o que** testar em cada história e **em que nível**. Ele não escolhe a implementação.
Onde a regra ainda é vaga demais para virar um teste, o caso aponta para as [Perguntas em aberto](#perguntas-em-aberto).
Quando uma pergunta for respondida, o caso correspondente é ajustado neste arquivo.

## Sumário

1. [Escopo](#1-escopo)
2. [Regras confirmadas](#2-regras-confirmadas)
3. [Ambientes](#3-ambientes)
4. [Níveis de teste](#4-níveis-de-teste)
5. [Dados de teste](#5-dados-de-teste)
6. [O que o código precisa ter para ser testável](#6-o-que-o-código-precisa-ter-para-ser-testável)
7. [Casos de teste](#7-casos-de-teste)
8. [Checklist do teste manual do APK mock](#8-checklist-do-teste-manual-do-apk-mock)
9. [Critérios para a QA dar OK num PR](#9-critérios-para-a-qa-dar-ok-num-pr)
10. [Observações](#observações) e [Perguntas em aberto](#perguntas-em-aberto)
11. [Resumo dos casos](#11-resumo-dos-casos)

---

## 1. Escopo

**Entra no MVP (e neste plano):**

| App | Histórias |
|---|---|
| Cliente | (14) Introdução, (15) Início, (16) Página da barbearia, (1) Agendar, (4) Meus horários |
| Casa | (2) Agenda por profissional, (6) Balcão, (7) Expediente e folgas, (17) Clientes, (10) Preços e profissionais, (8) Caixa do mês, (20) Gerência |
| Regras gerais | (3) Sem encaixe duplo, status só anda pra frente, pedido repetido ignorado, preço gravado, horários livres só no servidor |
| Transversal | Login (gerente e profissional com e-mail e senha; cliente sem senha, com um código que nasce no aparelho), papéis, multi-tenant (`barbershop_id`), fuso America/Sao_Paulo, modo mock |
| Visual e nome | (9) Visual, (13) Nome CortaAqui |

**Fica fora (não testar, só conferir que não aparece):** nota, pontos de fidelidade, pagamento no app, relatório, avaliações e favoritar.
Também fica fora: confirmação de telefone por SMS, hospedagem do servidor e publicação na Play Store.

**Estrutura atual do repo (main em 07/10/2026):** o Spring Boot antigo em `src/` (Boot 3.4.2, Java 21, Flyway, 2 migrations, sem testes)
e o app WebView em `navalha-android/`. A tabela `SCHEDULES` de hoje só tem `UNIQUE (start_at, end_at)`, que **não** barra sobreposição parcial.
Por isso o CT-03-01 tem que falhar contra o schema antigo.

## 2. Regras confirmadas

Respostas do PO Dev de 07/10/2026 (três rodadas, a regra do caixa por papel e as decisões sobre as perguntas em aberto e o contrato) e o modelo de dados aprovado. Cada regra aponta para os casos que a cobrem.

**Agenda e horários livres**
- **Grade de 30 em 30 min.** Os horários começam de 30 em 30 min e o cliente escolhe o horário exato. Pedir um início fora da grade (ex.: 10:15) dá 422 `VALIDATION_ERROR` com o campo `startAt`. (CT-01-06, CT-01-18)
- **Turnos são só filtro na tela:** manhã 08:00–12:00, tarde 12:00–18:00, noite 18:00–21:00. O turno não muda o que o servidor calcula. (CT-01-17)
- **Duração do serviço é definida pelo gerente.** No mock: corte 30 min, barba 30 min e combo 60 min (ocupa 2 horários seguidos). (CT-10-06, CT-00-33)
- **Um horário só aparece nos livres se:** o serviço inteiro cabe no expediente do profissional, não bate com marcação `agendado` ou `concluido` nem com bloqueio em nenhum dos horários que ele ocupa, e começa com pelo menos 30 min de antecedência (regra do cliente pelo app). (CT-01-02 a CT-01-12)
- **A agenda abre 14 dias contando com hoje:** de hoje até hoje + 13, com "hoje" no fuso America/Sao_Paulo. Fora disso dá 422 `DATE_OUT_OF_RANGE`, tanto pra listar horários quanto pra marcar (não é lista vazia). (CT-01-13, CT-01-14, CT-06-08, CT-00-30)
- **O que ocupa a agenda (a trava):** marcações `agendado` e `concluido` e os bloqueios. **Falta e cancelado não ocupam:** depois de marcar falta, o horário fica livre de novo. (CT-03-06, CT-03-10, CT-03-11, CT-06-11)
- **Bloqueio:** é um intervalo dentro do mesmo dia, com início e fim na grade de 30 min. O menor é de 30 min. Passa pela mesma trava das marcações. O profissional desbloqueia os bloqueios dele e o gerente desbloqueia qualquer um. Desbloquear não mexe em marcação nenhuma. **Meia-noite:** um bloqueio que termina às 00:00 conta como fim do mesmo dia, e nada passa pro dia seguinte. (CT-02-07, CT-02-08, CT-02-15 a CT-02-21)
- **Preço e duração ficam gravados na marcação.** Mudar o serviço depois não muda agendamento que já existe. (CT-10-01, CT-10-06)

**Cliente e barbearias (modelo aprovado)**
- **Telefone normalizado:** o servidor aceita o número com máscara, com ou sem o 55, e normaliza. **Nunca recusa por formato** quando os dígitos formam um número válido. A resposta da API traz sempre `+55` + DDD + número (ex.: `+5511987654321`), com 10 ou 11 dígitos depois do 55. Formas diferentes de escrever o mesmo número viram o mesmo cliente: `(11) 98765-4321`, `11987654321`, `+55 11 98765-4321` e `5511987654321` são iguais. A constraint única do banco é sobre o número normalizado, e o limite de 2 soma as variações. (CT-17-11 a CT-17-18, CT-01-29, CT-06-16)
  - **Com `+` é sempre o código do país.** Sem `+`, 10 ou 11 dígitos são número nacional (DDD + número), e 12 ou 13 dígitos começando com 55 são país + número. Ex.: `55987654321` (11, sem `+`) é DDD 55 e vira `+5555987654321`; `551134567890` (12) vira `+551134567890`. (CT-17-17)
  - **10 dígitos é fixo:** `(11) 8765-4321` é outro número e outro cliente. O servidor **não** acrescenta o 9. (CT-17-16)
  - Inválidos: menos de 10 dígitos nacionais, 12 ou 13 dígitos que não começam com 55, letras e país diferente de 55. (CT-17-12)
- **Cliente único por telefone, com uma ficha por barbearia.** Cada barbearia só vê a própria ficha e os próprios agendamentos daquele cliente. (CT-17-08 a CT-17-10)
- **Código do cliente:** o servidor **nunca** devolve o código. Ele nasce no aparelho (o app gera) e vai no primeiro agendamento, e o servidor prende esse código àquele telefone. Outro aparelho com o mesmo telefone é recusado com 409 `PHONE_ON_OTHER_DEVICE`, e o app mostra a mensagem exata **"Esse telefone já está em outro aparelho. Fale com a barbearia."** Só a Casa, logada, busca cliente por telefone; o cliente anônimo não busca. **Um telefone por aparelho:** depois do 1º agendamento o app trava o campo de telefone, e o servidor recusa o código com um telefone diferente com 409 `DEVICE_PHONE_MISMATCH`. **Troca de celular:** só o gerente libera, na ficha do cliente no app Casa, no botão "Liberar aparelho" (`POST …/clients/{clientId}/release-device`, rota só do gerente: 403 pro profissional que não é gerente e 404 pro gerente de outra barbearia, pela regra geral do contrato). O código antigo para de valer na hora. **Liberar em uma barbearia libera em todas**, porque o aparelho fica preso ao telefone, e não à barbearia; no MVP, o gerente da outra barbearia não é avisado. Os horários futuros continuam marcados (são do cliente, não do aparelho). O próximo aparelho que agendar com esse telefone fica preso a ele e passa a ver esses horários, de todas as barbearias, e o limite de 2 continua contando esses horários. **O aparelho só fica preso quando o agendamento entra:** se o 1º agendamento é recusado por qualquer motivo (limite de 2, menos de 30 min, fora dos 14 dias, horário ocupado), nada fica preso e o próximo aparelho ainda pode tentar. **Trava proposta pelo Back-end e pelo tech lead (o PO ainda não confirmou):** o gerente só libera um telefone que tenha pelo menos um agendamento feito pelo app na barbearia dele; senão, 409 `DEVICE_RELEASE_NOT_ALLOWED`. Vale também no mock. (CT-01-01, CT-04-08, CT-04-14 a CT-04-23, CT-17-19 a CT-17-28)
- **Limite de 2 horários futuros:** vale só pro que é marcado pelo app e soma todas as barbearias. (CT-01-19 a CT-01-22, CT-01-27, CT-01-28, CT-00-42)
- **Papel por barbearia:** a mesma pessoa pode ser gerente em uma e não ter acesso, ou ter outro papel, em outra. (CT-00-38 a CT-00-40)

**Casa: marcação, cancelamento e status**
- **A Casa cancela a qualquer hora antes de concluir** (gerente em qualquer agenda, profissional na própria). A regra das 2h vale só pro cliente, que vê "cancelado pela barbearia". (CT-02-11, CT-04-11)
- **Concluir e marcar falta só a partir do horário de início:** 1 min antes é recusado, no horário exato é aceito. (CT-02-12, CT-02-14)
- **Cliente cancela com 2h ou mais:** exatamente 2h antes ainda pode; 2h menos 1 s já não. (CT-04-02 a CT-04-04)
- **Pedido repetido e status mudou:** repetir o mesmo pedido com a mesma `Idempotency-Key` é ignorado e devolve o mesmo resultado. Um pedido (com outra chave) que chega depois de o status já ter mudado leva 409 `STATUS_CHANGED` (o `INVALID_STATUS_TRANSITION` saiu do contrato), e a tela recarrega. Vale pra cancelar (cliente e Casa) e pra mudar status. (CT-00-02, CT-00-03, CT-00-06, CT-00-43 a CT-00-45, CT-04-10, CT-02-23)
- **Marcação pela Casa ou balcão:** vale a janela de 14 dias. Não valem o limite de 2 nem os 30 min. A Casa pode marcar o slot de 30 min que está **em andamento** agora, mas não um que já terminou (às 10:10, o slot 10:00 pode e o 09:30 não). Não conta no limite de 2 do cliente pelo app. O cliente pelo app continua com 30 min de antecedência. (CT-06-05, CT-06-06, CT-06-08 a CT-06-10, CT-06-12 a CT-06-14)
- **Balcão:** o nome é obrigatório e o telefone é opcional. Sem telefone, o atendimento cria só a ficha daquela barbearia (nenhum cliente por telefone) e não conta no limite de 2. Com telefone, ele é normalizado e liga ao cliente daquele número. (CT-06-01, CT-06-07, CT-06-15, CT-06-16)
- **Profissional removido é desativado, não apagado.** O servidor recusa a desativação enquanto houver horário futuro ativo. Depois de desativado, some da agenda e do agendamento, e histórico e caixa continuam. (CT-10-04, CT-10-05, CT-10-08, CT-10-09)

**Papéis**
- **Gerente:** tudo na sua barbearia, inclusive a agenda de qualquer profissional.
- **Profissional que não é gerente:** vê só a própria agenda. Pedir a agenda de outro profissional dá 403. Marca, conclui, dá falta, cancela e bloqueia só na agenda dele. Vê só o próprio ganho do mês. (CT-00-12, CT-02-22)
- **Só o gerente:** expediente e folgas, serviços, preços, % (rotas `/commission`, GET e PUT), outros profissionais e o caixa da casa inteira (total da barbearia e linhas de todos os profissionais).
- **Caixa por papel (regra do PO, 07/10):** `GET /cash` e `GET /cash/professionals/{id}` **não** são só do gerente. O profissional que não é gerente recebe **200 só com a própria linha**, sem o total da casa e sem as linhas dos outros profissionais. Ele recebe **403 só quando pede a linha de outro profissional**. Na própria linha, ele vê **só a parte dele**. O `shopCents` é **opcional** no `CashTotals`, e o servidor **não manda o campo** (fica ausente, nem `null` nem zero) quando quem pede é um profissional que não é gerente, nas duas rotas. O `grossCents` e o `professionalCents` dele continuam. O gerente recebe o `shopCents` normalmente. As rotas `/commission` continuam só do gerente (403 para quem não é). (CT-08-09, CT-08-10, CT-08-13 a CT-08-15, CT-20-10, CT-00-15)
- **O bloqueio vale no servidor** (403), não só escondendo o botão na tela. (CT-00-12 a CT-00-24)

**Caixa e %**
- **% por profissional, só número inteiro de 0 a 100.** Padrão: 60% pro profissional e 40% pra casa. Só o gerente muda. A soma é sempre 100. (CT-20-01 a CT-20-07)
- **A % fica gravada no agendamento na conclusão.** Mudar depois não altera o caixa antigo. (CT-20-04, CT-20-05)
- **Entra no caixa:** só agendamento `concluido`, inclusive a marcação de balcão. **Não entram:** falta, cancelado e agendado ainda não concluído. (CT-08-02, CT-08-03, CT-08-11)
- **Arredondamento (confirmado):** é **por agendamento, na conclusão**, não no total do mês. O valor do profissional = preço × % arredondado pro centavo mais próximo, com meio centavo pra cima (`HALF_UP`). A casa fica com o resto (preço − valor do profissional). O caixa do mês só soma os valores já gravados. Confirmado pelo PO em 07/10: o CT-20-08 e o CT-20-09 ficam como estão. (CT-20-08, CT-20-09)
- **Sempre soma o total:** em cada agendamento, parte da casa + parte do profissional = preço gravado, centavo por centavo. No mês: **caixa da casa + soma do ganho de todos os profissionais = total concluído.** (CT-08-01, CT-08-05)
- **Data do caixa:** o mês é o da data do atendimento (início da marcação) no fuso de São Paulo, não o da conclusão. (CT-08-07, CT-08-08, CT-08-12)

**Visual**
- **Vale a regra escrita**, mesmo onde o print do protótipo mostra diferente.
- **Amarelo oficial `#E6B325`**, com texto preto `#000000` no botão.
- **O amarelo aparece só em 4 lugares:** aba ativa, profissional escolhido, botão principal e ponto ativo da introdução. O rótulo acima do título e o "Próximo" da introdução ficam brancos.
- **Texto secundário:** sobre o card `#2C2C2E` usa `#AEAEB2`. O `#8E8E93` só vale sobre `#1C1C1E` e `#000000`.
- **`#636366` saiu do tema.** Abas inativas e placeholder usam `#8E8E93` (6,44:1 sobre `#000000` e 5,21:1 sobre `#1C1C1E`). (CT-09-11)

Contrastes conferidos (fórmula WCAG 2.1, valores truncados em 2 casas). AA pede 4,5:1 para texto normal.

| Texto | Fundo | Contraste | AA texto |
|---|---|---|---|
| `#FFFFFF` | `#000000` | 21,00:1 | passa |
| `#FFFFFF` | `#1C1C1E` | 17,01:1 | passa |
| `#FFFFFF` | `#2C2C2E` | 13,93:1 | passa |
| `#8E8E93` | `#000000` | 6,44:1 | passa |
| `#8E8E93` | `#1C1C1E` | 5,21:1 | passa |
| `#8E8E93` | `#2C2C2E` | 4,27:1 | **reprova** (proibido por regra) |
| `#AEAEB2` | `#2C2C2E` | 6,30:1 | passa |
| `#000000` | `#E6B325` (botão) | 10,83:1 | passa (também AAA) |
| `#E6B325` | `#000000` | 10,83:1 | passa |
| `#E6B325` | `#1C1C1E` | 8,78:1 | passa |
| `#E6B325` | `#2C2C2E` | 7,19:1 | passa |
| `#FFFFFF` | `#E6B325` | 1,93:1 | **reprova** (nunca usar texto branco no amarelo) |

## 3. Ambientes

| Ambiente | Para quê | Como |
|---|---|---|
| **Mock no APK** | Primeira entrega pro mouretz. Os 2 apps (Cliente e Casa) rodando sem servidor. | Flavor `mock` (ou flag de build) com repositório em memória e o seed da Barbearia Navalha. Testado em celular Android real, em modo avião. |
| **Servidor com Postgres real** | Regras de negócio, constraint do banco, concorrência, multi-tenant, papéis e fuso. | Testcontainers com a mesma versão de Postgres de produção (17). Nada de H2: a constraint de não sobreposição e o lock só existem no Postgres. JVM com `-Duser.timezone=UTC`. |
| **CI (GitHub Actions)** | Rodar tudo em cada PR. | Job Java: `./gradlew test` (unitário + integração com Testcontainers, Docker já existe no runner `ubuntu-latest`). Job Flutter: `flutter analyze` + `flutter test` (widget e golden). Job de APK: gera os 2 APKs mock com o nome CortaAqui. Variável `TZ=UTC` no runner. |

## 4. Níveis de teste

| Sigla | Nível | Onde roda |
|---|---|---|
| **UNI** | Unitário Java | JUnit 5, sem banco, com `Clock` fixo |
| **INT** | Integração com Postgres real | Testcontainers + repositórios/serviços reais |
| **API** | API | Chamada HTTP (MockMvc ou RestAssured) no app Spring inteiro, com Postgres real por trás |
| **FLU** | Widget/integração Flutter | `flutter test` com repositório fake e relógio fixo; golden tests para visual |
| **MAN** | Manual no APK | Celular Android real, roteiro da seção 8 |

## 5. Dados de teste

O seed oficial, igual no mock e no servidor, tem a **Barbearia Navalha**, os profissionais **Caio** e **Helena**, os serviços **Corte R$ 40,00 (30 min)**, **Barba R$ 30,00 (30 min)** e **Combo R$ 60,00 (60 min)** e pelo menos 1 cliente. Os ids são fixos e estão definidos em `app/lib/data/mock/mock_seed.dart` (branch do Front-end, ainda sem push). O seed do servidor usa os mesmos ids e valores (CT-00-33).
Os testes automáticos usam, além disso, dados próprios para não depender de detalhes do seed:

| Nome no plano | O que é |
|---|---|
| **Barbearia A** | Barbearia Navalha (seed) |
| **Barbearia B** | Segunda barbearia criada só nos testes, para isolamento multi-tenant |
| **P1, P2** | Profissionais da A, sem papel de gerente. **PB1** é profissional da B |
| **G-A** | Gerente da A que não é barbeiro e não tem vínculo com a B. **G-P2** é um profissional da A que também é gerente. **G-B** é gerente da B |
| **PX** | Mesma pessoa (mesmo login) com papel de gerente na A e de profissional na B (papel por barbearia) |
| **Serviços** | Corte 30 min (R$ 40,00), Barba 30 min (R$ 30,00) e Combo 60 min (R$ 65,00). As durações são as do seed; os preços são **só de teste** (o Combo de teste custa R$ 65,00, e o do seed R$ 60,00), para os testes de caixa não dependerem do seed |
| **% de teste** | P1 com o padrão 60/40 (profissional/casa). P2 com 70/30 |
| **Expediente de teste** | 08:00 às 19:00 (hora de Brasília), todos os dias, salvo quando o caso diz outra coisa |
| **Telefones** | T1 = `+5511987654321` e T2 = `+5521912345678` (formato da resposta da API), de clientes diferentes. T1 tem ficha na A e na B (cliente único por telefone, uma ficha por barbearia). Aparelhos: D1 com o código K1 (preso a T1) e D2 com o código K2 |
| **Relógio** | Sempre fixo. Datas do plano em hora de Brasília (BRT, UTC-3, sem horário de verão desde 2019). "Hoje" = 07/10/2026, salvo quando o caso diz outra coisa |

## 6. O que o código precisa ter para ser testável

Sem isto, vários casos abaixo não têm como ser automatizados. Peço que entre no primeiro PR de cada camada.

1. **Relógio injetável:** o servidor usa um `java.time.Clock` injetado (zona `America/Sao_Paulo`), nunca `LocalDateTime.now()` solto. O app Flutter recebe um relógio fake nos testes.
2. **Datas no banco com fuso:** colunas `timestamptz` e conversão para America/Sao_Paulo só na regra de "dia" e "mês".
3. **Identificador do pedido:** um header (ex.: `Idempotency-Key`) definido no contrato OpenAPI, para criar, cancelar e mudar status.
4. **Erros com código estável:** conflito (`SLOT_TAKEN`), status mudou (409 `STATUS_CHANGED`), fora do prazo, limite por telefone, antecedência, fora da janela de 14 dias (`DATE_OUT_OF_RANGE`), campo inválido (`VALIDATION_ERROR` com o campo), telefone em outro aparelho (409 `PHONE_ON_OTHER_DEVICE`), código com telefone diferente (409 `DEVICE_PHONE_MISMATCH`), liberação de aparelho não permitida (409 `DEVICE_RELEASE_NOT_ALLOWED`) e sem permissão devolvem um código de erro próprio no corpo (além do HTTP), para o app e os testes não dependerem do texto.
5. **`barbershop_id` e papel vêm do token**, nunca de parâmetro da requisição. Como o papel é por barbearia, o token (ou a barbearia ativa validada no servidor) diz em qual barbearia a pessoa está agindo, e o papel é o dela nessa barbearia.
6. **Repositório do app atrás de interface:** a mesma tela roda com o repositório mock e com o de API.
7. **Rotas marcadas por papel no OpenAPI** (ex.: extensão `x-role: gerente`), para a varredura do CT-00-24 achar sozinha toda rota só do gerente. `GET /cash` e `GET /cash/professionals/{id}` **não** levam essa marca: o profissional recebe 200 filtrado nelas (regra própria, CT-08-13 a CT-08-15).
8. **Dinheiro em `BigDecimal` (ou centavos inteiros) com `RoundingMode.HALF_UP`.** Nunca `double`: R$ 33,33 × 50% em `double` dá 16,664999… e arredonda errado para 16,66.
9. **Normalização do telefone numa função só**, usada no agendamento pelo app, na Casa, no balcão, no cadastro e na busca.
10. **A trava no banco filtra pelo status:** a constraint de não sobreposição vale para `agendado`, `concluido` e bloqueio, e ignora `falta` e `cancelado`.
11. **Origem do agendamento gravada** (app, Casa ou balcão) e **quem cancelou** (cliente ou barbearia), para o limite de 2 e o texto "cancelado pela barbearia".

---

## 7. Casos de teste

Formato do ID: `CT-<história>-<nº>`. O grupo `CT-00` reúne as regras transversais (status, pedido repetido, login, papéis, multi-tenant, fuso e mock), que não pertencem a uma história só.

### CT-01 · (1) Agendar

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-01-01 | Agora = 07/10 09:00. P1 livre às 10:00. Aparelho D1 sem código salvo. | Abrir o app (gera K1 no aparelho) e agendar Corte com P1 às 10:00, com telefone T1, mandando K1. | 201. Agendamento `agendado`, 10:00–10:30, com `barbershop_id` da A, `professional_id` P1, preço R$ 40,00 gravado. A resposta **não traz código nenhum**. K1 fica preso a T1 no servidor. | API + FLU |
| CT-01-02 | Agora = 09:30:00. P1 livre às 10:00. | Pedir livres e agendar Corte às 10:00 (exatamente 30 min). | 10:00 aparece nos livres e o agendamento é aceito. | UNI + API |
| CT-01-03 | Agora = 09:31:00. | Pedir livres e agendar Corte às 10:00 (29 min). | 10:00 não aparece (o primeiro livre é 10:30) e o POST é recusado com erro de antecedência. Nada gravado. | UNI + API |
| CT-01-04 | Agora = 09:30:01. | Agendar 10:00 (29 min e 59 s). | Recusado. O limite conta segundos, não arredonda para o minuto. | UNI |
| CT-01-05 | Agora = 06/10 20:00. Expediente de P1 começa 08:00 no dia 07/10. | Pedir os livres de P1 para 07/10. | O primeiro horário é **08:00**. Não existe 07:30. | UNI + API |
| CT-01-06 | — | Pedir livres de um dia inteiro. Agendar Corte às 10:15. | Todos os livres começam em :00 ou :30. O POST de 10:15 dá 422 `VALIDATION_ERROR` com `fields[].field = startAt`. Nada gravado. | UNI + API |
| CT-01-07 | Expediente até 19:00. | Pedir livres de Corte e agendar Corte às 18:30 e às 19:00. | 18:30 é o último livre e é aceito (termina 19:00). 19:00 não aparece e é recusado. | UNI + API |
| CT-01-08 | Expediente até 19:00. | Pedir livres de Combo e agendar Combo às 18:00 e às 18:30. | 18:00 é o último livre de Combo e é aceito (termina 19:00). **18:30 não aparece** e o POST é recusado (terminaria 19:30). | UNI + API |
| CT-01-09 | Expediente começa 08:00. | Agendar Corte às 07:30. | Recusado (antes do expediente). | UNI + API |
| CT-01-10 | P1 tem Corte 10:30–11:00 `agendado`. | Pedir livres de Combo e de Corte. Agendar Combo às 10:00. | 10:00 aparece para Corte, mas **não para Combo** (o 2º horário está ocupado). O POST do Combo 10:00 é recusado com conflito. | UNI + API |
| CT-01-11 | P1 tem um bloqueio às 10:30. | Mesmos passos do CT-01-10. | Mesmo resultado: Combo 10:00 não aparece e é recusado. Bloqueio ocupa igual a um agendamento. | UNI + API |
| CT-01-12 | P1 tem Corte 10:00–10:30. | Pedir livres de Combo. | 09:30 também não aparece para Combo (o 2º horário bate com 10:00). 09:00 e 10:30 aparecem. | UNI |
| CT-01-13 | Hoje = 07/10. | Pedir livres de 20/10 (hoje + 13) e agendar nesse dia. | Tem livres e o agendamento é aceito (14º dia contando com hoje). | UNI + API |
| CT-01-14 | Hoje = 07/10. | Pedir livres de 21/10 (hoje + 14) e agendar nesse dia. | **422 `DATE_OUT_OF_RANGE` nos dois**: a lista não volta vazia, volta erro. Nada gravado. | UNI + API |
| CT-01-15 | Agora = 11:00. | Agendar hoje às 10:00. | Recusado (horário que já passou). | UNI + API |
| CT-01-16 | Hoje = 07/10. | Abrir o seletor de dia na tela Agendar. | Mostra 14 dias: de 07/10 a 20/10. | FLU |
| CT-01-17 | O servidor devolve livres de 08:00 a 20:30. | Na tela, filtrar por manhã, tarde e noite. | Manhã: 08:00 a 11:30. Tarde: 12:00 a 17:30. Noite: 18:00 a 20:30. 12:00 fica só em tarde e 18:00 só em noite. Trocar o turno não muda os horários nem faz o app calcular nada. | FLU |
| CT-01-18 | — | Escolher um turno e tocar num horário exato. | O horário tocado fica marcado e é exatamente esse início que vai no POST. | FLU |
| CT-01-19 | T1 já tem 2 horários futuros `agendado`, marcados pelo app. | Agendar o 3º com T1, pelo app. | Recusado com erro de limite por telefone. | API |
| CT-01-20 | T1 tem 2 futuros. Cliente cancela 1. | Agendar de novo com T1. | Aceito: cancelado não conta no limite. | API |
| CT-01-21 | T1 tem 1 futuro e 3 no passado (concluído, falta, cancelado). | Agendar mais 1 com T1. | Aceito: passado e status final não contam. | API |
| CT-01-22 | T1 tem 1 futuro. | Dois pedidos de agendamento de T1 ao mesmo tempo (horários diferentes, livres), em conexões separadas. | No máximo 1 aceito. Nunca 3 futuros para T1. Repetir 20 vezes. | INT |
| CT-01-23 | — | Agendar com profissional ou serviço da Barbearia B dentro da A. | Recusado (404 ou 422). Nada gravado. | API |
| CT-01-24 | — | Na tela Agendar: escolher serviço, profissional, dia e horário, e confirmar. | O botão Confirmar só habilita com tudo escolhido. Ao confirmar, mostra sucesso e o horário aparece em Meus horários. | FLU |
| CT-01-25 | Repositório fake devolve uma lista fixa de livres. | Abrir a tela Agendar. | A tela mostra exatamente a lista do servidor, só separada por turno, sem tirar nem calcular horário no app. | FLU |
| CT-01-26 | O servidor responde conflito no POST. | Confirmar um horário que alguém pegou antes. | O app mostra "esse horário acabou de ser ocupado", recarrega os livres e não deixa o horário velho selecionado. | FLU |
| CT-01-27 | T1 tem 1 futuro pelo app na A e 1 pelo app na B. | Agendar o 3º com T1, pelo app, na A. | Recusado com erro de limite: o limite soma todas as barbearias. | API |
| CT-01-28 | T1 tem 2 futuros pelo app na A. | Agendar com T1, pelo app, na B. Depois cancelar 1 na A e tentar de novo na B. | A 1ª tentativa é recusada. Depois do cancelamento, o agendamento na B é aceito. | API |
| CT-01-29 | Nenhum futuro para T1. | Pelo app (D1), agendar 1 com `(11) 98765-4321` e 1 com `5511987654321`. Depois tentar o 3º com `+55 11 98765-4321`. | Os 2 primeiros aceitos e ligados ao mesmo cliente, que volta como `+5511987654321`. O 3º é recusado: o limite soma as variações do número. | API |

### CT-03 · (3) Sem encaixe duplo por profissional

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-03-01 | P1 tem 10:00–10:30 ativo. | Inserir 10:15–10:45 para P1 **direto no banco** (sem passar pelo serviço). | O Postgres recusa com violação de constraint. **Tem que falhar contra o schema antigo** (`UNIQUE (start_at, end_at)` não pega sobreposição parcial). | INT |
| CT-03-02 | P1 tem Corte 10:30–11:00. | Pela API, agendar Combo 10:00–11:00 para P1. | 409 com código de conflito, mensagem amigável, nunca 500. | API |
| CT-03-03 | P1 tem Combo 10:00–11:00. | Agendar 10:15–10:45 (contido, direto no banco) e Combo 09:30–10:30 (pela API). | Os dois recusados. | INT + API |
| CT-03-04 | P1 tem 10:00–10:30. | Agendar 10:30–11:00 e 09:30–10:00 (encostados). | Os dois aceitos. Intervalo é `[início, fim)`. | INT + API |
| CT-03-05 | P1 tem 10:00–10:30. | Agendar P2 10:00–10:30. | Aceito: a regra é por profissional. | INT |
| CT-03-06 | P1 tem 10:00–10:30 `cancelado`. | Agendar 10:00–10:30 para P1. | Aceito: cancelado não ocupa (a constraint só vale para ativos). | INT + API |
| CT-03-07 | P1 livre às 10:00. | **Concorrência real:** 2 conexões separadas tentam gravar 10:00–10:30 para P1 ao mesmo tempo (threads soltas juntas por um `CountDownLatch`), clientes diferentes. Repetir 50 vezes. | Em todas as rodadas: exatamente 1 sucesso e 1 conflito. No banco, 1 agendamento ativo. **Tem que falhar sem a constraint** (o "confere e depois grava" deixa os 2 passarem). | INT |
| CT-03-08 | P1 livre. | Concorrência com sobreposição parcial: Combo 10:00–11:00 e Corte 10:30–11:00, ao mesmo tempo. | Só 1 vale. | INT |
| CT-03-09 | P1 livre às 10:00. | Ao mesmo tempo: app do cliente agenda 10:00, Casa lança balcão 10:00 e Casa bloqueia 10:00. | Só 1 dos 3 vale. Balcão, app e bloqueio passam pela mesma checagem. | INT |
| CT-03-10 | P1 tem 10:00–10:30 com status `concluido`. Em outro teste, com status `falta`. | Agendar 10:00–10:30 para P1. | Concluído ocupa: recusado. Falta não ocupa: aceito. | INT + API |
| CT-03-11 | P1 tem 10:00–10:30 em cada um destes estados, um por teste: `agendado`, `concluido`, bloqueio, `falta`, `cancelado`. | Inserir direto no banco uma marcação 10:15–10:45 e um bloqueio 10:00–11:00 para P1. | Com `agendado`, `concluido` e bloqueio: violação da constraint. Com `falta` e `cancelado`: aceito. | INT |

### CT-04 · (4) Meus horários

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-04-01 | Cliente C1 (código K1) tem 2 futuros e 2 passados. | Listar Meus horários com K1. | Vê os 4, com status. Futuros e histórico separados. | API + FLU |
| CT-04-02 | Agora = 08:00:00. Horário de C1 às 10:00. | Cancelar com K1. | **Aceito:** exatamente 2h antes ainda pode (a regra é "2h ou mais"). | UNI + API |
| CT-04-03 | Agora = 08:00:01. Horário às 10:00. | Cancelar com K1. | Recusado pelo servidor com erro de prazo. Status continua `agendado`. | UNI + API |
| CT-04-04 | Relógio fake: 2h01, **2h00 exatas** e 1h59 antes. | Abrir Meus horários nos três momentos. | Com 2h01 e com 2h00 o botão Cancelar aparece. Com 1h59 ele some e aparece "cancelamento só com a barbearia". | FLU |
| CT-04-05 | C1 cancela o horário de 10:00 com P1. | Pedir livres de P1. Outro cliente agenda 10:00. | 10:00 volta para os livres e o novo agendamento é aceito. | API |
| CT-04-06 | — | Listar e cancelar com código inexistente ou alterado. | 401/403. Nenhum dado volta. A mensagem não diz se o telefone existe. | API |
| CT-04-07 | C2 tem código K2 válido. | Com K2, listar e cancelar um horário de C1 (pelo id). | Recusado (403/404). O horário de C1 não muda. | API |
| CT-04-08 | Telefone T1 de C1 conhecido. Aparelho sem o código de C1. | Tentar listar, cancelar ou descobrir o código só com o telefone. Repetir **no mock do app Cliente**. | Recusado no servidor e no mock. Não existe rota nem tela que entregue o código pelo telefone. Saber o telefone não basta. | API + FLU |
| CT-04-09 | App com código salvo. | Fechar o app à força e abrir de novo. Reiniciar o celular. | O código continua lá e Meus horários carrega. | FLU + MAN |
| CT-04-10 | Horário de C1 já `cancelado` (pela Casa). | C1, com a tela velha, tenta cancelar (com outra `Idempotency-Key`). | Recusado com 409 `STATUS_CHANGED`. A tela recarrega e mostra "cancelado pela barbearia". | API + FLU |
| CT-04-11 | A Casa cancela um horário de C1 com menos de 2h. Em outro horário, a Casa conclui. | C1 abre Meus horários. | O cancelado aparece como **"cancelado pela barbearia"** e o outro como concluído. C1 não vê dados de outros clientes nem notas internas da barbearia. | API + FLU |
| CT-04-12 | C1 cancela um horário ele mesmo. | Abrir Meus horários. | Aparece como cancelado, **sem** o texto "pela barbearia". | API + FLU |
| CT-04-13 | C1 (código K1) tem 1 futuro pelo app na A e 1 na B. | Listar Meus horários com K1. | Vê os 2, cada um com o nome da sua barbearia (cliente único por telefone). | API |
| CT-04-14 | App instalado agora, sem código salvo. Mock e servidor. | Abrir o app. Agendar com T1. Reinstalar o app em outro celular e abrir. | O código nasce no aparelho (o app gera, sem pedir ao servidor) e vai no 1º agendamento. Dois aparelhos geram códigos diferentes. A resposta do agendamento não traz o código. | FLU + API |
| CT-04-15 | K1 (D1) preso a T1. | D2 (código K2) agenda com T1. Repetir escrevendo T1 de outro jeito (`(11) 98765-4321`) e com T1 sem nenhum horário futuro. | Recusado nas 3 vezes com 409 `PHONE_ON_OTHER_DEVICE`, e o app mostra a mensagem exata **"Esse telefone já está em outro aparelho. Fale com a barbearia."** Nada gravado, K2 não fica preso a T1, e os horários de T1 não aparecem para D2. O app mostra o texto exato. | API + FLU |
| CT-04-16 | T1 ainda sem aparelho. Dois horários livres diferentes. | **Concorrência real (corrida):** D1 (K1) e D2 (K2) fazem o 1º agendamento com T1 ao mesmo tempo, cada um num horário livre. Repetir 20 vezes. | Em todas as rodadas, **só um código fica preso a T1** e só o agendamento dele é gravado. O outro aparelho recebe 409 `PHONE_ON_OTHER_DEVICE` e não fica preso a nada. | INT |
| CT-04-17 | K1 preso a T1, com agendamentos na A. | Varredura: chamar todas as rotas (agendar, Meus horários, cancelar, ficha do cliente na Casa, agenda, caixa) e procurar o valor de K1 nas respostas e nos logs do servidor. | K1 não aparece em nenhuma resposta nem em log. | API |
| CT-04-18 | — | Buscar cliente por telefone (`GET /clients?q=11987654321`) sem token e só com `X-Client-Code`. Depois com o token do G-A. | Sem token e com código de cliente: 401, nenhum dado. Com G-A logado: acha T1 (só a ficha da A). O cliente anônimo não tem rota que diga se um telefone existe. | API |
| CT-04-19 | T1 cadastrado só pela Casa (balcão com telefone), sem aparelho preso. | D1 (K1) agenda pelo app com T1. | Aceito. K1 passa a ficar preso a T1: o telefone ainda não tinha aparelho, e o próximo aparelho que agenda com ele fica preso (mesma regra da troca de celular, CT-17-20). Um 2º aparelho depois disso cai no CT-04-15. | API |
| CT-04-20 | K1 (D1) preso a T1, com 1 horário futuro. | Com K1, agendar informando T2. Depois, com K1, agendar informando T1 escrito de outro jeito (`(11) 98765-4321`). | T2: **recusado** com 409 `DEVICE_PHONE_MISMATCH`. Nada gravado: T2 não vira cliente nem ganha ficha, e K1 continua preso só a T1. T1 com outra máscara: aceito (é o mesmo número). | API |
| CT-04-21 | App Cliente, no mock e com servidor. | Abrir Agendar antes do 1º agendamento, fazer o 1º agendamento com T1, abrir Agendar de novo, fechar o app à força e abrir de novo. No mock, mandar um agendamento com K1 e T2 direto pelo repositório. | Antes do 1º agendamento, o campo de telefone é editável. Depois, ele aparece preenchido com T1 e **travado**, também depois de reabrir o app. O mock recusa K1 com T2 do mesmo jeito que o servidor. | FLU |
| CT-04-22 | T1 ainda sem aparelho. | D1 (K1) faz o 1º agendamento com T1 e é recusado, um motivo por vez: limite de 2 (T1 já tem 2 futuros pelo app, depois de uma liberação), menos de 30 min (`TOO_SOON`), hoje + 14 (`DATE_OUT_OF_RANGE`) e horário ocupado (`SLOT_TAKEN`). Depois de cada recusa, D2 (K2) agenda um horário válido com T1. | Cada recusa de D1 tem o código próprio dela e **não prende K1**. O agendamento de D2 é aceito e K2 fica preso a T1. Depois disso, D1 cai no CT-04-15. | API |
| CT-04-23 | T1 ainda sem aparelho. P1 tem 10:00 ocupado e 10:30 livre. | **Concorrência real (corrida):** ao mesmo tempo, D1 (K1) pede 10:00 (vai dar `SLOT_TAKEN`) e D2 (K2) pede 10:30 com T1. Repetir 20 vezes. | Em todas as rodadas, D1 é recusado por horário ocupado e não fica preso. D2 é aceito e K2 fica preso a T1, em qualquer ordem de chegada. | INT |

### CT-14 · (14) Introdução

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-14-01 | Primeira abertura. | Tocar Próximo duas vezes. | Passa pelas 3 telas. O indicador mostra 3 pontos e só o ponto da tela atual fica amarelo `#E6B325`. | FLU |
| CT-14-02 | Na 3ª tela. | Tocar no botão final. | Vai para o Início. | FLU |
| CT-14-03 | Na 1ª tela. | Tocar Pular. | Vai direto para o Início. | FLU |
| CT-14-04 | Intro já vista. | Fechar e abrir o app. | Depende da [pergunta da intro](#perguntas-em-aberto). | FLU |

### CT-15 · (15) Início

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-15-01 | Cliente com 2 futuros (amanhã 10:00 e depois de amanhã 15:00). | Abrir o Início. | O card "próximo horário" mostra amanhã 10:00, com serviço, profissional e barbearia. | FLU + API |
| CT-15-02 | O mais próximo foi cancelado. | Abrir o Início. | Mostra o seguinte ativo, nunca um cancelado ou já passado. | FLU |
| CT-15-03 | Cliente sem horário (ou sem código). | Abrir o Início. | Estado vazio com chamada para agendar. Sem erro. | FLU |
| CT-15-04 | Seed. | Abrir o Início. | A lista de barbearias mostra a Barbearia Navalha. Tocar abre a página dela (CT-16). | FLU + MAN |

### CT-16 · (16) Página da barbearia

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-16-01 | Seed. | Abrir a Barbearia Navalha. | Mostra os serviços do seed com preço e duração (Corte R$ 40,00 / 30 min, Barba R$ 30,00 / 30 min, Combo R$ 60,00 / 60 min) e os profissionais Caio e Helena. | API + FLU |
| CT-16-02 | G-A (gerente que não é barbeiro) existe. | Abrir a página. | G-A não aparece como profissional. | API |
| CT-16-03 | Um profissional desativado (CT-10-04). | Abrir a página. | Ele não aparece. | API |
| CT-16-04 | — | Tocar em Agendar a partir de um serviço ou profissional. | Abre o Agendar com a barbearia (e o item tocado) já escolhidos. | FLU |
| CT-16-05 | — | Procurar nota, avaliações, favoritar, pontos e pagamento. | Nada disso aparece (fora do MVP). | FLU + MAN |

### CT-02 · (2) Agenda por profissional (Casa)

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-02-01 | G-A logado. P1 e P2 com horários no mesmo dia. | Na agenda, escolher P1, depois P2. | Cada visão mostra só os horários daquele profissional. | API + FLU |
| CT-02-02 | P1 logado (não gerente). | Abrir a agenda. | Mostra só a agenda de P1, sem seletor de outros profissionais. (O bloqueio no servidor está no CT-00-12.) | FLU |
| CT-02-03 | Expediente de P1 08:00–19:00. | Abrir a agenda de P1. | Antes de 08:00 e depois de 19:00 aparece em cinza e não abre ações. | FLU |
| CT-02-04 | — | Pela API, marcar para P1 às 07:30. | Recusado: fora do expediente vale no servidor, não só na cor. | API |
| CT-02-05 | Horário livre. | Tocar nele. | Aparecem as opções Marcar e Bloquear. | FLU |
| CT-02-06 | Horário marcado. | Tocar nele. | Aparecem Concluir, Marcar falta e Cancelar. Nada disso aparece num horário cancelado, concluído ou com falta. | FLU |
| CT-02-07 | P1 logado. Horário livre dele às 14:00. | Bloquear 14:00–14:30 (o menor bloqueio). | Aceito. Fica ocupado na agenda. Some dos livres do cliente. Tentar agendar 14:00 pelo app dá conflito. | API |
| CT-02-08 | P1 tem 14:00–14:30 `agendado`. | Tentar bloquear 13:30–15:00 (sobreposição parcial com a marcação). | Recusado com conflito pela mesma trava das marcações. Nada criado. | API |
| CT-02-09 | P1 logado. Horário dele `agendado`. | Concluir. | Status `concluido`. Preço e % de P1 gravados (CT-20-04). Entra no caixa (CT-08). | API |
| CT-02-10 | P1 logado. Horário dele `agendado`. | Marcar falta. | Status `falta`. Final. Não entra no caixa. O horário volta a ficar livre (CT-06-11). | API |
| CT-02-11 | Horário `agendado` às 15:00. Relógio em 3 momentos: 14:00 (1h antes), 14:59 (1 min antes) e 15:10 (já começou, ainda não concluído). | Gerente cancela. Em outro horário, P1 cancela um da própria agenda. | Aceito nos 3 momentos: a Casa cancela a qualquer hora antes de concluir. A regra das 2h não vale pra Casa. O cancelamento grava que foi a barbearia. | UNI + API |
| CT-02-12 | Horário `agendado` às 15:00. | Concluir com o relógio em 14:59:00, 14:59:59 e 15:00:00. | 14:59:00 e 14:59:59: recusado com erro próprio e o status continua `agendado`. 15:00:00: aceito. | UNI + API |
| CT-02-13 | Servidor real. | Cliente agenda pelo app. Casa abre a agenda. | O horário aparece na agenda da Casa com o nome do cliente. | MAN (com servidor) |
| CT-02-14 | Horário `agendado` às 15:00. | Marcar falta com o relógio em 14:59:00 e 15:00:00. | 14:59: recusado, status continua `agendado`. 15:00: aceito. | UNI + API |
| CT-02-15 | P1 logado. Dia livre. | Bloquear 14:00–16:00. | Aceito. Os livres de 14:00 a 15:30 somem para todos os serviços, e o Combo das 13:30 também (bate em 14:00). | UNI + API |
| CT-02-16 | P1 logado. | Bloquear 10:15–11:00 e 10:00–10:45. | Os 2 recusados (422): início ou fim fora da grade de 30 min. | UNI + API |
| CT-02-17 | P1 logado. | Bloquear 23:00 de hoje até 00:30 de amanhã. | Recusado (422): o bloqueio não atravessa a meia-noite. Terminar exatamente às 00:00 é aceito (CT-02-21). | UNI + API |
| CT-02-18 | P1 logado. | Bloquear 11:00–11:00 e 11:00–10:30. | Os 2 recusados (422): o fim tem que ser depois do início. | UNI + API |
| CT-02-19 | P1 tem um bloqueio 14:00–16:00 e marcações `agendado` às 13:00 e 16:00. | P1 desbloqueia o próprio bloqueio. Em outro teste, G-A desbloqueia um bloqueio de P1. | Os 2 aceitos. 14:00–15:30 voltam aos livres. As marcações das 13:00 e 16:00 continuam iguais (mesmo id, horário e status), e nenhuma marcação é criada ou cancelada (conferir no banco). | API + INT |
| CT-02-20 | P1 logado. P2 tem um bloqueio. | P1 tenta desbloquear o bloqueio de P2. | 403. O bloqueio continua. | API |
| CT-02-21 | P1 logado. Expediente de P1 na sexta até o fim do dia (00:00). Servidor em UTC. | Bloquear sexta 23:30–00:00 (fim = sábado 00:00 BRT). Pedir a agenda de sexta e a de sábado. | Aceito: termina às 00:00, que conta como fim da sexta. O bloqueio aparece só na agenda de sexta. Na de sábado não aparece nada, e o slot de sábado 00:00 (se houver expediente) continua livre. | UNI + API |
| CT-02-22 | P1 logado (não gerente). | `GET /agenda?date=…` sem filtro, com `professionalId` = P1 e com `professionalId` = P2. | Sem filtro: 200 só com P1. Com P1: 200. Com P2: **403** e nenhum dado de P2 (não é lista vazia nem filtro silencioso). | API |
| CT-02-23 | Horário de P1 `agendado` às 15:00. Agora = 15:10. Gerente e P1 com a agenda aberta. | Gerente conclui. Depois P1, com a tela velha, marca falta (com outra `Idempotency-Key`). | O pedido de P1 leva 409 `STATUS_CHANGED`. O status continua `concluido`. O app Casa de P1 recarrega e mostra concluído, sem as ações velhas. | API + FLU |

### CT-06 · (6) Horário de balcão e marcação pela Casa

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-06-01 | P1 livre às 11:00. | Lançar balcão Corte 11:00 só com nome, sem telefone. Conferir no banco. | Aceito. A ficha volta com `phone` = `null`. Preço gravado. Cria **só a ficha da A** (nenhum cliente por telefone), que a B não vê e que não conta no limite de 2 de ninguém. | API + INT |
| CT-06-02 | — | Lançar balcão com telefone. | Aceito. O telefone fica no agendamento. | API |
| CT-06-03 | P1 tem 11:00–11:30. | Lançar balcão Combo 10:30–11:30. | Recusado com conflito (sobreposição parcial). | API |
| CT-06-04 | Expediente até 19:00. | Lançar balcão Combo às 18:30. | Recusado (passa do fim do expediente). | API |
| CT-06-05 | T1 já tem 2 futuros marcados pelo app. | Lançar balcão com T1 e marcar outro pela agenda da Casa com T1. | Os 2 aceitos: o limite de 2 não vale pra Casa. | API |
| CT-06-06 | Agora = 10:00:00. P1 livre às 10:00. | Lançar balcão às 10:00. Em outro teste, marcar 10:00 pela agenda da Casa. | Os 2 aceitos: os 30 min de antecedência não valem pra Casa. | UNI + API |
| CT-06-07 | — | Abrir o formulário de balcão no app Casa. | Telefone é opcional. Salvar sem telefone funciona. | FLU |
| CT-06-08 | Hoje = 07/10. | A Casa marca (pela agenda e pelo balcão) em 20/10 (hoje + 13) e em 21/10 (hoje + 14). | 20/10 aceito. 21/10 dá 422 `DATE_OUT_OF_RANGE`: os 14 dias valem pra Casa. | UNI + API |
| CT-06-09 | T1 tem 1 futuro pelo app e 2 futuros marcados pela Casa. | T1 agenda pelo app. Depois tenta mais um pelo app. | O 1º é aceito (marcação da Casa não conta no limite). O 2º é recusado (já são 2 pelo app). | API |
| CT-06-10 | Agora = 10:10. Slots 09:30 e 10:00 de P1 livres. | A Casa marca Corte às 10:00 (em andamento) e às 09:30 (já terminou). | 10:00 aceito. 09:30 recusado com erro de horário passado. | UNI + API |
| CT-06-11 | P1 tem Corte 15:00–15:30 `agendado`. | Às 15:05, marcar falta. Às 15:10, a Casa lança balcão Corte às 15:00 para P1. | Os 2 aceitos: a falta libera o horário e o slot das 15:00 ainda está em andamento. No caixa entra só o balcão. | API |
| CT-06-12 | Slot 10:00 de P1 livre. | A Casa marca 10:00 com o relógio em 10:29:59 e, em outro teste, em 10:30:00. | 10:29:59: aceito (slot ainda em andamento). 10:30:00: recusado (o slot terminou). | UNI |
| CT-06-13 | Agora = 10:10. 10:00 e 10:30 de P1 livres. | A Casa marca Combo às 10:00 (10:00–11:00). Em outro teste, Combo às 09:30. | Combo 10:00 aceito: o 1º slot está em andamento. Combo 09:30 recusado: o slot de início já terminou. | UNI + API |
| CT-06-14 | Agora = 10:10. P1 livre o dia todo. | Pelo app do cliente, pedir livres e agendar 10:00 e 10:30. | Os 2 recusados (o 10:30 está a 20 min). O primeiro livre do cliente é 11:00. A regra de em andamento é só da Casa. | UNI + API |
| CT-06-15 | — | Lançar balcão sem nome (vazio e só espaços), com e sem telefone. | 422 `VALIDATION_ERROR` com o campo `name`. Nada gravado. | API |
| CT-06-16 | T1 tem ficha na A. | Lançar balcão com o telefone escrito `(11) 98765-4321`. | Aceito, sem recusa por formato. O atendimento liga ao mesmo cliente de T1, e o telefone volta como `+5511987654321`. Não cria cliente nem ficha nova. | API |

### CT-07 · (7) Expediente e folgas

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-07-01 | G-A logado. | Definir P1 de terça 10:00–18:00. | Os livres de Corte de terça de P1 vão de 10:00 a 17:30. | API |
| CT-07-02 | G-A logado. | Marcar folga de P1 na sexta. | Sexta não tem livres de P1. P2 continua com livres. | API |
| CT-07-03 | P1 tem sexta 15:00 `agendado`. | G-A marca folga de P1 na sexta. | O agendamento **continua valendo** (não é apagado nem cancelado). Aparece destacado na agenda da Casa. O cliente ainda vê o horário. | API + FLU |
| CT-07-04 | P1 tem 18:00 agendado. | G-A reduz o expediente de P1 para terminar 17:00. | O agendamento das 18:00 continua valendo e aparece destacado. Não abre livres novos depois das 17:00. | API |
| CT-07-05 | — | Salvar expediente com fim antes do início, ou com hora inválida. | Recusado (422). O expediente antigo fica. | UNI + API |
| CT-07-06 | — | Mudar o expediente de P1 depois que os livres de amanhã foram calculados. | O próximo pedido de livres já reflete a mudança (sem cache velho). | API |
| CT-07-07 | P1 logado. | Tentar mudar o próprio expediente e marcar a própria folga. | 403. Expediente e folgas são só do gerente. Nada muda. | API |

### CT-17 · (17) Clientes

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-17-01 | G-A logado. | Cadastrar cliente com nome, telefone e e-mail. | Aceito, ligado à Barbearia A. | API |
| CT-17-02 | — | Cadastrar sem nome, com telefone inválido ou e-mail inválido. | Recusado (422) com o campo que falhou. | API |
| CT-17-03 | T1 já cadastrado na A. | Cadastrar outro cliente com T1 na A. | Recusado (telefone repetido na mesma barbearia). | INT + API |
| CT-17-04 | Clientes "João Almeida" (T1) e "Ana". | Buscar "joão", "JOAO", "alm", `(11) 98765-4321` e `98765`. | Acha o João nos 5 casos. A busca por telefone tira o que não é dígito antes de procurar. | API |
| CT-17-05 | A Barbearia B tem cliente "João B". | G-A busca "joão". | "João B" não aparece. | API |
| CT-17-06 | — | Cadastrar e buscar pelo app Casa. | O cliente novo aparece na busca sem precisar reabrir a tela. | FLU |
| CT-17-07 | P1 logado. | Buscar e cadastrar cliente. | Depende da [pergunta do profissional em Clientes](#perguntas-em-aberto). | API |
| CT-17-08 | T1 tem ficha na B com nome "João Silva" e e-mail. Não tem ficha na A. | G-A cadastra T1 na A com nome "João". | Aceito. Cria a ficha da A ligada ao mesmo cliente (mesmo telefone). A resposta não traz nada da ficha da B (nome, e-mail, histórico) nem avisa que ela existe. | API + INT |
| CT-17-09 | T1 tem ficha na A e na B. | G-A muda o nome e o e-mail de T1 na A. | A ficha da B continua igual (conferir no banco). | INT |
| CT-17-10 | T1 tem agendamentos na A e na B. | G-A abre a ficha e o histórico de T1. G-B faz o mesmo. | Cada um vê só a própria ficha e só os agendamentos da própria barbearia. | API |
| CT-17-11 | — | Teste parametrizado da normalização: `(11) 98765-4321`, `11987654321`, `+55 11 98765-4321`, `5511987654321` e o fixo `(11) 3456-7890`. | Os 4 primeiros viram `+5511987654321`. O fixo vira `+551134567890`. | UNI |
| CT-17-12 | — | Cadastrar e agendar com `987654321` (9 dígitos), `119876543210` (12 dígitos sem 55 no começo), `1198765432101` (13 sem 55), `11 9876-ABCD` (letras), `+55987654321` (só 9 dígitos depois do +55), `+1 212 555 0100` e `+351 912 345 678` (país diferente de 55). | Todos recusados (422) com o código de telefone inválido. Nada gravado. | UNI + API |
| CT-17-13 | T1 cadastrado na A como `(11) 98765-4321`. | Cadastrar `+55 11 98765-4321` na A. Depois `11987654321` na B. | Na A: recusado (mesmo cliente, ficha já existe). Na B: aceito como ficha nova do **mesmo** cliente. | API |
| CT-17-14 | Banco migrado. | Inserir direto no banco 2 clientes com o mesmo T1 normalizado. Inserir 1 com `(11) 98765-4321` (fora do formato normalizado). | 1º caso: violação da constraint única. 2º caso: recusado por constraint de formato (normalizado, `55` + 10 ou 11 dígitos). | INT |
| CT-17-15 | T1 ainda não existe. | **Concorrência real:** agendar pelo app na A com `(11) 98765-4321` e na B com `5511987654321` ao mesmo tempo, do mesmo aparelho (K1). | Existe 1 cliente só para T1 no banco, com as fichas certas. Nenhum erro 500. | INT |
| CT-17-16 | Cliente T1 (`+5511987654321`) existe. | Normalizar `(11) 8765-4321` (10 dígitos). Cadastrar esse número na A e agendar com ele pelo app. | Vira `+551187654321` (fixo, **sem** o 9 acrescentado). É outro cliente: não junta com T1, e o limite de 2 de um não conta pro outro. | UNI + API |
| CT-17-17 | — | Teste parametrizado do 55 com e sem `+`: `55987654321`, `(55) 98765-4321`, `+55 55 98765-4321`, `5532345678`, `551134567890`, `5511987654321` e `+5511987654321`. | `55987654321`, `(55) 98765-4321` e `+55 55 98765-4321` viram `+5555987654321` (o mesmo cliente). `5532345678` vira `+555532345678`. `551134567890` vira `+551134567890`. Os dois últimos viram `+5511987654321`. | UNI |
| CT-17-18 | G-A logado. Aparelho com K1. | Mandar T1 com máscara (`(11) 98765-4321`, `11 98765 4321`, `11.98765.4321`, `+55 (11) 98765-4321`) em todas as entradas: agendar pelo app, marcar pela Casa, balcão, cadastrar, editar a ficha e buscar. | Todas aceitas, **nunca 422 por formato**. Todas ligam ao mesmo cliente, e toda resposta traz `+5511987654321`. | API |
| CT-17-19 | K1 (D1) preso a T1. T1 tem 1 horário futuro pelo app na A. G-A logado. | Na ficha de T1 na A, G-A toca em "Liberar aparelho" (`POST …/clients/{clientId}/release-device`). Logo depois, com K1: listar Meus horários, cancelar o horário e agendar outro. | Liberação aceita. **K1 para de valer na hora:** as 3 chamadas dão 401, sem nenhum dado. O horário futuro continua `agendado` (mesmo id, horário e profissional) e continua na agenda da Casa. | API + INT |
| CT-17-20 | Depois do CT-17-19 (T1 sem aparelho, com 1 futuro). | D2 (K2) agenda com T1. Listar Meus horários com K2. Depois, com K2, tentar um 3º horário futuro. Por fim, D3 (K3) agenda com T1. | O agendamento de D2 é aceito, e K2 fica preso a T1. Meus horários de K2 mostra o horário antigo e o novo. O 3º dá `BOOKING_LIMIT_REACHED`, porque o horário antigo conta no limite. D3 leva 409 `PHONE_ON_OTHER_DEVICE`. | API |
| CT-17-21 | K1 preso a T1, que tem ficha na A e agendamento pelo app na A. | Chamar `POST …/clients/{clientId}/release-device` da ficha de T1 na A com P1 (profissional da A que não é gerente) e com G-B (gerente da B, sem vínculo com a A). Depois com G-A. | P1: **403**. G-B: **404** (regra geral do contrato pra quem não tem vínculo com a barbearia). Nos dois casos, K1 continua valendo. G-A: aceito. A rota entra na varredura de papel do CT-00-24 e na de multi-tenant do CT-00-28. | API |
| CT-17-22 | App Casa, mock e servidor. | Abrir a ficha de um cliente logado como gerente e como profissional que não é gerente. | O botão "Liberar aparelho" aparece só pro gerente. Ao tocar, a liberação é feita e a tela mostra que deu certo. O profissional não vê o botão. | FLU |
| CT-17-23 | K1 preso a T1. | **Concorrência real:** G-A libera o aparelho de T1 e D1 agenda com K1 ao mesmo tempo. Repetir 20 vezes. | No fim, K1 sempre está inválido. Nenhum agendamento é gravado com K1 depois da liberação. Se o agendamento de D1 entrou antes, ele continua `agendado` e aparece pro próximo aparelho (CT-17-20). | INT |
| CT-17-24 | T1 tem ficha na A e na B, com 1 futuro pelo app em cada uma (K1). | G-A libera o aparelho de T1 pela ficha da A. Com K1, listar Meus horários e cancelar o horário da B. D2 (K2) agenda com T1 na A e lista Meus horários. Em outro teste, G-B libera pela ficha da B. | A liberação vale **em todas as barbearias**: K1 dá 401 também no horário da B, que continua `agendado`. K2 fica preso a T1 e vê os horários da A e da B. A B não recebe nenhum aviso (no MVP não tem aviso). Liberar pela ficha da B tem o mesmo efeito, porque T1 também tem agendamento pelo app na B e passa na trava proposta (**depende da confirmação do PO**, [pergunta 8](#perguntas-em-aberto); ver CT-17-28). | API |
| CT-17-25 | T1 tem 2 futuros pelo app (K1). G-A libera o aparelho. | D2 (K2) agenda um 3º horário com T1. Depois, com K2, listar Meus horários. A Casa cancela 1 dos 2 horários. D2 agenda de novo. | 1ª tentativa: `BOOKING_LIMIT_REACHED`, e **K2 não fica preso** (Meus horários com K2 dá 401, sem dados). Os 2 horários continuam `agendado`. Depois do cancelamento pela Casa, o agendamento de D2 é aceito, K2 fica preso a T1 e vê o horário que sobrou e o novo. (Ver as [Observações](#observações).) | API |
| CT-17-26 | K1 preso a T1. Na A, a ficha de T1 foi criada só no balcão (com o telefone de T1 digitado por outra pessoa), sem nenhum agendamento pelo app na A. | G-A chama a liberação pela ficha da A. | **Depende da confirmação do PO** ([pergunta 8](#perguntas-em-aberto)): 409 `DEVICE_RELEASE_NOT_ALLOWED`. K1 continua valendo, e nada muda nos horários de T1. | API |
| CT-17-27 | K1 preso a T1, com 1 agendamento feito pelo app na A. | G-A chama a liberação pela ficha da A. | **Depende da confirmação do PO** ([pergunta 8](#perguntas-em-aberto)): aceito, e K1 para de valer (como no CT-17-19). | API |
| CT-17-28 | K1 preso a T1. T1 tem agendamento pelo app só na A e uma ficha na B criada no balcão (nunca agendou pelo app na B). | G-B chama a liberação pela ficha da B. | **Depende da confirmação do PO** ([pergunta 8](#perguntas-em-aberto)): 409 `DEVICE_RELEASE_NOT_ALLOWED`. K1 continua valendo, inclusive nos horários da A. | API |

### CT-10 · (10) Preços, serviços e profissionais

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-10-01 | Corte custa R$ 40,00. Existe agendamento futuro de Corte. | G-A muda o Corte para R$ 45,00. | Agendamentos novos gravam R$ 45,00. O antigo continua com R$ 40,00 (preço gravado). | API |
| CT-10-02 | — | Salvar preço zero, negativo, com 3 casas decimais ou texto. | Recusado (422). | UNI + API |
| CT-10-03 | — | G-A inclui o profissional P3. | P3 aparece na agenda da Casa e na página da barbearia, e ganha livres quando tiver expediente. A % dele começa em 60/40. | API |
| CT-10-04 | P3 sem horário futuro ativo. | G-A desativa P3. Tentar também apagar P3. | Desativação aceita: P3 continua no banco, desativado. Some da agenda da Casa, da página do cliente e da tela Agendar. Histórico e caixa dele continuam. Não existe rota que apague profissional (DELETE dá 404/405). | API |
| CT-10-05 | P1 tem 1 horário futuro `agendado`. | G-A desativa P1. Depois cancela esse horário e desativa de novo. | 1ª vez: recusado com erro próprio e P1 continua ativo. 2ª vez (sem futuro ativo): aceito. | API |
| CT-10-06 | Barba dura 30 min. Existe Barba agendada amanhã 10:00–10:30. | G-A muda a Barba para 60 min. | Os livres de Barba passam a exigir 2 horários seguidos (como o Combo). O agendamento antigo continua 10:00–10:30 (duração gravada na marcação). | API |
| CT-10-07 | — | Salvar serviço com duração zero ou negativa. | Recusado (422). Duração que não é múltiplo de 30: depende da [pergunta da duração](#perguntas-em-aberto). | UNI + API |
| CT-10-08 | P1 tem futuros só `cancelado` e passados `concluido`/`falta`. | G-A desativa P1. | Aceito: só horário futuro ativo trava a desativação. | API |
| CT-10-09 | P3 desativado, com concluídos em outubro. | Pedir livres de P3. Agendar com P3 pelo app e pela Casa. G-A abre o caixa de outubro. | Livres vazios e agendamentos recusados. O caixa de outubro continua mostrando os valores de P3. | API |

### CT-08 · (8) Caixa do mês

Base dos casos CT-08-01 a CT-08-03: P1 com 60/40 e P2 com 70/30 (profissional/casa), todos em outubro.

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-08-01 | Concluídos: P1 Corte R$ 40 + Combo R$ 65; P2 Barba R$ 30. | G-A abre o caixa de outubro. | Total concluído R$ 135,00. P1 R$ 63,00, P2 R$ 21,00, casa R$ 51,00 (42,00 de P1 + 9,00 de P2). 63 + 21 + 51 = 135. | INT + API |
| CT-08-02 | Base do CT-08-01 + 1 `falta` de P1 (Corte R$ 40) + 1 `cancelado` de P2 (Corte R$ 40). | Abrir o caixa. | Tudo igual ao CT-08-01: falta e cancelado não entram. | API |
| CT-08-03 | Base do CT-08-01 + 1 balcão `concluido` de P1 (Barba R$ 30, sem telefone). | Abrir o caixa. | Balcão entra normalmente: total R$ 165,00, P1 R$ 81,00, casa R$ 63,00, P2 R$ 21,00. | API |
| CT-08-04 | Concluído em setembro. | Abrir outubro. | Não entra. Setembro continua igual. | API |
| CT-08-05 | Gerador de casos: preços e % variados, inclusive valores que geram meio centavo e fração de centavo. | Somar parte da casa + parte do profissional, por agendamento e no mês. | **A soma bate com o preço gravado e com o total concluído, centavo por centavo.** Caixa da casa + ganho de todos os profissionais = total concluído. | UNI |
| CT-08-06 | Barbearia B tem concluídos em outubro. | G-A abre o caixa. | Só valores da A. | API |
| CT-08-07 | Servidor em UTC. Expediente de P1 em 31/10 até 23:30. Horário 31/10 23:00 BRT (= 01/11 02:00 UTC), concluído às 23:20 BRT. | Abrir o caixa de outubro e o de novembro. | Entra em **outubro** (data do atendimento em SP), não em novembro. | INT |
| CT-08-08 | Horário de 31/10 às 18:00, concluído só em 01/11 às 09:00. | Abrir outubro e novembro. | Entra em **outubro** (data do atendimento), não em novembro (data da conclusão). | INT |
| CT-08-09 | P1 logado. Base do CT-08-03. | Abrir "meu ganho do mês". | Mostra só P1: R$ 81,00 e os agendamentos dele. Não mostra total da casa nem valores de P2. | API + FLU |
| CT-08-10 | P1 logado (não gerente). Base do CT-08-03. | Pedir o ganho de P2 pela API: `GET /cash/professionals/{id de P2}?month=2026-10`. | 403. Nenhum valor de P2 volta (nem total, nem agendamentos). | API |
| CT-08-11 | Horário de P1 em outubro ainda `agendado` (passou a hora e ninguém concluiu). | Abrir o caixa. | Não entra. | API |
| CT-08-12 | O gerente já consultou o caixa de outubro. | Em 02/11, concluir um horário de 31/10. Abrir outubro de novo. | Outubro passa a incluir esse valor, com a % do momento da conclusão. Novembro não muda. | INT + API |
| CT-08-13 | P1 logado (não gerente). Base do CT-08-03. | `GET /cash?month=2026-10`. | **200.** Só a linha de P1: `grossCents` = 13500 (R$ 135,00 dos 3 atendimentos dele) e `professionalCents` = 8100 (R$ 81,00). O campo `shopCents` **não vem** (ausente, nem `null` nem zero), nem na linha nem em `totals`. Não aparece a linha de P2 (R$ 21,00) nem o total da barbearia (R$ 165,00 bruto, R$ 63,00 da casa) em nenhum campo. Repetir com P1 sem nenhum concluído no mês: 200 com a linha dele zerada, sem `shopCents`, e continua sem dados dos outros. | API |
| CT-08-14 | P1 logado (não gerente). Base do CT-08-03. | `GET /cash/professionals/{id de P1}?month=2026-10`. | **200.** Só os agendamentos concluídos de P1 em outubro. `totals` com `grossCents` = 13500 e `professionalCents` = 8100, **sem o campo `shopCents`**. Nenhum agendamento de P2. | API |
| CT-08-15 | G-A logado (gerente). Base do CT-08-03. | `GET /cash?month=2026-10`, `GET /cash/professionals/{id de P1}` e `GET /cash/professionals/{id de P2}`. | **200 nos três.** O caixa traz o total da barbearia (R$ 165,00 bruto, R$ 63,00 da casa) e as linhas de P1 (R$ 81,00) e de P2 (R$ 21,00). Cada rota de profissional traz os agendamentos dele. Pro gerente, o `shopCents` vem em `totals` e em todas as linhas (R$ 54,00 de P1 e R$ 9,00 de P2). Repetir com G-P2 (gerente e profissional): o mesmo resultado, não só a linha dele. | API |

### CT-20 · (20) Gerência (%)

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-20-01 | Profissional novo, sem % definida. | Ler a % dele. | 60% profissional e 40% casa. | API |
| CT-20-02 | G-A logado. | Salvar para P1: 70/30, 100/0 e 0/100. | Os 3 aceitos (somam 100). | UNI + API |
| CT-20-03 | G-A logado. | Salvar para P1: 60,5/39,5 (decimal), -1/101, 101/-1, 70/40 (110), 50/49 (99), texto e só um dos dois valores. | Todos recusados (422). A % de P1 não muda. | UNI + API |
| CT-20-04 | P1 com 60/40. Horário `agendado`. | Concluir. | O agendamento grava 60/40 (e o preço) no momento da conclusão. | INT |
| CT-20-05 | Horário de P1 concluído em outubro com 60/40. | G-A muda P1 para 50/50. Abrir o caixa de outubro de novo. | O caixa de outubro **não muda**. | INT + API |
| CT-20-06 | Horário de P1 marcado quando a % era 60/40. | G-A muda P1 para 50/50. Depois concluir. | Grava 50/50 (vale a % do momento da conclusão). | INT |
| CT-20-07 | P1 60/40, P2 70/30. | G-A muda só P1 para 50/50. Concluir 1 horário de cada. | P1 grava 50/50 e P2 continua 70/30. A % é por profissional. | INT |
| CT-20-08 | — | Teste parametrizado do cálculo (preço, % do profissional → profissional / casa):<br>R$ 0,05 a 50% → 0,03 / 0,02<br>R$ 0,01 a 50% → 0,01 / 0,00<br>R$ 33,33 a 60% → 20,00 / 13,33<br>R$ 33,33 a 50% → 16,67 / 16,66<br>R$ 10,01 a 33% → 3,30 / 6,71<br>R$ 40,00 a 0% → 0,00 / 40,00<br>R$ 40,00 a 100% → 40,00 / 0,00 | Todos exatos. Meio centavo vai pra cima no valor do profissional e a casa fica com o resto. O caso R$ 33,33 a 50% pega quem calcula com `double` (daria 16,66). | UNI |
| CT-20-09 | P1 com 60%. Horário de R$ 33,33 `agendado`. | Concluir. Ler o agendamento no banco e abrir o caixa. | Gravado: profissional R$ 20,00 e casa R$ 13,33. O caixa mostra esses mesmos valores, sem recalcular. | INT + API |
| CT-20-10 | P1 logado (não gerente). | `GET /commission` e `PUT /commission` (mudando a % de P1 e a de P2). Repetir o GET e o PUT com G-A. | P1: **403** nos dois, nenhuma % volta e nada muda no banco. G-A: 200 nos dois. Ver o próprio caixa (CT-08-13) não dá acesso à %. | API |

(Profissional tentando mudar a %: CT-00-16.)

### CT-09 · (9) Visual

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-09-01 | Pacote de tema. | Ler as cores do tema. | `#000000`, `#1C1C1E`, `#2C2C2E`, `#FFFFFF`, `#8E8E93`, `#AEAEB2` e amarelo `#E6B325`. **Nenhum `#636366`.** Nenhuma cor solta fora do tema nas telas. | FLU |
| CT-09-02 | Tema com a lista de pares texto/fundo usados. | Teste que calcula o contraste de cada par (fórmula WCAG). | Todo texto ≥ 4,5:1. Os valores batem com a tabela da [seção 2](#2-regras-confirmadas). Texto preto no `#E6B325` dá 10,83:1. | FLU (unitário Dart) |
| CT-09-03 | — | Procurar uso de `#8E8E93` sobre `#2C2C2E` e de texto branco sobre `#E6B325`. | Nenhum (4,27:1 e 1,93:1, os dois reprovam). Texto secundário em card `#2C2C2E` usa `#AEAEB2`. | FLU |
| CT-09-04 | — | Conferir onde o amarelo aparece, em todas as telas dos 2 apps. | Só na aba ativa, no profissional escolhido, no botão principal e no ponto ativo da introdução. Em mais nenhum lugar. | FLU (golden) + MAN |
| CT-09-05 | Tela de introdução. | Ver o rótulo acima do título e o "Próximo". | Os dois brancos `#FFFFFF`, não amarelos (vale a regra escrita, não o print). | FLU + MAN |
| CT-09-06 | — | Ver o botão principal (normal e pressionado). | Fundo `#E6B325` e texto preto `#000000`. | FLU |
| CT-09-07 | — | Golden test das telas principais (Intro, Início, Barbearia, Agendar, Meus horários, Agenda, Caixa, Clientes, Menu). | Bate com a imagem aprovada. Mudança visual exige atualizar o golden no mesmo PR. | FLU |
| CT-09-08 | Celular em modo avião. | Abrir os títulos. | Inter peso 800 aparece mesmo sem internet (fonte empacotada no app, não baixada). | MAN |
| CT-09-09 | — | Comparar com a regra escrita e com o protótipo em `/workspace/cortaaqui-grok/`. | Fundo preto, cards cinza, menu de linha fina, mesma hierarquia de texto. Onde o print e a regra diferem, vale a regra. | MAN |
| CT-09-10 | Fonte do Android em tamanho máximo. Celular pequeno (360 dp). | Navegar pelas telas. | Nenhum texto cortado nem botão escondido. | MAN |
| CT-09-11 | Tema e menu de baixo. | Teste de contraste das abas inativas (texto e ícone) sobre `#000000` e do placeholder do campo sobre o fundo do campo `#1C1C1E`. Procurar `#636366` no código. | Abas inativas e placeholder em `#8E8E93`: 6,44:1 e 5,21:1, os dois ≥ 4,5:1. `#636366` não aparece (dava 3,51:1 e 2,84:1, os dois reprovam). Se o campo ficar sobre `#2C2C2E`, o placeholder usa `#AEAEB2`. | FLU |

### CT-13 · (13) Nome CortaAqui

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-13-01 | APKs gerados. | Instalar os 2 apps. | O nome embaixo do ícone tem "CortaAqui" nos dois (Cliente e Casa distinguíveis). | MAN |
| CT-13-02 | Workflow de APK. | Rodar o workflow. | O nome do workflow, do artifact, da release e dos arquivos `.apk` tem "CortaAqui". | MAN (CI) |
| CT-13-03 | Repo. | Passo na CI que procura "Navalha" em textos visíveis do app e no workflow. | Nenhuma ocorrência, exceto o nome da barbearia do seed ("Barbearia Navalha"). | CI |

### CT-00 · Transversal

**Status só anda pra frente**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-01 | — | Testar todas as transições (teste parametrizado). | Aceitas só: `agendado` → `concluido`, `falta` ou `cancelado`. As 12 transições que saem de um status final (3 finais × 4 destinos, inclusive o mesmo status e a volta para `agendado`) são recusadas. | UNI |
| CT-00-02 | Horário `cancelado`. | Pela API, com chaves novas: concluir, marcar falta e "reabrir". | Recusado com 409 `STATUS_CHANGED`. O banco não muda. | API |
| CT-00-03 | Horário `agendado`. | **Concorrência real:** cliente cancela e Casa conclui ao mesmo tempo, em conexões separadas. Repetir 50 vezes. | Sempre só 1 vale. O outro recebe 409 `STATUS_CHANGED`. O status final é o do vencedor e o caixa bate com ele. | INT |

**Pedido repetido (mesmo identificador)**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-04 | — | Mandar o mesmo POST de agendamento 2 vezes com o mesmo identificador. | 1 agendamento só. A 2ª resposta devolve o mesmo agendamento (mesmo id), sem erro de conflito. Conta 1 no limite do telefone. | API |
| CT-00-05 | — | Mesmo identificador, 2 pedidos **ao mesmo tempo**. | 1 agendamento só. | INT |
| CT-00-06 | — | Mesmo cancelamento (mesma `Idempotency-Key`) 2 vezes, pelo cliente e pela Casa. | A 2ª é ignorada e devolve o mesmo resultado (200, mesmo agendamento), não `STATUS_CHANGED`. | API |
| CT-00-07 | — | Dois POST com dados iguais e identificadores diferentes. | São 2 pedidos: o 2º leva conflito. | API |
| CT-00-08 | — | Mesmo identificador com dados diferentes. | Depende da [pergunta do identificador](#perguntas-em-aberto). | API |

**Login**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-09 | G-A cadastrado. | Login com e-mail e senha certos. Depois com senha errada e com e-mail inexistente. | Certo: token. Errados: 401 com a mesma mensagem nos dois casos. | API |
| CT-00-10 | — | Ler a senha gravada no banco. | Hash BCrypt (começa com `$2`), nunca texto puro. Senha não aparece em log nem em resposta. | INT |
| CT-00-11 | — | Chamar rotas da Casa sem token, com token alterado e com o código de cliente. | 401/403 em todas. | API |

**Papéis: profissional que não é gerente** (todos barrados **no servidor**, conferindo no banco que nada mudou)

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-12 | P1 logado. P2 tem horários. | Ler a agenda de P2 e um horário de P2 pelo id. | 403. Nenhum dado de P2 volta. | API |
| CT-00-13 | P1 logado. | Marcar, lançar balcão e bloquear na agenda de P2. | 403. Nada criado. | API |
| CT-00-14 | P1 logado. P2 tem horário `agendado`. | Concluir, marcar falta e cancelar esse horário. | 403. Status continua `agendado`. | API |
| CT-00-15 | P1 logado. | Pedir o ganho de P2 (`GET /cash/professionals/{id de P2}`) e o caixa (`GET /cash`). | Ganho de P2: 403 (mesmo teste do CT-08-10). Caixa: 200 só com a linha de P1, sem total da casa nem linhas dos outros (CT-08-13). | API |
| CT-00-16 | P1 logado. | Mudar a própria % e a % de P2. | 403. As duas % não mudam. | API |
| CT-00-17 | P1 logado. | Mudar preço e duração de um serviço, criar serviço, incluir e desativar profissional. | 403. Nada muda. | API |
| CT-00-18 | P1 logado. | Mudar expediente ou folga de P1 e de P2. | 403. Nada muda. | API |
| CT-00-19 | P1 logado. | Na própria agenda: marcar, lançar balcão, bloquear, concluir, marcar falta, cancelar e ver o próprio ganho. | Tudo aceito. | API |
| CT-00-20 | G-A logado. | Agenda de P1 e de P2, ações em horários dos dois, caixa da casa, %, preços, serviços e expediente. | Tudo aceito. | API |
| CT-00-21 | G-P2 (gerente e profissional). | Abrir a própria agenda, a agenda de P1 e a Gerência. | Aparece como profissional na agenda e na página do cliente, e tem tudo do gerente. | API + FLU |
| CT-00-22 | G-A (só gerente). | Abrir a agenda e a página do cliente. | Não aparece como profissional nem recebe agendamento. | API |
| CT-00-23 | P1 logado no app Casa. | Procurar Gerência, caixa da casa, preços, expediente e outros profissionais. | Não aparecem na tela. (A tela é só conforto; o que vale são os testes de servidor acima.) | FLU |
| CT-00-24 | OpenAPI com as rotas marcadas por papel. | **Varredura:** um teste chama toda rota só do gerente com token de P1, inclusive `GET` e `PUT /commission`. **Ficam fora:** `GET /cash` e `GET /cash/professionals/{id}`, que dão 200 filtrado pro profissional (cobertas pelo CT-08-10 e pelo CT-08-13 a CT-08-15). | 403 em todas as rotas da varredura. Rota nova entra na varredura sozinha. | API |

**Isolamento multi-tenant**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-25 | Dados na A e na B. | G-A lê, pelo id, agendamento, cliente, profissional, serviço, expediente, caixa e % da B. | 404 em todos (regra geral do contrato pra quem não tem vínculo com a barbearia). Nenhum dado da B na resposta. Nunca 200. | API |
| CT-00-26 | — | G-A e P1 tentam alterar, cancelar, concluir ou bloquear recursos da B. | Recusado. No banco, a B fica igual (conferir com SELECT). | API + INT |
| CT-00-27 | — | P1 manda `barbershop_id` da B no corpo ou na query. | O servidor ignora e usa a barbearia do token, ou recusa. Nunca grava na B. | API |
| CT-00-28 | OpenAPI do projeto. | **Varredura:** um teste percorre todas as rotas do contrato com token da A e ids da B. | Nenhuma resposta 2xx. Rota nova entra na varredura sozinha. | API |
| CT-00-29 | Banco migrado. | Consultar o schema. | Toda tabela de negócio tem `barbershop_id NOT NULL` com FK. | INT |

(Cliente vendo dados de outro cliente: CT-04-07 e CT-04-08. Listas da Casa só com itens da A: CT-08-06 e CT-17-05.)

**Fuso (America/Sao_Paulo com o servidor em UTC)**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-30 | Servidor e JVM em UTC. Relógio = 07/10 02:30 UTC (= 06/10 23:30 BRT). | Pedir "livres de hoje", "agenda de hoje" e o último dia que aceita agendamento. | "Hoje" é **06/10**. O último dia é 19/10 (hoje + 13). 20/10 é recusado. | INT + API |
| CT-00-31 | Mesmo relógio. | Agendar 07/10 09:00 (BRT). | Gravado como 07/10 12:00 UTC e devolvido como `2026-10-07T09:00-03:00`. | API |
| CT-00-32 | Celular com fuso de Lisboa ou com a hora adiantada 1h. | Abrir Meus horários e a agenda. Tentar agendar com 20 min de antecedência real. | Os horários aparecem na hora da barbearia (BRT). O servidor recusa o agendamento: vale a hora do servidor, não a do celular. | FLU + API |

**Modo mock**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-33 | Seed do mock (`app/lib/data/mock/mock_seed.dart`) e seed do servidor. | Comparar os dois, campo a campo. | Os mesmos **ids fixos** e os mesmos valores nos dois: Barbearia Navalha, profissionais Caio e Helena, Corte R$ 40,00 (30 min), Barba R$ 30,00 (30 min), Combo R$ 60,00 (60 min) e o mesmo cliente. Qualquer diferença de id, nome, preço ou duração reprova. | FLU + INT |
| CT-00-34 | Build mock. | Rodar os testes de widget com o cliente HTTP trocado por um que falha em qualquer chamada. | Nenhuma chamada de rede. Todas as telas funcionam. | FLU |
| CT-00-35 | APK mock, celular em modo avião desde a instalação. | Seguir o checklist da seção 8. | Tudo funciona, sem tela de erro de rede. | MAN |
| CT-00-36 | Mock. | Tentar no mock: encaixe duplo, Combo que não cabe no fim do expediente, 3º horário do mesmo telefone escrito de outro jeito, dia hoje + 14, 29 min de antecedência, cancelamento com menos de 2h, bloqueio fora da grade e balcão num slot já terminado. | O mock aplica as mesmas recusas do servidor, para o mouretz não ver um comportamento que depois muda. | FLU |
| CT-00-37 | Mock, app Casa logado como profissional do seed. | Tentar abrir a agenda do outro profissional e a Gerência. | O mock respeita os mesmos papéis do servidor. | FLU |

**Papel por barbearia e cliente único**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-38 | G-A logado (gerente só na A, sem vínculo com a B). | Escolher a B como barbearia ativa e chamar rotas da B (agenda, caixa, %, clientes). | 404 em tudo (sem vínculo com a B). Ser gerente na A não dá acesso nenhum na B. | API |
| CT-00-39 | PX logado, agindo na B (onde é profissional). | Pedir caixa da casa, %, preços e agenda de PB1. Depois usar a própria agenda na B. | 403 nas rotas de gerente e na agenda de PB1. Na própria agenda, tudo aceito. Ser gerente na A não vale na B. | API |
| CT-00-40 | PX logado, agindo na A (onde é gerente). | Usar rotas de gerente na A e conferir as respostas. | Tudo aceito. Nenhuma resposta traz dado da B. | API |
| CT-00-41 | Banco migrado. | Consultar o schema. | Telefone do cliente é único. A ficha tem `UNIQUE (barbershop_id, client_id)`. O vínculo pessoa–barbearia guarda o papel, com `UNIQUE (barbershop_id, user_id)`. | INT |
| CT-00-42 | T1 tem 1 futuro pelo app. | **Concorrência real:** T1 agenda pelo app na A e na B ao mesmo tempo, em conexões separadas. Repetir 20 vezes. | No máximo 1 aceito. Nunca 3 futuros pelo app para T1, somando as barbearias. | INT |
| CT-00-43 | Horário `agendado` e já no horário de início. | Mandar a mesma mudança de status (concluir) 2 vezes com a **mesma** `Idempotency-Key`. Repetir com 2 pedidos ao mesmo tempo. | 1 conclusão só. A 2ª resposta devolve o mesmo resultado (mesmo status, mesma % gravada), sem `STATUS_CHANGED`. O caixa conta 1 vez. | API + INT |
| CT-00-44 | Horário já `concluido` (ou `cancelado`). | Com uma chave **nova**: pedir o mesmo status que já está, outro status final e o cancelamento pelo cliente. | Os 3 recusados com 409 `STATUS_CHANGED`. O banco não muda. (Pedir o mesmo status com chave nova não é "ignorado": só a mesma chave é.) | API |
| CT-00-45 | Repositório fake que responde `STATUS_CHANGED`. | No app Cliente, cancelar. No app Casa, concluir, marcar falta e cancelar. | Nos dois apps, a tela mostra um aviso, recarrega o agendamento, mostra o status novo e tira as ações que não valem mais. Nada de tela de erro genérica. | FLU |

---

## 8. Checklist do teste manual do APK mock

Rodar antes de mandar o APK pro mouretz. Celular Android real, **modo avião ligado antes de abrir o app pela primeira vez**. Anotar modelo, versão do Android e número do build no PR.

**Instalação**
- [ ] Os 2 APKs instalam juntos, sem um substituir o outro.
- [ ] O nome e o ícone dizem CortaAqui (Cliente e Casa distinguíveis). Nada de "Navalha", exceto a barbearia do seed.

**App Cliente**
- [ ] Intro: 3 telas, Próximo, Pular e o indicador de 3 pontos funcionam. Só o ponto ativo é amarelo; o rótulo e o "Próximo" são brancos.
- [ ] Início: mostra o próximo horário do cliente do seed e a Barbearia Navalha.
- [ ] Página da barbearia: Corte R$ 40 (30 min), Barba R$ 30 (30 min) e Combo R$ 60 (60 min), e os profissionais Caio e Helena. Sem nota, avaliações, favoritar, pontos ou pagamento.
- [ ] Agendar: o seletor mostra 14 dias (hoje até hoje + 13).
- [ ] Os horários vão de 30 em 30 min. Filtrar manhã, tarde e noite separa certo (12:00 em tarde, 18:00 em noite).
- [ ] Horário com menos de 30 min não aparece.
- [ ] Combo: o último horário do dia não aparece quando não cabe no expediente; e não aparece quando o 2º horário está ocupado.
- [ ] Agendar um horário e vê-lo em Meus horários e no card do Início.
- [ ] Tentar o 3º horário futuro com o mesmo telefone, escrito de outro jeito (ex.: com +55): recusa com mensagem clara.
- [ ] Telefone com 9 dígitos ou com letras: recusa com mensagem clara.
- [ ] Telefone com máscara (`(11) 98765-4321`) é aceito.
- [ ] Em outro celular, agendar com o mesmo telefone do seed: aparece "Esse telefone já está em outro aparelho. Fale com a barbearia."
- [ ] Depois do 1º agendamento, o campo de telefone fica travado.
- [ ] Cancelar um horário com mais de 2h: some dos futuros e o horário volta a ficar livre.
- [ ] Horário com menos de 2h: sem botão de cancelar.
- [ ] Fechar à força e abrir: os dados continuam.

**App Casa como gerente**
- [ ] Entrar com o gerente do seed.
- [ ] Agenda: trocar de profissional. Fora do expediente aparece em cinza.
- [ ] Horário livre: Marcar e Bloquear funcionam. Bloquear um intervalo (ex.: 14:00–16:00) tira todos esses horários. O horário bloqueado não deixa marcar em cima.
- [ ] Desbloquear devolve os horários e não mexe nas marcações em volta.
- [ ] Horário marcado: Concluir, Marcar falta e Cancelar funcionam. Depois de final, não aparece ação nenhuma.
- [ ] Concluir ou marcar falta antes do horário de início é recusado com mensagem clara.
- [ ] Cancelar um horário que começa em menos de 2h funciona (a regra das 2h é só do cliente).
- [ ] Balcão sem telefone funciona. Balcão em cima de outro horário é recusado.
- [ ] Balcão no slot em andamento funciona e num slot que já terminou é recusado. Marcar depois de hoje + 13 é recusado.
- [ ] Marcar falta e lançar um balcão no mesmo horário funciona.
- [ ] Desativar um profissional com horário futuro é recusado. Sem horário futuro, ele some da agenda e o caixa dele continua.
- [ ] Expediente: fechar um dia que já tem horário. O horário continua lá, destacado.
- [ ] Clientes: buscar e cadastrar.
- [ ] Ficha do cliente: "Liberar aparelho" aparece pro gerente, e depois disso um outro celular consegue agendar com o telefone e vê os horários antigos.
- [ ] Preços: mudar um preço. O horário já marcado mantém o preço antigo.
- [ ] Caixa do mês: concluído e balcão concluído entram. Falta e cancelado não entram. Casa + profissionais = total.
- [ ] Gerência: % decimal, -1 e 101 são recusados.
- [ ] Gerência: % que não soma 100 é recusada. Mudar a % de um profissional não altera o caixa já fechado nem a % dos outros.

**App Casa como profissional (não gerente)**
- [ ] Vê só a própria agenda, sem seletor de outros profissionais.
- [ ] Marca, bloqueia, conclui, dá falta e cancela na própria agenda.
- [ ] Vê só o próprio ganho do mês.
- [ ] Não vê Gerência, caixa da casa, preços, serviços, expediente nem outros profissionais.

**Visual e uso**
- [ ] Fundo preto, cards cinza, Inter 800 nos títulos e menu de linha fina.
- [ ] Amarelo `#E6B325` só na aba ativa, no profissional escolhido, no botão principal e no ponto ativo da intro.
- [ ] Botão principal com texto preto. Texto cinza legível nos cards mais claros.
- [ ] Fonte do sistema no máximo: nada cortado.
- [ ] Voltar do Android funciona em todas as telas e não fecha o app sem querer.
- [ ] Girar a tela e trocar de app no meio do Agendar não perde a escolha nem trava.
- [ ] Nenhuma tela de erro de rede em modo avião.

## 9. Critérios para a QA dar OK num PR

A QA só aprova quando **todos** valem:

1. **Testes da história presentes:** cada caso `CT-xx-yy` deste plano que o PR cobre tem um teste automático (no nível pedido) ou, se for `MAN`, o resultado anotado na descrição do PR. O nome ou comentário do teste cita o ID (ex.: `@DisplayName("CT-03-07 ...")`).
2. **Rodando na CI:** os jobs Java e Flutter passam no PR. Teste marcado como `@Disabled`/`skip` sem motivo escrito e sem issue não conta.
3. **Postgres de verdade:** teste de constraint, concorrência, multi-tenant, papéis e fuso roda com Testcontainers, nunca com H2 ou mock de repositório.
4. **Falha sem a mudança, quando fizer sentido:** para regra nova ou correção de bug, o autor mostra na descrição do PR que o teste falha sem a mudança (ex.: rodar o CT-03-07 sem a constraint e ver os 2 inserts passarem; tirar a checagem de papel e ver o CT-00-12 passar a dar 200). Para refatoração e visual, não precisa.
5. **Limites testados:** quando a história tem limite (30 min, 2h, 08:00 e último horário que cabe, combo no fim do expediente, hoje + 13, 2 por telefone somando barbearias, 1 min antes de concluir, slot em andamento (10:29:59 / 10:30:00), grade e meia-noite do bloqueio, formatos de telefone, % de 0 a 100, meio centavo, virada do mês em SP), os dois lados do limite estão testados, não só o caminho feliz.
6. **Papel testado no servidor:** toda rota nova da Casa entra na varredura de papel (CT-00-24) e na de multi-tenant (CT-00-28).
7. **Sem relógio de verdade:** nenhum teste depende da hora em que roda. Teste que falha em certos horários é bug do teste.
8. **Estável:** testes de concorrência repetem várias vezes por execução e passam 3 vezes seguidas na CI.
9. **Nada de dado sensível:** sem token, senha ou dado real de cliente no código, nos testes ou nos logs da CI.
10. **Plano atualizado:** se o PR muda uma regra ou responde uma pergunta em aberto, este arquivo é atualizado no mesmo PR ou num PR ligado.

## Observações

Riscos conhecidos que a regra aprovada deixa de propósito. Não são perguntas; ficam aqui para ninguém estranhar no teste.

- **Troca de celular com 2 horários:** um cliente com 2 horários futuros pelo app que troca de celular não consegue prender o aparelho novo, porque o 1º agendamento é recusado pelo limite de 2 e só agendamento aceito prende o aparelho. Até a barbearia cancelar um desses horários ou ele usar um, ele não vê nem cancela esses horários pelo app. (CT-17-25)

## Perguntas em aberto

Já respondidas e viradas regra (seção 2): turnos, grade de 30 min, duração dos serviços, janela de 14 dias, % por profissional e padrão 60/40, matriz de papéis, falta e balcão no caixa, visual (1ª rodada); cancelamento pela Casa, concluir e falta antes da hora, regras da marcação pela Casa e do balcão, profissional desativado, % inteira e arredondamento, data do caixa e o modelo de cliente e papel por barbearia (2ª rodada); arredondamento por agendamento, bloqueio, falta que libera o horário, slot em andamento e telefone normalizado (3ª rodada); caixa por papel (regra de 07/10); meia-noite do bloqueio, celular sem o 9, 55 com e sem `+`, telefone em outro aparelho e `shopCents` do profissional (decisões de 07/10); um telefone por aparelho e troca de celular com "Liberar aparelho" (decisões de 07/10); liberar em uma barbearia libera em todas, e o aparelho só fica preso quando o agendamento entra (decisões de 07/10).

Estas continuam vagas demais para virar um teste com resultado esperado claro. Os casos que dependem delas estão marcados acima.

**Agenda**
1. **Horário fora dos turnos:** se o expediente começa antes das 08:00 ou vai depois das 21:00, esses horários aparecem (em qual filtro)? Um Combo que começa 11:30 e termina 12:30 fica em manhã, pelo início? (CT-01-17)
2. **Grade x expediente:** se o expediente começa 08:15, os horários seguem o relógio (08:30, 09:00...) ou o início do expediente (08:15, 08:45...)? (CT-01-05, CT-01-06)
3. **Duração que não é múltiplo de 30** (ex.: 45 min): o gerente pode salvar? Se pode, quantos horários ela ocupa? (CT-10-07)

**Cliente e aparelho**

4. **Intro:** aparece só na primeira abertura ou sempre? (CT-14-04)

**Casa**

5. **Profissional em Clientes (17):** o profissional que não é gerente pode buscar e cadastrar clientes? (CT-17-07)
6. **Profissional desativado:** ele ainda entra no app Casa e vê o próprio histórico e ganho, ou perde o acesso? Dá para reativar? (CT-10-04)
7. **Mesmo identificador de pedido com dados diferentes:** devolve o primeiro resultado ou dá erro? (CT-00-08)
8. **Trava da liberação (proposta do Back-end e do tech lead):** o gerente só libera um telefone que tenha pelo menos um agendamento feito pelo app na barbearia dele; senão, 409 `DEVICE_RELEASE_NOT_ALLOWED`. O PO confirma? Se sim, conta agendamento pelo app em qualquer status (inclusive cancelado e já passado), ou só os ativos? (CT-17-24, CT-17-26 a CT-17-28)

## 11. Resumo dos casos

| Grupo | História | Casos |
|---|---|---|
| CT-01 | (1) Agendar | 29 |
| CT-03 | (3) Sem encaixe duplo | 11 |
| CT-04 | (4) Meus horários | 23 |
| CT-14 | (14) Introdução | 4 |
| CT-15 | (15) Início | 4 |
| CT-16 | (16) Página da barbearia | 5 |
| CT-02 | (2) Agenda por profissional | 23 |
| CT-06 | (6) Balcão e marcação pela Casa | 16 |
| CT-07 | (7) Expediente e folgas | 7 |
| CT-17 | (17) Clientes | 28 |
| CT-10 | (10) Preços, serviços e profissionais | 9 |
| CT-08 | (8) Caixa do mês | 15 |
| CT-20 | (20) Gerência | 10 |
| CT-09 | (9) Visual | 11 |
| CT-13 | (13) Nome CortaAqui | 3 |
| CT-00 | Transversal (status, pedido repetido, login, papéis, multi-tenant, fuso, mock, papel por barbearia) | 45 |
| **Total** | | **243** |
