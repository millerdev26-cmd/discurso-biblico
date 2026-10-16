# Decisões de engenharia

Este documento registra as decisões técnicas do projeto e **por quê** foram
tomadas. Sempre que uma decisão tiver consequência para quem for dar
manutenção, ela está aqui (ou em [`LIMITACOES.md`](LIMITACOES.md)).

---

## 1. Núcleo em pacote SwiftPM separado (`DiscursoCore`)

**Decisão.** Toda a lógica de domínio (modelos, editor, referências bíblicas,
EPUB, indexação, importação/exportação, backup, pesquisa, rolagem automática)
mora no pacote `Sources/DiscursoCore`, sem importar SwiftUI/SwiftData/PDFKit.
O aplicativo iOS é uma camada fina que consome esse pacote.

**Por quê.**
- Uma única fonte de verdade para o formato dos dados: o backup, o
  armazenamento em arquivo e os registros do SwiftData usam os mesmos modelos.
- A maior parte do risco do produto (analisar EPUB, reconhecer referências,
  estimar duração, mesclar backup) fica testável **fora** do Xcode.
- O aplicativo pode ser reconstruído (ou portado) sem reimplementar regra.

**Consequência.** O alvo iOS precisa do pacote local no projeto
(`App/project.yml` já declara); qualquer mudança de formato exige atualizar os
dois lados — o que é desejável, porque quebra em um só lugar.

## 2. Zero dependências de terceiros

**Decisão.** ZIP, DEFLATE, CRC-32, leitura de EPUB, conversão de HTML em
texto, extração mínima de PDF e formatação de números/datas são implementados
no projeto. `Package.swift` tem a lista de dependências vazia.

**Por quê.**
- O app é offline-first e precisa continuar funcionando sem rede nem serviços.
- Auditoria e privacidade: nenhum código de terceiros lendo os dados do
  usuário; nada para manter/atualizar por causa de CVE em biblioteca.
- O domínio é pequeno e bem conhecido (ZIP de EPUBs, texto).

**Consequência.** O DEFLATE foi validado contra uma suíte de casos sintéticos
gerados por `Scripts/make_fixtures.py`; qualquer EPUB que use recursos
exóticos (por exemplo, compressão que não seja deflate) cai no caminho de
aviso, não de exceção.

## 3. Swift 5 (modo de linguagem) com toolchain 6.2, iOS 17

**Decisão.** `swiftLanguageMode(.v5)` no pacote e `SWIFT_VERSION 5.0` no
Xcode; implantação mínima iOS 17.

**Por quê.**
- O código é compatível com Swift 6, mas exigir concorrência estrita em todo o
  código de UI/domínio traria ruído sem ganho real para um app de um usuário.
- iOS 17 é o mínimo que traz SwiftData maduro no aparelho.

**Consequência.** Se um dia o projeto migrar para modo estrito, os pontos de
atenção estão nos atores de armazenamento (`@ModelActor`) e nos serviços
`Sendable`.

## 4. Persistência: armazenamento em arquivo no núcleo, SwiftData no app

**Decisão.**
- Núcleo: repositórios em arquivo (JSON atômico, um arquivo por entidade,
  leitura tolerante a arquivos corrompidos) e em memória (testes/previews).
- Aplicativo: **SwiftData**, com **colunas de índice** (título, datas,
  contagens, favorito, categoria…) e o **modelo completo em JSON** no campo
  `payload`.

**Por quê.**
- Os protocolos de repositório (`SpeechRepository`, `LibraryRepository`…)
  mantêm a interface agnóstica: as telas falam com o protocolo, e os testes em
  Linux usam as implementações em memória/arquivo.
- Guardar o modelo completo como JSON evita “duas verdades” entre o esquema do
  SwiftData e os modelos testados; o `payload` é o **mesmo** formato do backup
  e do armazenamento em arquivo (`PayloadCoding` usa ISO 8601 + chaves
  ordenadas, iguais ao `DocumentStore`).
