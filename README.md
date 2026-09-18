# Dino

Um dinossaurinho de pixel art que mora no cantinho da tela do Mac e conversa
com você usando a sua assinatura do **OpenCode Go**. Ele fica numa janelinha de
vidro fosco, sempre por cima se você quiser, com balões de chat curtos em
português.

Não é um *widget* do macOS: é um app AppKit comum (`NSApplication` com política
`.regular`) que abre um `NSPanel` sem moldura. Um widget de verdade seria uma
extensão do WidgetKit (bundle `.appex`, `@main struct X: Widget`, sandbox), o
que não serve para uma janela flutuante que recebe digitação.

Não existe cena SwiftUI nenhuma: o entry point é `@main enum Main` chamando
`NSApplication.run()`, e as telas são vistas SwiftUI hospedadas em `NSView` e
`NSHostingController`. A cena `Settings` foi removida porque abria sozinha no
launch e só podia ser invocada pelo seletor privado `showSettingsWindow:`.

## Rodando

```sh
./build-app.sh              # compila e monta build/Dino.app
./build-app.sh release --run  # compila, monta e abre
```

Na primeira vez o próprio Dino pede a API key. Ele valida a chave contra o
servidor antes de salvar, e grava no mesmo lugar que a janela de Preferências
usa — então dar a chave pelo balão ou pelas Preferências dá no mesmo.

A chave fica em `~/Library/Application Support/Dino/secrets.json`, com
permissão `0600`. Keychain seria o lugar mais correto, mas como o app é assinado
ad-hoc (uma identidade nova a cada build), o Keychain pediria permissão toda vez
que você recompilasse.

## Preferências

`Dino` no menu (ou `Cmd+,`, ou a engrenagem no cabeçalho): chave da API, modelo,
tamanho do Dino, fixar por cima e streaming.

O system prompt do Dino é **fixo**, em `Sources/Dino/Personality.swift`. Ele é a
personalidade do personagem e não dá pra editar pela interface, pra não derivar
com o tempo — se quiser mudar, edite o arquivo e recompile.

## Como mexer no dinossauro

- **Arrastar**: pela faixa do título no cabeçalho.
- **Redimensionar**: pela alça no canto inferior direito.
- **Fixar por cima**: o botão de tachinha no cabeçalho.
- **Nova conversa**: o botão de recomeçar (a conversa fica salva entre execuções).

Quando a janela fica estreita demais para um campo de texto decente, o Dino sobe
e o input ocupa a largura toda sozinho (`ViewThatFits`), em vez de espremer o
campo até o placeholder quebrar letra por letra.

## Arquitetura

```
Sources/Dino/
  App.swift            entry point AppKit puro + AppDelegate (menu, Edit p/ Cmd+V)
  SettingsWindow.swift janela de Preferências, em AppKit
  PetWindow.swift      NSPanel sem moldura, sempre-no-topo, arrastável
  WindowChrome.swift   vistas AppKit reais de arrastar/redimensionar
  PetRootView.swift    o widget: cabeçalho, transcrição, campo de digitação
  DinoSprite.swift     o ciclo de respiração e o piscar
  Balloon.swift        balões com rabinho
  ChatStore.swift      estado da conversa + orquestração
  OpenCodeGo.swift     cliente HTTP (streaming SSE)
  ChatHistory.swift    conversa salva entre execuções
  AppSettings.swift    preferências (UserDefaults)
  Secrets.swift        a API key
  SupportDirectory.swift  onde ficam a chave e a conversa
  LegacyCleanup.swift  apaga o que sobrou do nome antigo (DinoWidget)
  Sprites.swift        carregamento dos sprites
  Personality.swift    o system prompt do Dino (fixo)
  SettingsView.swift   janela de Preferências
  VisualEffectBackground.swift  o vidro fosco
  SelfTest.swift       `--selftest`: testa o cliente sem abrir a janela
  RenderHarness.swift  `--render <dir>`: desenha o widget em PNG, sem tela
  Debug.swift          logs atrás de `DINO_DEBUG=1`
```

