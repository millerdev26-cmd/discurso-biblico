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

## 17. Testes: 160 no núcleo, 54 no app (Linux), 27 no app (Apple)

**Decisão.** Toda regra tem teste no nível em que pode rodar:
- núcleo (Linux): `swift test` — 160;
- lógica do app independente de Apple (Linux): `Scripts/verify_app_logic.sh`
  — 54;
- persistência SwiftData e UIKit/PDFKit: executados no Xcode/macOS — 27;
- sintaxe de todos os arquivos do app: `Scripts/parse_check_app.sh`.

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

## 18. Fixtures sintéticas

**Decisão.** EPUBs, PDFs, casos de DEFLATE e arquivos de exemplo são gerados
por `Scripts/make_fixtures.py` — nada de conteúdo de terceiros nos testes.

**Por quê.** Licenças, determinismo e reprodutibilidade.

## 19. Projeto iOS descrito em texto (`XcodeGen`)

**Decisão.** `App/project.yml` é a fonte da verdade do projeto; o
`.xcodeproj` não é versionado. O arquivo também documenta como criar o
projeto manualmente no Xcode, sem XcodeGen.

**Por quê.** Projetos `.xcodeproj` são difíceis de revisar e de mesclar; o YAML
mantém tudo legível e reproduzível.

## 20. Preview e recuperação de armazenamento

**Decisão.** `AppEnvironment` abre o contêiner SwiftData; se não conseguir,
cai para um contêiner em memória e registra um aviso para a interface. Os
previews do SwiftUI usam ambientes em memória com dados de exemplo. Os avisos
de armazenamento (`RepositoryWarning`) aparecem uma vez na interface e são
consumidos.

**Por quê.** Recuperação antes de falhar: o usuário prefere um app que abre
com aviso a um que não abre. Nada é apagado sem ação explícita.