- Colunas de índice dão as listas/ordenações rápidas que o SwiftData faz bem.

**Consequência.** Datas são normalizadas para o segundo (ISO 8601 sem fração),
como no armazenamento em arquivo; testes que comparam modelos usam datas
exatas. Registros órfãos (payload inválido) são ignorados nas leituras em vez
de derrubar o app.

## 5. `@ModelActor` + classes de repositório que encaminham

**Decisão.** Cada área (discursos, biblioteca, pesquisa, ajustes) tem um
`actor` `@ModelActor` com o próprio contexto do SwiftData, e uma classe que
apenas encaminha as chamadas para cumprir o protocolo do núcleo.

**Por quê.** Mantém o contexto do SwiftData fora do ator principal, evita
bloquear a interface e deixa os testes do app exercitarem exatamente os
protocolos que a interface usa.

## 6. Modo de proferimento com `UITextView` (TextKit 1)

**Decisão.** O texto apresentado é um `UITextView` não editável, com
`usingTextLayoutManager: false` (TextKit 1), dentro de
`UIViewRepresentable`.

**Por quê.**
- A rolagem automática precisa de offsets **exatos** por seção e por quadro:
  com TextKit 1, `layoutManager.boundingRect(forGlyphRange:in:)` dá a medição
  de forma estável e barata.
- O `UITextView` resolve seleção, links (`NSAttributedString.Key.link`),
  acessibilidade e Dynamic Type de graça.

**Consequência.** As medições devem ser refeitas quando a largura, o tamanho
de fonte ou as preferências mudarem; esse recálculo está concentrado em
`PresentationTextView`/`PresentationViewModel`.

## 7. Rolagem automática que nunca “dispara sozinha”

**Decisão.** `AutoScrollEngine` (núcleo) avança o deslocamento em função do
**tempo decorrido** entre quadros, com velocidade em pontos/segundo
(limites 6…90 após suavizar a faixa da preferência) e política de interação:
pausar de vez, pausar e retomar depois de N segundos, ou continuar.

**Por quê.** Rolagem automática por `Timer` acumula erro e “anda sozinha”
depois de pausas e mudanças de tela — o pior defeito possível em um discurso.
O motor é puro (testável) e o texto só anda quando alguém o instrui a andar;
interação do usuário respeita a política escolhida.

**Consequência.** Ao pausar, a posição é mantida; ao retomar, o texto não salta
(e o motor está coberto por 17 testes no núcleo).

## 8. Ligações internas `discursoref://`

**Decisão.** Referências bíblicas no texto apresentado viram links
`discursoref://<livro>/<capítulo>/<versículo>` (ex.: `discursoref://43/3/16`).

**Por quê.**
- Tocar a referência abre o painel do trecho **por cima**, preservando a
  posição do discurso — requisito explícito do produto.
- É um esquema próprio: não colide com URLs externas, não depende de rede e
  pode ser interpretado por testes unitários (11 no app).

**Consequência.** O painel reconstrói a referência a partir da URL (o
`BibleReferenceLink` é a única implementação desse formato; os testes cobrem
todos os 66 livros).

## 9. Texto bíblico: nunca redistribuir, nunca inventar

**Decisão.** O aplicativo **não** embute traduções da Bíblia. O painel de
trechos usa dois provedores:
1. `OfficialLinkBibleProvider` — abre a consulta na fonte oficial
   (`wol.jw.org`/`jw.org`), com o capítulo/versículo já posicionados;
2. `LocalBibleTextProvider` — usa um texto que o **próprio usuário** importou
   para a biblioteca (quando existir).

**Por quê.** Direitos autorais e confiança: o app não exibe texto que não pode
exibir. Se não há fonte oficial nem texto importado, ele mostra a ligação em
vez de “completar” o versículo.

## 10. Pesquisa externa isolada em provedores desligáveis