Dois atalhos de desenvolvimento, porque testar UI no Mac é chato:

```sh
./build/Dino.app/Contents/MacOS/Dino --selftest
./build/Dino.app/Contents/MacOS/Dino --render /tmp/out
./build/Dino.app/Contents/MacOS/Dino --prompt      # imprime o system prompt
```

O `--render` escreve o widget em vários tamanhos mais uma tira de balões e uma
dos frames. Ele **não** desenha o vidro nem os campos de texto (são vistas
AppKit, que o `ImageRenderer` não fotografa), então serve para conferir layout
e balões — o vidro e o texto você olha na tela.

## Sprites

Os sprites ficam em `Resources/sprites/` e são copiados para o bundle pelo
`build-app.sh`. Para trocar a arte, jogue um novo sprite sheet (uma tira
horizontal, frames separados por colunas vazias) e rode:

```sh
python3 tools/slice_sprites.py ~/Downloads/dino-breathing.png Resources/sprites --report --preview
```

Os sheets originais não ficam no repositório — só os frames já fatiados. O
sheet em uso no momento é o de 5 frames (`dino-breathing`).

O contrato é:

| arquivo | o que é |
| --- | --- |
| `idle_1.png` .. `idle_N.png` | um ciclo inteiro de respiração |
| `blink.png` | só os olhos fechados, transparente no resto |

O sheet é lido **em ordem**: `idle_1` e `idle_N` são a mesma pose de repouso e o
frame mais cheio fica no meio. O app caminha essa sequência para cima e para
baixo, então um sheet novo só precisa manter essa forma.

O runner garante isso de duas maneiras:

1. **Separação por colunas vazias**, não por proporção. Um sheet de 5 frames e um
   de 3 podem ter a mesma largura total, então a contagem não sai do tamanho.
2. **Ancoragem pelos pés** (borda de baixo + centroide das pernas). Sem isso o
   dino desliza para os lados enquanto respira, porque o ChatGPT desenha cada
   frame numa posição ligeiramente diferente.

Também é ele que pinta o `blink.png`: acha o olho sozinho (maior mancha escura
compacta na cabeça), cobre com a cor da pele e desenha a pálpebra fechada. Por
isso a arte pode ser regenerada sem editar constantes.

### Detalhes que custaram caro

- **Não faça cross-fade entre os frames.** Eles são desenhos independentes, então
  as silhuetas nunca coincidem e a mistura vira uma imagem fantasma. A troca é
  seca, como pixel art pede.
- **O piscar só acontece durante a pausa de pulmão vazio.** O overlay é alinhado
  a uma pose fixa; piscar no meio do movimento deixaria a pálpebra fora do lugar.
- **A respiração é dos frames, não de um `scaleEffect`.** Os pés ficam plantados
  na mesma linha em todos os frames; mexer o sprite inteiro tira os pés do chão.
- **`NSHostingView` é invertida** (origem no topo). Por isso o chrome da janela
  vive numa camada própria, não invertida, em vez de fazer contas de cabeça
  para baixo dentro da hosting view.
- **`hitTest` recebe o ponto nas coordenadas da *superview*.** Converter de novo
  faz a camada nunca ser encontrada, e foi por isso que arrastar e
  redimensionar não funcionavam.
- **O painel flutua acima da própria janela de Preferências**, então abrir os
  ajustes eleva aquela janela acima do Dino e a foca (`AppCommands.openSettings`).

## Notas

- O `x-opencode-session` é obrigatório no Go, e é por conversa: "Nova conversa"
  gera um id novo.
- O painel é `nonactivating`, então clicar no Dino não rouba o foco do que você
  estava fazendo. Como o Ditado do macOS só escreve no app ativo, o app se
  ativa quando o campo de texto recebe o foco.
