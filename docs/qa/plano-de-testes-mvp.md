# Plano de testes do MVP do CortaAqui

Autora: QA Dev (Mesa Dev). Base: as histórias do MVP aprovadas pelo mouretz em 07/10/2026.

Este plano diz **o que** testar em cada história e **em que nível**. Ele não escolhe a implementação.
Onde a regra ainda é vaga demais para virar um teste, o caso aponta para as [Perguntas em aberto](#perguntas-em-aberto).
Quando uma pergunta for respondida, o caso correspondente é ajustado neste arquivo.

## Sumário

1. [Escopo](#1-escopo)
2. [Ambientes](#2-ambientes)
3. [Níveis de teste](#3-níveis-de-teste)
4. [Dados de teste](#4-dados-de-teste)
5. [O que o código precisa ter para ser testável](#5-o-que-o-código-precisa-ter-para-ser-testável)
6. [Casos de teste](#6-casos-de-teste)
7. [Checklist do teste manual do APK mock](#7-checklist-do-teste-manual-do-apk-mock)
8. [Critérios para a QA dar OK num PR](#8-critérios-para-a-qa-dar-ok-num-pr)
9. [Perguntas em aberto](#perguntas-em-aberto)
10. [Resumo dos casos](#10-resumo-dos-casos)

---

## 1. Escopo

**Entra no MVP (e neste plano):**

| App | Histórias |
|---|---|
| Cliente | (14) Introdução, (15) Início, (16) Página da barbearia, (1) Agendar, (4) Meus horários |
| Casa | (2) Agenda por profissional, (6) Balcão, (7) Expediente e folgas, (17) Clientes, (10) Preços e profissionais, (8) Caixa do mês, (20) Gerência |
| Regras gerais | (3) Sem encaixe duplo, status só anda pra frente, pedido repetido ignorado, preço gravado, horários livres só no servidor |
| Transversal | Login (gerente e profissional com e-mail e senha; cliente com código), papéis, multi-tenant (`barbershop_id`), fuso America/Sao_Paulo, modo mock |
| Visual e nome | (9) Visual, (13) Nome CortaAqui |

**Fica fora (não testar, só conferir que não aparece):** nota, pontos de fidelidade, pagamento no app, relatório, avaliações e favoritar.
Também fica fora: confirmação de telefone por SMS, hospedagem do servidor e publicação na Play Store.

**Estrutura atual do repo (main em 07/10/2026):** o Spring Boot antigo em `src/` (Boot 3.4.2, Java 21, Flyway, 2 migrations, sem testes)
e o app WebView em `navalha-android/`. A tabela `SCHEDULES` de hoje só tem `UNIQUE (start_at, end_at)`, que **não** barra sobreposição parcial.
Por isso o CT-03-01 tem que falhar contra o schema antigo.

## 2. Ambientes

| Ambiente | Para quê | Como |
|---|---|---|
| **Mock no APK** | Primeira entrega pro mouretz. Os 2 apps (Cliente e Casa) rodando sem servidor. | Flavor `mock` (ou flag de build) com repositório em memória e o seed da Barbearia Navalha. Testado em celular Android real, em modo avião. |
| **Servidor com Postgres real** | Regras de negócio, constraint do banco, concorrência, multi-tenant e fuso. | Testcontainers com a mesma versão de Postgres de produção (17). Nada de H2: a constraint de não sobreposição e o lock só existem no Postgres. JVM com `-Duser.timezone=UTC`. |
| **CI (GitHub Actions)** | Rodar tudo em cada PR. | Job Java: `./gradlew test` (unitário + integração com Testcontainers, Docker já existe no runner `ubuntu-latest`). Job Flutter: `flutter analyze` + `flutter test` (widget e golden). Job de APK: gera os 2 APKs mock com o nome CortaAqui. Variável `TZ=UTC` no runner. |

## 3. Níveis de teste

| Sigla | Nível | Onde roda |
|---|---|---|
| **UNI** | Unitário Java | JUnit 5, sem banco, com `Clock` fixo |
| **INT** | Integração com Postgres real | Testcontainers + repositórios/serviços reais |
| **API** | API | Chamada HTTP (MockMvc ou RestAssured) no app Spring inteiro, com Postgres real por trás |
| **FLU** | Widget/integração Flutter | `flutter test` com repositório fake e relógio fixo; golden tests para visual |
| **MAN** | Manual no APK | Celular Android real, roteiro da seção 7 |

## 4. Dados de teste

O seed oficial (servidor e mock) tem a **Barbearia Navalha**, 2 profissionais e pelo menos 1 cliente.
Os testes automáticos usam, além disso, dados próprios para não depender de detalhes do seed:

| Nome no plano | O que é |
|---|---|
| **Barbearia A** | Barbearia Navalha (seed) |
| **Barbearia B** | Segunda barbearia criada só nos testes, para isolamento multi-tenant |
| **P1, P2** | Profissionais da A. **PB1** é profissional da B |
| **G-A** | Gerente da A que não é barbeiro. **G-P2** é o P2 com papel de gerente também. **G-B** é gerente da B |
| **S30, S60** | Serviços de teste de 30 e 60 minutos, com preço R$ 40,00 e R$ 70,00 |
| **Expediente de teste** | 09:00 às 19:00 (hora de Brasília), todos os dias, salvo quando o caso diz outra coisa |
| **Telefones** | T1 e T2, de clientes diferentes |
| **Relógio** | Sempre fixo. Datas do plano em hora de Brasília (BRT, UTC-3, sem horário de verão desde 2019) |

Duração, preço e expediente acima são **fixtures de teste**, não regra de produto.

## 5. O que o código precisa ter para ser testável

Sem isto, vários casos abaixo não têm como ser automatizados. Peço que entre no primeiro PR de cada camada.

1. **Relógio injetável:** o servidor usa um `java.time.Clock` injetado (zona `America/Sao_Paulo`), nunca `LocalDateTime.now()` solto. O app Flutter recebe um relógio fake nos testes.
2. **Datas no banco com fuso:** colunas `timestamptz` e conversão para America/Sao_Paulo só na regra de "dia" e "mês".
3. **Identificador do pedido:** um header (ex.: `Idempotency-Key`) definido no contrato OpenAPI, para criar, cancelar e mudar status.
4. **Erros com código estável:** conflito, "status mudou", fora do prazo, limite por telefone e antecedência devolvem um código de erro próprio no corpo (além do HTTP), para o app e os testes não dependerem do texto.
5. **`barbershop_id` vem do token**, nunca de parâmetro da requisição.
6. **Repositório do app atrás de interface:** a mesma tela roda com o repositório mock e com o de API.

---

## 6. Casos de teste

Formato do ID: `CT-<história>-<nº>`. O grupo `CT-00` reúne as regras transversais (status, pedido repetido, login, papéis, multi-tenant, fuso e mock), que não pertencem a uma história só.

### CT-01 · (1) Agendar

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-01-01 | Agora = 07/10 09:00. P1 livre às 10:00. Aparelho sem código. | Cliente agenda S30 com P1 às 10:00, com telefone T1. | 201. Agendamento `agendado`, 10:00–10:30, com `barbershop_id` da A, `professional_id` P1, preço R$ 40,00 gravado. A resposta traz o código do cliente. | API |
| CT-01-02 | Agora = 09:30:00. P1 livre às 10:00. | Agendar 10:00. | Aceito (exatamente 30 min = "no mínimo 30 min"). | UNI + API |
| CT-01-03 | Agora = 09:31:00. | Agendar 10:00 (29 min). | Recusado com erro de antecedência. Nada gravado. | UNI + API |
| CT-01-04 | Agora = 09:30:01. | Agendar 10:00 (29 min e 59 s). | Recusado. O limite conta segundos, não arredonda para o minuto. | UNI |
| CT-01-05 | Agora = 09:30. | Pedir os horários livres de hoje. | 10:00 aparece e 09:45 (se existir na grade) não aparece. A lista bate com CT-01-02 e CT-01-03. | API |
| CT-01-06 | Expediente até 19:00. | Pedir livres de S60 e tentar agendar S60 às 18:30. | 18:30 não aparece nos livres. O POST é recusado (terminaria 19:30, depois do fim do expediente). | UNI + API |
| CT-01-07 | Expediente até 19:00. | Agendar S60 às 18:00. | Aceito: termina exatamente às 19:00. | UNI + API |
| CT-01-08 | Expediente a partir de 09:00. | Agendar S30 às 08:30 e S60 às 08:45 (se a grade permitir). | Recusados: começam antes do expediente. | UNI + API |
| CT-01-09 | Agora = 11:00. | Agendar hoje às 10:00. | Recusado (horário que já passou). | UNI + API |
| CT-01-10 | — | Agendar num horário fora da grade de horários (ex.: 10:07). | Recusado. Depende da [pergunta do slot](#perguntas-em-aberto). | API |
| CT-01-11 | — | Agendar além do último dia em que a agenda abre. | Recusado. Depende da [pergunta de dias à frente](#perguntas-em-aberto). | UNI + API |
| CT-01-12 | T1 já tem 2 horários futuros `agendado`. | Agendar o 3º com T1. | Recusado com erro de limite por telefone. | API |
| CT-01-13 | T1 tem 2 futuros. Cliente cancela 1. | Agendar de novo com T1. | Aceito: cancelado não conta no limite. | API |
| CT-01-14 | T1 tem 1 futuro e 3 no passado (concluído, falta, cancelado). | Agendar mais 1 com T1. | Aceito: passado e status final não contam. | API |
| CT-01-15 | T1 tem 1 futuro. | Dois pedidos de agendamento de T1 ao mesmo tempo (horários diferentes, livres), em conexões separadas. | No máximo 1 aceito. Nunca 3 futuros para T1. Repetir 20 vezes. | INT |
| CT-01-16 | — | Agendar com profissional ou serviço da Barbearia B dentro da A. | Recusado (404 ou 422). Nada gravado. | API |
| CT-01-17 | — | Na tela Agendar: escolher serviço, profissional, dia e turno, e confirmar. | O botão Confirmar só habilita com tudo escolhido. Ao confirmar, mostra sucesso e o horário aparece em Meus horários. | FLU |
| CT-01-18 | Repositório fake devolve uma lista fixa de livres. | Abrir a tela Agendar. | A tela mostra exatamente a lista do servidor, sem filtrar nem calcular nada no app (horários livres só no servidor). | FLU |
| CT-01-19 | O servidor responde conflito no POST. | Confirmar um horário que alguém pegou antes. | O app mostra "esse horário acabou de ser ocupado", recarrega os livres e não deixa o horário velho selecionado. | FLU |

### CT-03 · (3) Sem encaixe duplo por profissional

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-03-01 | P1 tem 10:00–10:30 ativo. | Inserir 10:15–10:45 para P1 **direto no banco** (sem passar pelo serviço). | O Postgres recusa com violação de constraint. **Tem que falhar contra o schema antigo** (`UNIQUE (start_at, end_at)` não pega sobreposição parcial). | INT |
| CT-03-02 | P1 tem 10:00–10:30. | Pela API, agendar 10:15–10:45 para P1. | 409 com código de conflito, mensagem amigável, nunca 500. | API |
| CT-03-03 | P1 tem 10:00–11:00. | Agendar 10:15–10:45 (contido) e 09:30–11:30 (contém). | Os dois recusados. | INT + API |
| CT-03-04 | P1 tem 10:00–10:30. | Agendar 10:30–11:00 e 09:30–10:00 (encostados). | Os dois aceitos. Intervalo é `[início, fim)`. | INT + API |
| CT-03-05 | P1 tem 10:00–10:30. | Agendar P2 10:00–10:30. | Aceito: a regra é por profissional. | INT |
| CT-03-06 | P1 tem 10:00–10:30 `cancelado`. | Agendar 10:00–10:30 para P1. | Aceito: cancelado não ocupa (a constraint só vale para ativos). | INT + API |
| CT-03-07 | P1 livre às 10:00. | **Concorrência real:** 2 conexões separadas tentam gravar 10:00–10:30 para P1 ao mesmo tempo (threads soltas juntas por um `CountDownLatch`), clientes diferentes. Repetir 50 vezes. | Em todas as rodadas: exatamente 1 sucesso e 1 conflito. No banco, 1 agendamento ativo. **Tem que falhar sem a constraint** (o "confere e depois grava" deixa os 2 passarem). | INT |
| CT-03-08 | P1 livre. | Concorrência com intervalos que se sobrepõem parcialmente: 10:00–11:00 (S60) e 10:30–11:00 (S30), ao mesmo tempo. | Só 1 vale. | INT |
| CT-03-09 | P1 livre às 10:00. | Ao mesmo tempo: app do cliente agenda 10:00, Casa lança balcão 10:00 e Casa bloqueia 10:00. | Só 1 dos 3 vale. Balcão, app e bloqueio passam pela mesma checagem. | INT |
| CT-03-10 | P1 tem 10:00–10:30 com status `falta` ou `concluido`. | Agendar 10:00–10:30 para P1. | Concluído ocupa. Falta: depende da [pergunta sobre falta](#perguntas-em-aberto). | INT |

### CT-04 · (4) Meus horários

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-04-01 | Cliente C1 (código K1) tem 2 futuros e 2 passados. | Listar Meus horários com K1. | Vê os 4, com status. Futuros e histórico separados. | API + FLU |
| CT-04-02 | Agora = 08:00. Horário de C1 às 10:00. | Cancelar com K1. | Aceito: exatamente 2h antes ainda pode ("até 2h antes"). | UNI + API |
| CT-04-03 | Agora = 08:00:01. Horário às 10:00. | Cancelar com K1. | Recusado pelo servidor com erro de prazo. Status continua `agendado`. | UNI + API |
| CT-04-04 | Relógio fake: 2h01 antes e depois 1h59 antes. | Abrir Meus horários nos dois momentos. | Com 2h01 o botão Cancelar aparece. Com 1h59 ele some e aparece "cancelamento só com a barbearia". | FLU |
| CT-04-05 | C1 cancela o horário de 10:00 com P1. | Pedir livres de P1. Outro cliente agenda 10:00. | 10:00 volta para os livres e o novo agendamento é aceito. | API |
| CT-04-06 | — | Listar e cancelar com código inexistente ou alterado. | 401/403. Nenhum dado volta. A mensagem não diz se o telefone existe. | API |
| CT-04-07 | C2 tem código K2 válido. | Com K2, listar e cancelar um horário de C1 (pelo id). | Recusado (403/404). O horário de C1 não muda. | API |
| CT-04-08 | Telefone T1 de C1 conhecido. Sem código. | Tentar listar ou cancelar só com o telefone. | Recusado. Saber o telefone não basta. | API |
| CT-04-09 | App com código salvo. | Fechar o app à força e abrir de novo. Reiniciar o celular. | O código continua lá e Meus horários carrega. | FLU + MAN |
| CT-04-10 | Horário de C1 já `cancelado` (pela Casa). | C1 tenta cancelar. | Recusado com "status mudou". A tela atualiza para o status novo. | API + FLU |
| CT-04-11 | Casa conclui ou cancela um horário de C1. | C1 abre Meus horários. | Vê o status novo. Não vê dados de outros clientes nem notas internas. | API |

### CT-14 · (14) Introdução

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-14-01 | Primeira abertura. | Tocar Próximo duas vezes. | Passa pelas 3 telas. O indicador mostra 3 pontos e marca a tela atual. | FLU |
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
| CT-16-01 | Seed. | Abrir a Barbearia Navalha. | Mostra os serviços com preço e duração e os 2 profissionais. | API + FLU |
| CT-16-02 | G-A (gerente que não é barbeiro) existe. | Abrir a página. | G-A não aparece como profissional. | API |
| CT-16-03 | Um profissional desativado (CT-10-04). | Abrir a página. | Ele não aparece. | API |
| CT-16-04 | — | Tocar em Agendar a partir de um serviço ou profissional. | Abre o Agendar com a barbearia (e o item tocado) já escolhidos. | FLU |
| CT-16-05 | — | Procurar nota, avaliações, favoritar, pontos e pagamento. | Nada disso aparece (fora do MVP). | FLU + MAN |

### CT-02 · (2) Agenda por profissional (Casa)

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-02-01 | P1 e P2 com horários no mesmo dia. | Na agenda, escolher P1, depois P2. | Cada visão mostra só os horários daquele profissional. | API + FLU |
| CT-02-02 | Expediente de P1 09:00–19:00. | Abrir a agenda de P1. | Antes de 09:00 e depois de 19:00 aparece em cinza e não abre ações. | FLU |
| CT-02-03 | — | Pela API, marcar para P1 às 08:00. | Recusado: fora do expediente vale no servidor, não só na cor. | API |
| CT-02-04 | Horário livre. | Tocar nele. | Aparecem as opções Marcar e Bloquear. | FLU |
| CT-02-05 | Horário marcado. | Tocar nele. | Aparecem Concluir, Marcar falta e Cancelar. Nada disso aparece num horário cancelado, concluído ou com falta. | FLU |
| CT-02-06 | Horário livre de P1 às 14:00. | Bloquear. | Fica ocupado na agenda. Some dos livres do cliente. Tentar agendar 14:00 pelo app dá conflito. | API |
| CT-02-07 | P1 tem 14:00 agendado. | Tentar bloquear 14:00. | Recusado com conflito (mesma checagem). | API |
| CT-02-08 | Horário `agendado`. | Concluir. | Status `concluido`. Preço e % gravados (CT-20-03). Entra no caixa (CT-08). | API |
| CT-02-09 | Horário `agendado`. | Marcar falta. | Status `falta`. Final. | API |
| CT-02-10 | Horário `agendado` daqui a 1h. | A Casa cancela. | Depende da [pergunta de quem cancela](#perguntas-em-aberto). | API |
| CT-02-11 | Horário às 15:00, agora 10:00. | Concluir ou marcar falta antes da hora. | Depende da [pergunta de concluir antes](#perguntas-em-aberto). | UNI |
| CT-02-12 | Servidor real. | Cliente agenda pelo app. Casa abre a agenda. | O horário aparece na agenda da Casa com o nome do cliente. | MAN (com servidor) |

### CT-06 · (6) Horário de balcão

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-06-01 | P1 livre às 11:00. | Lançar balcão S30 11:00 só com nome, sem telefone. | Aceito. Telefone vazio. Preço gravado. | API |
| CT-06-02 | — | Lançar balcão com telefone. | Aceito. O telefone fica no agendamento. | API |
| CT-06-03 | P1 tem 11:00–11:30. | Lançar balcão 11:15–11:45. | Recusado com conflito (sobreposição parcial). | API |
| CT-06-04 | — | Lançar balcão que passa do fim do expediente. | Recusado. | API |
| CT-06-05 | T1 já tem 2 futuros. | Lançar balcão com T1. | Depende da [pergunta do balcão](#perguntas-em-aberto). | API |
| CT-06-06 | Agora 10:50. | Lançar balcão às 11:00 (10 min). | Depende da [pergunta do balcão](#perguntas-em-aberto). | API |
| CT-06-07 | — | Abrir o formulário de balcão no app Casa. | Telefone é opcional. Salvar sem telefone funciona. | FLU |

### CT-07 · (7) Expediente e folgas

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-07-01 | — | Gerente define P1 de terça 10:00–18:00. | Os livres de terça de P1 começam às 10:00 e o último termina às 18:00. | API |
| CT-07-02 | — | Gerente marca folga de P1 na sexta. | Sexta não tem livres de P1. P2 continua com livres. | API |
| CT-07-03 | P1 tem sexta 15:00 `agendado`. | Marcar folga de P1 na sexta. | O agendamento **continua valendo** (não é apagado nem cancelado). Aparece destacado na agenda da Casa. O cliente ainda vê o horário. | API + FLU |
| CT-07-04 | P1 tem 18:00 agendado. | Reduzir o expediente de P1 para terminar 17:00. | O agendamento das 18:00 continua valendo e aparece destacado. Não abre livres novos depois das 17:00. | API |
| CT-07-05 | — | Salvar expediente com fim antes do início, ou com hora inválida. | Recusado (422). O expediente antigo fica. | UNI + API |
| CT-07-06 | — | Mudar o expediente de P1 depois que os livres de amanhã foram calculados. | O próximo pedido de livres já reflete a mudança (sem cache velho). | API |

### CT-17 · (17) Clientes

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-17-01 | — | Cadastrar cliente com nome, telefone e e-mail. | Aceito, ligado à Barbearia A. | API |
| CT-17-02 | — | Cadastrar sem nome, com telefone inválido ou e-mail inválido. | Recusado (422) com o campo que falhou. | API |
| CT-17-03 | T1 já cadastrado na A. | Cadastrar outro cliente com T1 na A. | Recusado (telefone repetido na mesma barbearia). | INT + API |
| CT-17-04 | Clientes "João Almeida" e "Ana". | Buscar "joão", "JOAO", "alm" e parte do telefone. | Acha o João nos 4 casos. Depende do formato do telefone ([pergunta](#perguntas-em-aberto)). | API |
| CT-17-05 | A Barbearia B tem cliente "João B". | G-A busca "joão". | "João B" não aparece. | API |
| CT-17-06 | — | Cadastrar e buscar pelo app Casa. | O cliente novo aparece na busca sem precisar reabrir a tela. | FLU |

### CT-10 · (10) Preços e profissionais

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-10-01 | S30 custa R$ 40,00. Existe agendamento futuro com S30. | Gerente muda S30 para R$ 45,00. | Agendamentos novos gravam R$ 45,00. O antigo continua com R$ 40,00 (preço gravado). | API |
| CT-10-02 | — | Salvar preço zero, negativo, com 3 casas decimais ou texto. | Recusado (422). | UNI + API |
| CT-10-03 | — | Gerente inclui o profissional P3. | P3 aparece na agenda da Casa e na página da barbearia, e ganha livres quando tiver expediente. | API |
| CT-10-04 | P3 sem horários futuros. | Gerente desativa P3. | P3 some da página do cliente e não recebe agendamento novo. O histórico dele continua no caixa. | API |
| CT-10-05 | P1 tem horários futuros. | Gerente tenta remover ou desativar P1. | Depende da [pergunta do profissional removido](#perguntas-em-aberto). | API |

### CT-08 · (8) Caixa do mês

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-08-01 | Outubro: 3 concluídos de P1 (R$ 40, 40, 70) e 1 de P2 (R$ 70). | Abrir o caixa de outubro. | Bruto R$ 220,00. Por profissional: P1 R$ 150,00, P2 R$ 70,00. Divisão casa/profissional pela % gravada em cada um. | INT + API |
| CT-08-02 | Mais 1 `cancelado` e 1 `falta` em outubro. | Abrir o caixa. | Depende da [pergunta falta/cancelado no caixa](#perguntas-em-aberto). Proposta: não entram. | API |
| CT-08-03 | 1 concluído de balcão em outubro. | Abrir o caixa. | Depende da [pergunta balcão no caixa](#perguntas-em-aberto). | API |
| CT-08-04 | Concluído em setembro. | Abrir outubro. | Não entra. Setembro continua igual. | API |
| CT-08-05 | Em qualquer mês, com valores que geram fração de centavo. | Somar parte da casa + parte dos profissionais. | A soma bate com o bruto, centavo por centavo. Sem `double`: dinheiro em `BigDecimal`/centavos inteiros. | UNI |
| CT-08-06 | Barbearia B tem concluídos em outubro. | G-A abre o caixa. | Só valores da A. | API |
| CT-08-07 | Concluído em 31/10 às 21:30 (BRT) = 01/11 00:30 UTC. Servidor em UTC. | Abrir outubro e novembro. | Entra em **outubro**, não em novembro. Depende também da [pergunta de qual data conta](#perguntas-em-aberto). | INT |
| CT-08-08 | Horário de 31/10 às 18:00, concluído só em 01/11 às 09:00. | Abrir outubro e novembro. | Depende da [pergunta de qual data conta](#perguntas-em-aberto). | INT |

### CT-20 · (20) Gerência (%)

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-20-01 | Barbearia nova. | Ler a % padrão. | 60/40. Qual lado é 60 depende da [pergunta do 60/40](#perguntas-em-aberto). | API |
| CT-20-02 | — | Gerente salva 70/30, 100/0 e 0/100. Depois tenta 70/40, 50/49, -10/110 e 60,5/39,5. | Os 3 primeiros aceitos (somam 100). Os outros recusados (422). Decimais dependem da [pergunta de arredondamento](#perguntas-em-aberto). | UNI + API |
| CT-20-03 | % = 60/40. Horário `agendado`. | Concluir. | O agendamento grava a % no momento da conclusão (casa e profissional), além do preço. | INT |
| CT-20-04 | Horário concluído em outubro com 60/40. | Gerente muda para 50/50. Abrir o caixa de outubro de novo. | O caixa de outubro **não muda**. | INT + API |
| CT-20-05 | Horário marcado quando a % era 60/40. | Gerente muda para 50/50. Depois concluir. | Grava 50/50 (vale a % do momento da conclusão). | INT |
| CT-20-06 | Duas % diferentes por profissional (se for por profissional). | Concluir 1 horário de P1 e 1 de P2. | Cada um grava a sua. Depende da [pergunta de % global ou por profissional](#perguntas-em-aberto). | INT |
| CT-20-07 | — | Profissional P1 (sem papel de gerente) tenta mudar a %. | 403. Nada muda. | API |

### CT-09 · (9) Visual

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-09-01 | Pacote de tema. | Ler as cores do tema. | Fundo `#000000`, cards `#1C1C1E`/`#2C2C2E`, texto `#FFFFFF`, secundário `#8E8E93` e o amarelo definido pelo Front-end. Nenhuma cor solta fora do tema nas telas. | FLU |
| CT-09-02 | Tema. | Teste que calcula o contraste de cada par texto/fundo usado. | Todo texto ≥ 4,5:1 (AA). **Atenção:** `#8E8E93` sobre `#2C2C2E` dá **4,27:1** e reprova para texto normal. Sobre `#1C1C1E` dá 5,22:1 e sobre `#000000`, 6,44:1. | FLU (unitário Dart) |
| CT-09-03 | — | Golden test das telas principais (Intro, Início, Barbearia, Agendar, Meus horários, Agenda, Caixa, Clientes, Menu). | Bate com a imagem aprovada. Mudança visual exige atualizar o golden no mesmo PR. | FLU |
| CT-09-04 | — | Conferir onde o amarelo aparece. | Só na aba ativa, no profissional escolhido e no botão principal. Ver a [pergunta do visual](#perguntas-em-aberto). | FLU + MAN |
| CT-09-05 | Celular em modo avião. | Abrir os títulos. | Inter peso 800 aparece mesmo sem internet (fonte empacotada no app, não baixada). | MAN |
| CT-09-06 | — | Comparar com o protótipo em `/workspace/cortaaqui-grok/`. | Mesmo layout, menu de linha fina, mesma hierarquia de texto. | MAN |
| CT-09-07 | Fonte do Android em tamanho máximo. Celular pequeno (360 dp). | Navegar pelas telas. | Nenhum texto cortado nem botão escondido. | MAN |

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
| CT-00-02 | Horário `cancelado`. | Pela API: concluir, marcar falta e "reabrir". | Recusado com "status mudou". O banco não muda. | API |
| CT-00-03 | Horário `agendado`. | **Concorrência real:** cliente cancela e Casa conclui ao mesmo tempo, em conexões separadas. Repetir 50 vezes. | Sempre só 1 vale. O outro recebe "status mudou". O status final é o do vencedor e o caixa bate com ele. | INT |

**Pedido repetido (mesmo identificador)**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-04 | — | Mandar o mesmo POST de agendamento 2 vezes com o mesmo identificador. | 1 agendamento só. A 2ª resposta devolve o mesmo agendamento (mesmo id), sem erro de conflito. Conta 1 no limite do telefone. | API |
| CT-00-05 | — | Mesmo identificador, 2 pedidos **ao mesmo tempo**. | 1 agendamento só. | INT |
| CT-00-06 | — | Mesmo cancelamento (mesmo identificador) 2 vezes. | A 2ª é ignorada e devolve o mesmo resultado, não "status mudou". | API |
| CT-00-07 | — | Dois POST com dados iguais e identificadores diferentes. | São 2 pedidos: o 2º leva conflito. | API |
| CT-00-08 | — | Mesmo identificador com dados diferentes. | Depende da [pergunta do identificador](#perguntas-em-aberto). | API |

**Login e papéis**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-09 | G-A cadastrado. | Login com e-mail e senha certos. Depois com senha errada e com e-mail inexistente. | Certo: token. Errados: 401 com a mesma mensagem nos dois casos. | API |
| CT-00-10 | — | Ler a senha gravada no banco. | Hash BCrypt (começa com `$2`), nunca texto puro. Senha não aparece em log nem em resposta. | INT |
| CT-00-11 | — | Chamar rotas da Casa sem token, com token alterado e com o código de cliente. | 401/403 em todas. | API |
| CT-00-12 | P1 logado (não gerente). | Tentar: mudar %, mudar preço, incluir profissional, mudar o expediente de P2. | 403 em tudo. Nada muda. (Matriz de papéis: ver [pergunta](#perguntas-em-aberto).) | API |
| CT-00-13 | G-A logado. | Fazer as mesmas 4 ações. | Todas aceitas. | API |
| CT-00-14 | G-P2 (gerente e profissional). | Abrir a agenda e a Gerência. | Aparece como profissional na agenda e na página do cliente e também acessa a Gerência. | API + FLU |
| CT-00-15 | G-A (só gerente). | Abrir a agenda e a página do cliente. | Não aparece como profissional nem recebe agendamento. | API |

**Isolamento multi-tenant**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-16 | Dados na A e na B. | G-A lê, pelo id, agendamento, cliente, profissional, serviço, expediente, caixa e % da B. | 404 (ou 403) em todos. Nenhum dado da B na resposta. Nunca 200. | API |
| CT-00-17 | — | G-A e P1 tentam alterar, cancelar, concluir ou bloquear recursos da B. | Recusado. No banco, a B fica igual (conferir com SELECT). | API + INT |
| CT-00-18 | — | P1 manda `barbershop_id` da B no corpo ou na query. | O servidor ignora e usa a barbearia do token, ou recusa. Nunca grava na B. | API |
| CT-00-19 | — | Listas da Casa (agenda, clientes, caixa, profissionais) com token da A. | Só itens da A. | API |
| CT-00-20 | OpenAPI do projeto. | **Varredura:** um teste percorre todas as rotas do contrato com token da A e ids da B. | Nenhuma resposta 2xx. Rota nova entra na varredura sozinha. | API |
| CT-00-21 | Banco migrado. | Consultar o schema. | Toda tabela de negócio tem `barbershop_id NOT NULL` com FK. | INT |
| CT-00-22 | — | Cliente C2 tenta ver dados de C1 (ver CT-04-07 e CT-04-08). | Recusado. | API |

**Fuso (America/Sao_Paulo com o servidor em UTC)**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-23 | Servidor e JVM em UTC. Relógio = 07/10 02:30 UTC (= 06/10 23:30 BRT). | Pedir "livres de hoje" e "agenda de hoje". | "Hoje" é **06/10**. Não aparece nada de 07/10 como hoje. | INT + API |
| CT-00-24 | Mesmo relógio. | Agendar 07/10 09:00 (BRT). | Gravado como 07/10 12:00 UTC e devolvido como `2026-10-07T09:00-03:00`. | API |
| CT-00-25 | Relógio = 07/10 01:00 UTC (= 06/10 22:00 BRT). | Casa abre a agenda do dia. | Mostra 06/10. | API |
| CT-00-26 | Celular com fuso de Lisboa. | Abrir Meus horários e a agenda. | Os horários aparecem na hora da barbearia (BRT), iguais aos de um celular em São Paulo. | FLU |
| CT-00-27 | Celular com a hora errada (adiantado 1h). | Tentar agendar com 20 min de antecedência real. | O servidor recusa. A regra usa a hora do servidor, não a do celular. | API |

**Modo mock**

| ID | Pré-condição | Passos | Resultado esperado | Nível |
|---|---|---|---|---|
| CT-00-28 | Build mock. | Rodar os testes de widget com o cliente HTTP trocado por um que falha em qualquer chamada. | Nenhuma chamada de rede. Todas as telas funcionam. | FLU |
| CT-00-29 | APK mock, celular em modo avião desde a instalação. | Seguir o checklist da seção 7. | Tudo funciona, sem tela de erro de rede. | MAN |
| CT-00-30 | — | Comparar o seed do servidor com o do mock. | Mesma Barbearia Navalha, mesmos 2 profissionais, mesmo cliente e mesmos serviços. | FLU + INT |
| CT-00-31 | Mock. | Tentar encaixe duplo, 3º horário do mesmo telefone e cancelamento com menos de 2h no mock. | O mock aplica as mesmas recusas do servidor, para o mouretz não ver um comportamento que depois muda. | FLU |

---

## 7. Checklist do teste manual do APK mock

Rodar antes de mandar o APK pro mouretz. Celular Android real, **modo avião ligado antes de abrir o app pela primeira vez**. Anotar modelo, versão do Android e número do build no PR.

**Instalação**
- [ ] Os 2 APKs instalam juntos, sem um substituir o outro.
- [ ] O nome e o ícone dizem CortaAqui (Cliente e Casa distinguíveis). Nada de "Navalha", exceto a barbearia do seed.

**App Cliente**
- [ ] Intro: 3 telas, Próximo, Pular e o indicador de 3 pontos funcionam.
- [ ] Início: mostra o próximo horário do cliente do seed e a Barbearia Navalha.
- [ ] Página da barbearia: serviços com preço e duração e os 2 profissionais. Sem nota, avaliações, favoritar, pontos ou pagamento.
- [ ] Agendar: escolher serviço, profissional, dia e turno. Horário com menos de 30 min não aparece.
- [ ] Agendar um horário e vê-lo em Meus horários e no card do Início.
- [ ] Tentar o 3º horário futuro com o mesmo telefone: recusa com mensagem clara.
- [ ] Cancelar um horário com mais de 2h: some dos futuros e o horário volta a ficar livre.
- [ ] Horário com menos de 2h: sem botão de cancelar.
- [ ] Fechar à força e abrir: os dados continuam.

**App Casa**
- [ ] Entrar com o usuário do seed (gerente e profissional).
- [ ] Agenda: trocar de profissional. Fora do expediente aparece em cinza.
- [ ] Horário livre: Marcar e Bloquear funcionam. O horário bloqueado não deixa marcar em cima.
- [ ] Horário marcado: Concluir, Marcar falta e Cancelar funcionam. Depois de final, não aparece ação nenhuma.
- [ ] Balcão sem telefone funciona. Balcão em cima de outro horário é recusado.
- [ ] Expediente: fechar um dia que já tem horário. O horário continua lá, destacado.
- [ ] Clientes: buscar e cadastrar.
- [ ] Preços: mudar um preço. O horário já marcado mantém o preço antigo.
- [ ] Caixa do mês: o concluído aparece com a divisão casa/profissional.
- [ ] Gerência: % que não soma 100 é recusada. Mudar a % não altera o caixa já fechado.

**Visual e uso**
- [ ] Fundo preto, cards cinza, Inter 800 nos títulos e menu de linha fina.
- [ ] Amarelo só na aba ativa, no profissional escolhido e no botão principal.
- [ ] Fonte do sistema no máximo: nada cortado.
- [ ] Voltar do Android funciona em todas as telas e não fecha o app sem querer.
- [ ] Girar a tela e trocar de app no meio do Agendar não perde a escolha nem trava.
- [ ] Nenhuma tela de erro de rede em modo avião.

## 8. Critérios para a QA dar OK num PR

A QA só aprova quando **todos** valem:

1. **Testes da história presentes:** cada caso `CT-xx-yy` deste plano que o PR cobre tem um teste automático (no nível pedido) ou, se for `MAN`, o resultado anotado na descrição do PR. O nome ou comentário do teste cita o ID (ex.: `@DisplayName("CT-03-07 ...")`).
2. **Rodando na CI:** os jobs Java e Flutter passam no PR. Teste marcado como `@Disabled`/`skip` sem motivo escrito e sem issue não conta.
3. **Postgres de verdade:** teste de constraint, concorrência, multi-tenant e fuso roda com Testcontainers, nunca com H2 ou mock de repositório.
4. **Falha sem a mudança, quando fizer sentido:** para regra nova ou correção de bug, o autor mostra na descrição do PR que o teste falha sem a mudança (ex.: rodar o CT-03-07 sem a constraint e ver os 2 inserts passarem). Para refatoração e visual, não precisa.
5. **Limites testados:** quando a história tem limite (30 min, 2h, fim do expediente, 2 por telefone, soma 100), os dois lados do limite estão testados, não só o caminho feliz.
6. **Sem relógio de verdade:** nenhum teste depende da hora em que roda. Teste que falha em certos horários é bug do teste.
7. **Estável:** testes de concorrência repetem várias vezes por execução e passam 3 vezes seguidas na CI.
8. **Nada de dado sensível:** sem token, senha ou dado real de cliente no código, nos testes ou nos logs da CI.
9. **Plano atualizado:** se o PR muda uma regra ou responde uma pergunta em aberto, este arquivo é atualizado no mesmo PR ou num PR ligado.

## Perguntas em aberto

Estas regras ainda são vagas demais para virar um teste com resultado esperado claro. Os casos que dependem delas estão marcados acima.

**Agendar e agenda**
1. **Turno:** quais horários são manhã, tarde e noite? Depois de escolher o turno, o cliente escolhe o horário exato ou o sistema escolhe? (CT-01-17)
2. **Grade e duração:** de quanto em quanto tempo os horários começam (15, 30 min?) e qual a duração de cada serviço? Um S60 pode começar em qualquer ponto da grade? (CT-01-10)
3. **Dias à frente:** quantos dias a agenda abre e se conta com hoje ou não (hoje + 13 ou hoje + 14)? (CT-01-11)
4. **Bloquear x folga:** "bloquear" um horário livre ocupa só aquele slot ou um intervalo escolhido? Dá para desbloquear? Folga é o dia inteiro e fica no expediente? (CT-02-06)
5. **Falta libera o horário?** Depois de marcar falta às 10:05 num horário 10:00–10:30, dá para lançar um balcão às 10:10? (CT-03-10)

**Cliente e telefone**

6. **Formato do telefone:** com ou sem +55 e o 9? `(11) 98888-7777` e `11988887777` contam como o mesmo telefone no limite de 2? (CT-01-12, CT-17-04)
7. **Mesmo telefone em outro aparelho, sem o código:** ao agendar, o servidor gera outro código, recusa ou junta com os horários do primeiro? O limite de 2 vale somando os dois? (CT-04-08)
8. **Cliente entre barbearias:** o cadastro do cliente é por barbearia ou global? Cliente cadastrado na A aparece na busca da B? O limite de 2 horários é por telefone no sistema todo ou por barbearia? (CT-17-05)
9. **Intro:** aparece só na primeira abertura ou sempre? (CT-14-04)

**Casa e papéis**

10. **Quem cancela o quê:** a Casa pode cancelar com menos de 2h? Um profissional pode cancelar, concluir ou marcar falta num horário de outro profissional? (CT-02-10)
11. **Concluir ou marcar falta antes da hora** do horário: pode? (CT-02-11)
12. **Matriz de papéis:** o profissional (não gerente) pode editar o próprio expediente e folgas? Vê a agenda dos outros? Cadastra cliente? Vê o caixa (o dele ou o de todos)? (CT-00-12)
13. **Balcão:** o limite de 2 por telefone vale? A antecedência mínima de 30 min vale? (CT-06-05, CT-06-06)
14. **Profissional com horários futuros** que é removido ou desativado: os horários são cancelados, ficam valendo ou a remoção é recusada? (CT-10-05)
15. **Mesmo identificador de pedido com dados diferentes:** devolve o primeiro resultado ou dá erro? (CT-00-08)

**Caixa e %**

16. **Quem fica com 60:** a história diz "% da casa + % do profissional, padrão 60/40". O protótipo diz "60% da equipe e 40% da casa". Qual é o certo? (CT-20-01)
17. **% global ou por profissional?** Uma % para a barbearia toda ou uma para cada profissional? (CT-20-06)
18. **Arredondamento:** a % aceita decimal? Quando a divisão dá fração de centavo (ex.: R$ 33,33 × 60%), o centavo que sobra vai para a casa ou para o profissional? (CT-08-05, CT-20-02)
19. **Falta e cancelado entram no caixa?** (proposta: não) (CT-08-02)
20. **Balcão entra no caixa?** (proposta: sim, quando concluído) (CT-08-03)
21. **Qual data conta no "Caixa do mês":** a do horário do atendimento ou a do momento em que foi concluído? (CT-08-07, CT-08-08)

**Visual**

22. **Prints do protótipo:** em `/workspace/cortaaqui-grok/` só existem 2 prints (a tela de Introdução). As outras telas não têm referência, então "exatamente como o protótipo" só dá para conferir na Intro. Precisamos dos prints das outras telas, ou o golden aprovado pelo mouretz vira a referência. (CT-09-03, CT-09-06)
23. **Amarelo fora dos 3 lugares:** no print da Intro o amarelo também aparece no rótulo acima do título, no link "Próximo" e no ponto ativo do indicador. Vale o print ou a regra "só aba ativa, profissional escolhido e botão principal"? (CT-09-04)
24. **Texto cinza sobre card `#2C2C2E`:** `#8E8E93` dá 4,27:1 e reprova no AA. Ou o texto secundário não vai em cima do `#2C2C2E`, ou o tom de cinza muda. Decisão do Front-end. (CT-09-02)

## 10. Resumo dos casos

| Grupo | História | Casos |
|---|---|---|
| CT-01 | (1) Agendar | 19 |
| CT-03 | (3) Sem encaixe duplo | 10 |
| CT-04 | (4) Meus horários | 11 |
| CT-14 | (14) Introdução | 4 |
| CT-15 | (15) Início | 4 |
| CT-16 | (16) Página da barbearia | 5 |
| CT-02 | (2) Agenda por profissional | 12 |
| CT-06 | (6) Balcão | 7 |
| CT-07 | (7) Expediente e folgas | 6 |
| CT-17 | (17) Clientes | 6 |
| CT-10 | (10) Preços e profissionais | 5 |
| CT-08 | (8) Caixa do mês | 8 |
| CT-20 | (20) Gerência | 7 |
| CT-09 | (9) Visual | 7 |
| CT-13 | (13) Nome CortaAqui | 3 |
| CT-00 | Transversal (status, pedido repetido, login e papéis, multi-tenant, fuso, mock) | 31 |
| **Total** | | **145** |