**Decisão.** Cada fonte é um `ResearchProvider` com `id` estável:
`local.library`, `local.scripture`, `wol.public.search`, `jworg.official.link`,
`local.saved`. O `ResearchService` cuida de cache (chave
`"<provedor>|<consulta normalizada>"`), histórico (limite 200), deduplicação e
mapeamento de estado (sucesso, vazio, offline, falha). O usuário liga/desliga
provedores nos Ajustes; a política (`ResearchAccessPolicy`) define intervalo
mínimo entre requisições, tempo limite, validade do cache e `User-Agent`.

**Por quê.**
- Respeitar `robots.txt`, ToS e limites de uso **por construção**: só páginas
  públicas oficiais, com identificação e intervalo, sem contornar CAPTCHA nem
  acessar área de login.
- Falha de rede nunca deixa o usuário sem nada: os provedores locais continuam
  e, quando a consulta é uma referência bíblica, a ligação oficial é oferecida.

**Consequência.** Nada de raspagem indiscriminada: quando uma página não pode
ser lida de forma documentável, o app oferece o link em vez de tentar outro
caminho.

## 11. JWPUB/DOCX: não quebrar proteção de conteúdo

**Decisão.** `.jwpub` e `.docx` são reconhecidos, podem ser **guardados** na
biblioteca como referência (com aviso de formato sem leitura) e **nunca** são
abertos à força. EPUB/PDF com DRM são identificados e não são indexados; a
mensagem indica o aplicativo oficial.

**Por quê.** É a postura correta e é o que mantém o app publicável.

## 12. Importação: triagem completa antes de gravar

**Decisão.** Ordem fixa: extensão reconhecida → tamanho (mínimo/limite) →
assinatura/magic bytes → proteção (DRM declarado no pacote) → hash FNV-1a de
64 bits + tamanho para duplicidade → só então gravar o arquivo e indexar.
Falhas viram mensagens prontas (`ImportError`) com sugestão de recuperação e
não interrompem o lote.

**Por quê.** O usuário pode importar uma pasta inteira de uma vez; um arquivo
ruim não pode levar os bons embora nem deixar o app em estado intermediário.

## 13. Backup versionado, inspecionado antes de restaurar

**Decisão.** Envelope JSON com `format`, `formatVersion`, `exportedAt` e o
conteúdo (`BackupEnvelope`): discursos, pastas, biblioteca, pesquisa,
histórico, ajustes e perfis. Restaurar tem dois modos: **mesclar** (padrão,
mais recente vence por `updatedAt`/`importedAt`/`savedAt`) e **substituir**
(não apaga o que não está no backup — e avisa isso).

**Por quê.** Backup é a única operação destrutiva do app: o arquivo é
**inspecionado** e resumido antes de aplicar qualquer coisa, e a mesclagem
nunca sobrescreve silenciosamente um item mais novo.

## 14. Acesso com escopo de segurança centralizado

**Decisão.** Todo acesso a arquivos escolhidos pelo usuário passa por
`SecurityScopedAccess.withAccess(to:)`, que usa
`startAccessingSecurityScopedResource()` na Apple e é um no-op fora dela.

**Por quê.** Mantém o código do app compilável também na verificação em Linux
e evita `#if` espalhados pelas telas/serviços.

## 15. Exportação e PDF

**Decisão.** TXT, Markdown e HTML saem do `SpeechTextRenderer` (núcleo), o
mesmo usado pela estimativa e pela indexação. O PDF é gerado no app com
`PDFSpeechRenderer`/`UIGraphicsPDFRenderer` a partir do HTML do núcleo
(`PDFSpeechRequest`); o Compartilhar usa `UIActivityViewController`.

**Por quê.** O núcleo não pode depender do UIKit; o HTML já é necessário para
outros fins e garante um PDF com a aparência do app (temas e tipografia).

## 16. Voz offline (AVSpeechSynthesizer)

**Decisão.** `SpeechReaderService` lê o discurso em pt-BR com as vozes do
sistema, sem rede nem serviços externos; para ao sair da tela.

