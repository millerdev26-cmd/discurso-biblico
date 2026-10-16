# Relatório — Fase 7: Verificação na tela (testes de interface e capturas)

## Objetivo

Fechar a lacuna que restava da fase 6: o aplicativo compilava e a lógica passava,
mas **ninguém tinha visto as telas**. Sem Mac nesta máquina, a forma de ver o
app é abrir o simulador em outro lugar (runner macOS do GitHub Actions) e
**fotografar** o resultado. Esta fase entrega essa verificação — e, de passagem,
corrige o defeito que ela encontrou.

## Entregas

### Testes de interface (`App/DiscursoBiblicoUITests/`)

Dois testes que abrem o aplicativo de verdade no simulador:

- `testDiscursoDetalheEditorEProferimento` — lista de discursos, detalhe,
  editor, modo de proferimento (tela limpa e com os controles), ajustes da
  apresentação, texto maior e salto para o próximo tópico;
- `testBibliotecaLeituraEPesquisa` — biblioteca com o material de exemplo,
  leitura interna do material e as abas Pesquisar e Ajustes.

Cada passo guarda uma captura de tela (`XCTAttachment`, `keepAlways`); são 12 no
total. O workflow extrai os anexos do `.xcresult`
(`xcrun xcresulttool export attachments`) e publica no artefato
**`capturas-simulador`**.

### Conteúdo de exemplo (`DemoSeed`)

O app só cria conteúdo quando é iniciado com o argumento `-uiTestSeed`: um
discurso com marcações de orador, referências bíblicas, notas do apresentador e
indicações, mais um material Markdown importado pela **via real** de importação
(triagem → armazenamento → indexação). Sem o argumento, nada é criado — um
usuário nunca vê conteúdo inventado pelo aplicativo.

O arquivo foi dividido de propósito:

| Arquivo | Depende de | Verificado em |
| --- | --- | --- |
| `Services/DemoSeed.swift` | `DiscursoCore` + Foundation | Linux (5 testes em `DemoSeedTests`) |
| `Services/DemoSeed+Environment.swift` | `AppEnvironment` (SwiftData) | Simulador (testes de interface) |

### Caminho sem Mac pelo xtool

`App/Package.swift`, `App/xtool.yml` e `App/Info-xtool.plist` descrevem o mesmo
aplicativo no formato SwiftPM, para instalar num iPhone físico sem Mac. Nenhum
deles é usado pelo CI. A ressalva honesta está na seção 3d do
[`App/README.md`](../App/README.md) e na decisão 23.

## Defeito real encontrado nesta fase (e corrigido)

1. **O nome do livro nas referências dependia de como o orador escreveu.** O
   discurso de exemplo escreve “Salmo 23:1-4” (singular, como se fala) e o
   catálogo canônico é “Salmos”. `DemoSeedTests` esperava a forma singular e
   **falhou no CI** — o comportamento do app estava certo (referência, nota,
   exportação e backup sempre usam o nome do catálogo), a expectativa é que
   estava errada. O teste passou a esperar “Salmos 23:1-4” e o núcleo ganhou
   `testAbreviacaoDoTextoVirarNomeCanônicoDoCatálogo`, que fixa o comportamento
   para “salmo 23:1-4”, “1Cor 13:4, 5”, “Jo 3:16” e “sl 23”.

   Vale registrar como isso foi encontrado: **não** pela leitura do código, mas
   por um teste rodando de verdade no simulador. É o mesmo motivo que fez a
   primeira compilação revelar 16 defeitos (decisão 17).

2. **Tocar numa linha da lista não abria a tela.** É o defeito que esta fase
   existe para encontrar. Cada `NavigationLink` das duas listas tinha um
   `.simultaneousGesture(TapGesture())` para gravar a “última abertura”. No
   iOS esse gesto **compete com o próprio link**: o toque registra o efeito
   colateral e a navegação não acontece. Na primeira rodada dos testes de
   interface (execução 38917807492) os dois testes falharam exatamente aí — a
   linha era tocada e a tela não abria (no segundo teste, a captura do leitor
   saiu idêntica à da biblioteca, byte a byte). O artefato dessa rodada
   descartou crash, modal e coordenada errada: o toque sintetizado chegou ao
   centro da linha (anexo “Synthesized Event”) e a árvore de acessibilidade
   continuava igual 60 s depois. A correção (commit `8b1ab83`) tirou o gesto
   dos links e passou o registro para a tela de detalhe e para o leitor — onde
   a abertura de fato acontece. Com ela a suíte ficou verde (execução
   38921600296) e as 12 capturas saíram. É o defeito mais valioso desta fase:
   num toque de dedo o conflito de gestos é o mesmo, e o usuário sentiria
   “toco no discurso e não abre”.

## Mudanças de verificação

| Antes | Agora |
| --- | --- |
| `swift test` — 168 | **169** (um teste novo de normalização de referência) |
| `Scripts/verify_app_logic.sh` — 54, 6 arquivos do app | **59**, 7 arquivos (`DemoSeed` entrou) |
| `Scripts/parse_check_app.sh` — 49 arquivos | **53** (entrou também `DiscursoBiblicoUITests/`) |
| `xcodebuild test` no CI — 81 | **86 de unidade + 2 de interface**, com 12 capturas de tela |

## Resultado da verificação

| Comando | Resultado |
| --- | --- |
| `swift test` | **169 testes, 0 falhas** |
| `Scripts/verify_app_logic.sh` | **59 testes, 0 falhas** |
| `Scripts/parse_check_app.sh` | **53 arquivos, 0 erros de sintaxe** |
| `xcodebuild test` (runner macOS, simulador iPhone 16) | **86 testes de unidade + 2 de interface**, capturas no artefato `capturas-simulador` |

Duas rodadas depois da correção, o CI também passou a escolher o **Xcode 26.x**
do runner (mesma geração do simulador) e os testes de interface ganharam toques
com tentativas (elemento → coordenada → pressão curta) e um anexo
`falha-<passo>` por falha; ver decisão 24.

## Limitações desta fase

- Os testes de interface cobrem **um caminho feliz por tela**; não cobrem
  digitação, gestos, rotação, Dynamic Type, iPad, importação/exportação por
  diálogo nem backup — isso continua no checklist do `App/README.md`.
- As capturas provam que a tela renderiza com o conteúdo esperado; elas não
  substituem olhar o resultado e julgar o visual.
- Nada foi medido em aparelho real, e nada foi instalado num iPhone/iPad.
- A compilação pelo xtool **não** foi executada (falta o `Xcode.xip`).

## Próximo passo recomendado

Percorrer o checklist do `App/README.md` (seção 5) num Mac — ou num Mac
alugado — começando pelo modo de proferimento (rolagem automática, retomada e
medição dos tópicos), que é a parte mais delicada do aplicativo e a que nenhum
teste automatizado mede hoje.