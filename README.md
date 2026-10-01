# 🦖 Dino

Um dinossaurinho de pixel art que mora no cantinho do seu Mac. Ele pisca,
respira, faz companhia e conversa com você em balõezinhos fofos. 🦕💚

[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/vittau)

![O Dino conversando](docs/print.png)

## Como instalar

1. Vá em **[Releases](https://github.com/vittau/dino/releases)** e baixe o
   `Dino-….dmg` mais recente.
2. Abra o arquivo e arraste o **Dino** para a pasta **Aplicativos**.
3. Abra o Dino. Prontinho, ele já mora aí. 🥚

Precisa de um Mac com **macOS 15 (Sequoia)** ou mais novo.

> ### "O Item Dino Não Foi Aberto" — calma, o Dino não é vírus 🦖
>
> É o Gatekeeper resmungando porque o Dino não tem assinatura paga da Apple
> (projeto de estimação, não multinacional). E não, ele **não apaga o app
> sozinho**: o botão "Mover para o Lixo" é só o padrão preguiçoso do macOS —
> clica em **OK** e o Dino continua bonitinho nos Aplicativos. 🙂
>
> Pra abrir, uma vez só:
>
> **Ajustes do Sistema → Privacidade e Segurança** → rola até aparecer
> "O Dino foi bloqueado…" → **Abrir Mesmo Assim**. Pronto, nunca mais enche o
> saco. 🎉
>
> Time terminal: `xattr -dr com.apple.quarantine "/Applications/Dino.app"`
> resolve na hora.

## Como usar

- Escreva no campinho de baixo e aperte Enter pra conversar. 💬
- Arraste pela faixa do título pra mover e use a alça do canto pra
  redimensionar.
- Quer ele sempre por cima? Clique na tachinha 📌.
- Pra começar uma conversa nova, clique na setinha circular 🔄.

Na primeira vez o Dino pede a sua **chave do OpenRouter** pra poder pensar.
Cola lá, ele guarda com carinho e nunca mais esquece. 🔑
Você pode criar a chave em [openrouter.ai/settings/keys](https://openrouter.ai/settings/keys).
O modelo inicial é `openrouter/free`; outros modelos podem ter custo no OpenRouter.

### Hora, localização e clima

Ao responder, o Dino recebe a data e hora do Mac com o fuso horário, uma
localização aproximada e o clima atual com previsão para hoje e os próximos
dois dias. Na primeira conversa, o macOS pede permissão para localizar o Mac.
Se você negar ou o Mac não conseguir obter a localização, o Dino usa a
estimativa por IP do [ipwho.is](https://ipwhois.io/documentation). Essa estimativa
pode apontar para outra cidade quando você usa VPN, iCloud Private Relay ou
certas redes. Se ambas as consultas falharem, o Dino informa que os dados
estão indisponíveis.

Os dados de clima são fornecidos pela [Open-Meteo](https://open-meteo.com/)
(dados licenciados sob [CC BY 4.0](https://open-meteo.com/en/terms)). As consultas
usam HTTPS, dispensam chave própria e são guardadas temporariamente para evitar
requisições a cada mensagem. O acesso gratuito da Open-Meteo é para uso não
comercial, limitado a 10 mil chamadas por dia e sem garantia de disponibilidade;
o ipwho.is permite 1 mil chamadas diárias por IP na modalidade gratuita.

## Deu ruim?

Abra uma [issue](https://github.com/vittau/dino/issues) que a gente resolve. 🦖

## Apoie o Dino 🥬

O Dino adora folhinhas — é o que mantém o meteoro longe. Se ele faz companhia
pro seu Mac, dá pra deixar uma pra ele aqui:

[![Sponsor](https://img.shields.io/badge/Sponsor-%E2%9D%A4-ea4aaa?logo=githubsponsors&logoColor=white)](https://github.com/sponsors/vittau)

---

Feito com carinho — e a uma boa distância do meteoro. ☄️