**Por quê.** Ajuda a revisar o texto e a estimar o ritmo, sem custo nem
privacidade em risco. É complementar ao modo de proferimento, não o substitui.

## 17. Testes: 169 no núcleo, 59 no app (Linux), 27 no app (Apple)

**Decisão.** Toda regra tem teste no nível em que pode rodar:
- núcleo (Linux e macOS): `swift test` — 169;
- lógica do app independente de Apple (Linux): `Scripts/verify_app_logic.sh`
  — 59;
- persistência SwiftData e UIKit/PDFKit: executados no **simulador do iOS**
  pelo CI macOS — 27 (86 no total, dentro do simulador);
- sintaxe de todos os arquivos do app: `Scripts/parse_check_app.sh` — 53.

**Por quê.** O ambiente de desenvolvimento deste trabalho é Linux; seria
desonesto declarar “compila no iPhone” sem poder rodar o Xcode. A verificação
cobriu o que dá para cobrir de verdade, e o que só o Mac verifica está
listado em [`LIMITACOES.md`](LIMITACOES.md) e no checklist do
`App/README.md`.

**Exemplos de defeitos reais encontrados pela verificação em Linux:**
- `LibraryImportService` chamava `ImportService.prepare` com os argumentos
  fora de ordem (erro de compilação no alvo iOS);
- `PresentationTextBuilder` mostrava `*ênfase*` e `{pausa}` crus no modo de
  proferimento (as marcações agora são resolvidas com `InlineMarkup`, como na
  exportação).

**Defeitos reais encontrados pela primeira compilação completa** (runner
macOS do GitHub Actions, Xcode 16.4, simulador iPhone 16 — nenhum deles
aparecia na análise sintática):

- `TEST_HOST` apontava para `DiscursoBiblico.app`, mas o produto era
  “Discurso Biblico.app” (`PRODUCT_NAME` com espaço): o alvo de testes não
  encontrava o aplicativo. O binário passou a `$(TARGET_NAME)` e o nome de
  exibição continua “Discurso Bíblico” no `Info.plist`;
- `LibraryItem` ambíguo: o framework `DeveloperToolsSupport` (pré-visualizações
  do Xcode) também declara esse tipo. Resolvido com apelido no módulo
  (`CoreAliases.swift`), que tem precedência sobre os importados;
- `SpeechStatus.draft` não existe — os estados são
  `preparing/ready/delivered/archived`;
- o enum aninhado `Section` do `ResearchView` ofuscava `SwiftUI.Section`
  (renomeado para `SearchSection`);
- `UITextView(usingTextLayoutManager:)` não existe no iOS: o modo de
  apresentação agora monta a pilha **TextKit 1 explícita**
  (storage → layout manager → container), garantindo o `NSLayoutManager`
  usado na medição dos tópicos;
- `paragraphAttributes()` devolvia `NSParagraphStyle` e era passado como se
  fosse dicionário de atributos (renomeado `paragraphStyle`);
- o método `block(withID:in:)` era sombreado pelo parâmetro `block` em
  `SpeechEditorView` (renomeado `findBlock`);
- `profiles` é somente-leitura nas telas: faltavam `addProfile`/`deleteProfile`
  no `SettingsViewModel`;
- `deinit` acessava o `ticker` do ator principal
  (`nonisolated(unsafe)` no `PresentationViewModel`);
- `CGSize(width: 0, height: .greatestFiniteMagnitude)` ambíguo (exigiu
  `CGFloat.greatestFiniteMagnitude`);
- `UIApplication.open(url)` dentro de contexto `async` resolve para a variante
  assíncrona (ponte automática do completion handler) e exige `await`; os
  pontos em contexto assíncrono passaram a usar a variante síncrona explícita;
