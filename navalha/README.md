# Navalha — apps Android de teste

São dois apps:

- **Navalha-cliente.apk** — o cliente escolhe o serviço, o dia e o horário e vê "Meus horários".
- **Navalha-barbeiro.apk** — agenda do dia: marcar como atendido, cancelar e cadastrar horário no balcão.

O código fica em `navalha-android/` e o workflow em `.github/workflows/navalha-apk.yml`.

## Como gerar os APKs

1. No GitHub, abra a aba **Actions** deste repositório.
2. À esquerda, clique em **Navalha APK**.
3. Clique em **Run workflow** e depois no botão verde **Run workflow**.
4. Espere uns 5 minutos até aparecer o ✅ verde.

## Como baixar e instalar no celular

1. Abra **Releases**: https://github.com/Mouretz/app-barber-java/releases
2. Na release mais nova ("Navalha APK N"), toque em `Navalha-cliente.apk` ou `Navalha-barbeiro.apk`.
3. Abra o arquivo baixado. Se o Android pedir, permita "instalar apps desconhecidos" para o navegador.
4. Pronto: aparecem os ícones **Navalha Cliente** e **Navalha Barbeiro**. Dá para instalar os dois juntos.

## Limitações desta versão

- Versão de teste: os dados ficam salvos só no próprio celular, e cada app tem o seu.
  O horário marcado no app do cliente não aparece no app do barbeiro (ainda não tem servidor).
- O APK é de depuração (debug). Serve para instalar e testar, não para publicar na Play Store.