- o mesmo `LibraryItem` ambíguo também derrubava o módulo de testes do
  **núcleo no macOS** (no Xcode, o `XCTest` deixa `DeveloperToolsSupport` no
  escopo): apelido equivalente em `Tests/DiscursoCoreTests/CoreAliases.swift`;
- `SpeechRecord.init(speech:)` chamava `applyIndexColumns` antes de inicializar
  todas as colunas (a inicialização definitiva não aceita isso): o `init`
  passou a atribuir todas as colunas diretamente;
- `PresentationViewModel.init` lia `self.preferences` antes de inicializar
  `session` (mesmo tipo de erro): as preferências saneadas viraram variável
  local usada na sessão;
- **defeito de lógica no núcleo:** os segmentos do `InlineMarkup` (ênfase,
  notas privadas e detalhes de indicação) eram montados a partir do texto
  *normalizado* — sem acentos e em minúsculas — então a apresentação e a
  exportação imprimiam “joao 3:16” no lugar de “João 3:16”. Corrigido na raiz
  (o texto exibido agora sai do texto original) e coberto por 8 testes novos
  em `Tests/DiscursoCoreTests/InlineMarkupTests.swift` — arquivo que não
  existia, e por isso o defeito passou;
- no modo de proferimento, o bloco de **nota do apresentador** era impresso
  como se fosse indicação (`[Marcação]`) em vez do texto da nota; agora sai
  “Nota: …”, igual à exportação (e o parágrafo marcado como nota recebe o
  mesmo rótulo).

## 18. Fixtures sintéticas

**Decisão.** EPUBs, PDFs, casos de DEFLATE e arquivos de exemplo são gerados
por `Scripts/make_fixtures.py` — nada de conteúdo de terceiros nos testes.

**Por quê.** Licenças, determinismo e reprodutibilidade.

## 19. Projeto iOS descrito em texto (`XcodeGen`)

**Decisão.** `App/project.yml` é a fonte da verdade do projeto. O
`.xcodeproj` gerado **também é versionado**, por conveniência: qualquer Mac
abre e compila sem instalar nada. Quem editar o YAML regenera
(`xcodegen generate`) — inclusive **em Linux**: o XcodeGen 2.46 foi compilado
(`swift build -c release`) e executado nesta máquina; a geração não exige Mac.
O arquivo também documenta como criar o projeto manualmente no Xcode, sem
XcodeGen.

**Por quê.** Projetos `.xcodeproj` são difíceis de revisar e de mesclar, então
o YAML continua sendo a origem; mas como o alvo iOS ainda não pôde ser
compilado aqui, deixar o projeto pronto reduz o atrito de quem for fazer a
primeira compilação (basta abrir).

**Consequência.** Duas cópias em jogo: edições manuais no Xcode são
sobrescritas na próxima geração; a regra é editar `project.yml`.

## 20. Preview e recuperação de armazenamento

**Decisão.** `AppEnvironment` abre o contêiner SwiftData; se não conseguir,
cai para um contêiner em memória e registra um aviso para a interface. Os
previews do SwiftUI usam ambientes em memória com dados de exemplo. Os avisos
de armazenamento (`RepositoryWarning`) aparecem uma vez na interface e são
consumidos.

**Por quê.** Recuperação antes de falhar: o usuário prefere um app que abre
com aviso a um que não abre. Nada é apagado sem ação explícita.

## 21. Verificação sem Mac: projeto gerado no Linux + CI macOS; xtool avaliado

**Decisão.** A compilação do alvo iOS é fechada na nuvem, num runner macOS do
GitHub Actions (`.github/workflows/ios.yml`): a cada push ele gera o projeto,
compila para o simulador e roda os 86 testes do app (inclusive os 27 de
SwiftData/UIKit/PDFKit) e os testes de interface (decisão 22), mais o núcleo em
Linux e macOS, guardando o `xcresult` como artefato. O `.xcodeproj` também é
gerado no próprio Linux (decisão 19). O `xtool` (substituto do Xcode para
Linux, verificado rodando nesta máquina — AppImage 1.22.2) fica registrado como
caminho **opcional** para compilar/instalar sem Mac, mas não é adotado por
padrão (decisão 23).

**Por quê.**
- O Xcode **não existe** fora do macOS; o SDK do iOS é distribuído dentro do
  Xcode e licenciado para produtos Apple. Emular macOS viola a licença.
- O runner macOS é gratuito para repositórios públicos e executa exatamente o
  mesmo `xcodebuild test` de um Mac (evidência por arquivo/linha em caso de
  erro), sem baixar 10 GB nem depender de conta Apple.
- O `xtool` exige: conta Apple ID (login interativo), **`Xcode.xip`** (~10 GB,
  developer.apple.com) para extrair o SDK Darwin, toolchain Swift 6.4 e o app
  convertido para o formato SwiftPM dele. Vale o esforço quando o objetivo
  for instalar num iPhone físico sem Mac — não para validar compilação.

**Resultado (16/10/2026).** O caminho foi percorrido de ponta a ponta:
repositório público, 9 rodadas de CI até o verde. A primeira compilação real
encontrou **16 defeitos** que a análise sintática não via — inclusive dois de
**lógica** que só a execução revelava (marcações em linha saindo sem acentos e
a nota do apresentador) —, todos listados na decisão 17; a primeira rodada de
testes de interface encontrou mais um, na decisão 22. Estado final do CI:
núcleo com 169 testes em Linux e macOS, aplicativo compilado e **86 testes de
unidade + 2 de interface passando no simulador** (iPhone 16, Xcode 16.4), com
o `xcresult` e as capturas de tela guardados como artefato.

**Consequência.** O que a nuvem **não** cobre continua sendo a verificação na
tela (simulador interativo/aparelho): permanece no checklist do
`App/README.md` e em [`LIMITACOES.md`](LIMITACOES.md).

## 22. Testes de interface no CI, com conteúdo de exemplo sob demanda

**Decisão.** O alvo `DiscursoBiblicoUITests` (XCUITest) abre o aplicativo de
verdade no simulador, percorre as telas principais e guarda **12 capturas de
tela** como anexos do resultado; o workflow extrai e publica essas imagens no
artefato `capturas-simulador`. Para que as telas tenham conteúdo, o app cria um
discurso de exemplo e um material Markdown **apenas** quando é iniciado com o
argumento `-uiTestSeed` (`Services/DemoSeed.swift` + `DemoSeed+Environment`,
ligados em `AppEnvironment.performStart`). O conteúdo do exemplo é Swift puro,
então é testado também em Linux (`DemoSeedTests`, 5 testes); a instalação no
banco fica num arquivo à parte, que depende do SwiftData.

**Por quê.**
- Sem um Mac, a única forma de **ver** o aplicativo é a imagem: o teste
  automatizado abre a tela, interage nos botões que importam e fotografa o
  resultado. As capturas viram evidência de que o app renderiza, e não só de
  que compila.
- O conteúdo de exemplo fica atrás de um **argumento de lançamento**: no uso
  normal o aplicativo nunca inventa discursos nem materiais para o usuário.
- Manter o conteúdo em um arquivo sem SwiftData permite verificá-lo no Linux,
  onde a maioria das suítes roda; só a gravação no banco precisa da Apple.

**Defeito encontrado por essa via** (primeira execução no CI): o exemplo
escreve “Salmo 23:1-4” no texto, mas o nome canônico do catálogo é “Salmos”, e
`DemoSeedTests` esperava a forma singular — a referência é exibida, gravada no
backup e exportada sempre com o nome do catálogo. O teste passou a esperar a
forma canônica e o núcleo ganhou um teste de regressão
(`testAbreviacaoDoTextoVirarNomeCanônicoDoCatálogo`) para “salmo 23:1-4”,
“1Cor 13:4, 5”, “Jo 3:16” e “sl 23”. O comportamento do app estava certo; a
expectativa é que estava errada — e agora está escrito por quê.

## 23. Manifesto SwiftPM do app para o caminho sem Mac (xtool)

**Decisão.** `App/Package.swift`, `App/xtool.yml` e `App/Info-xtool.plist`
descrevem o mesmo aplicativo no formato SwiftPM, para quem quiser compilar e
instalar num iPhone físico sem Mac pelo `xtool`. As fontes são as mesmas
(`DiscursoBiblico/`), com o mesmo pacote local `DiscursoCore`; o CI **não** usa
esse caminho e continua no XcodeGen + `xcodebuild`.

**Por quê.** Sem Mac, as três saídas são: nuvem (valida compilação e testes, de
graça), Mac alugado (dá a tela) e xtool (compila e **instala** no aparelho).
Deixar o manifesto pronto significa que o passo “instalar no iPhone” não
depende de adaptation: só falta ter o `Xcode.xip` e a conta Apple.

**Consequência — leia antes de usar.** O xtool **não** dispensa o SDK da
Apple: ele extrai o SDK do `Xcode.xip` (~10 GB), cujo licenciamento é da Apple
e a extração fora do macOS é área cinzenta. Com Apple ID gratuita a assinatura
expira em 7 dias. E, como neste ambiente não há `Xcode.xip`, **a compilação
pelo xtool ainda não foi executada** — o que foi conferido foi o formato dos
arquivos (`swift package describe` sem erros e o schema do `xtool.yml`). Para
validar compilação e testes, use a nuvem.

## 24. Testes de interface: Xcode na mesma geração do simulador e toques com três estratégias

**Decisão.** O workflow escolhe o **Xcode 26.x** mais novo instalado no runner
(o padrão do `macos-15` é o 16.4) antes de gerar o projeto. E os testes de
interface tocam por **três estratégias** — toque pelo elemento, toque real por
coordenada e toque com pressão curta —, parando na primeira que faz a tela
esperada aparecer; quando nenhuma funciona, o passo guarda `falha-<passo>`
(captura + árvore de acessibilidade) no artefato do CI.

**Por quê.** A primeira rodada dos testes de interface (execução 38917807492)
falhou nos dois testes: a linha do discurso e a linha da biblioteca eram
tocadas e **nada acontecia na tela**, e a aba "Ajustes" falhava com
`kAXErrorCannotComplete`. O artefato dessa execução permitiu descartar defeito
do aplicativo e apontar o ambiente:

- o evento sintetizado chegou exatamente no centro da linha (anexo
  "Synthesized Event": toque em (195,3; 464,8), dentro do quadro
  `{16, 406} × {361, 116,7}`) e a árvore de acessibilidade continuava idêntica
  60 s depois — sem crash, sem troca de pid, sem modal cobrindo a tela;
- os mesmos toques sintetizados **funcionaram** na barra de abas e na barra de
  navegação (`Importar material`, `Biblioteca`), então o app estava recebendo e
  tratando toques;
- o log de versões mostrou `Xcode 16.4` (SDK iOS 18) contra
  `{ platform:iOS Simulator, OS:26.2 }`: o XCUITest de uma geração testando o
  sistema de duas gerações à frente. No iOS 26 esse descompasso é conhecido por
  produzir exatamente esse sintoma ("toca e não acontece nada"; abas que
  raramente respondem) e o remédio prático é o toque por coordenada.

**Consequência.** Com o Xcode 26 o aplicativo passa a ser compilado com o SDK
do iOS 26 e as capturas mostram a aparência do iOS 26 (é também o sistema dos
aparelhos do autor). O `macos-15` já traz Xcode 26.3/26.2/26.1.1/26.0.1
instalados — o passo novo escolhe o mais novo disponível e imprime a lista e
os simuladores, para o dia em que a imagem do runner mudar. Se um dia o
`Xcode 26.x` não existir, o script mantém o padrão do runner (e a rodada de
testes de interface tende a falhar como falhou aqui — o motivo fica registrado).
