# Aplicativo iOS — Discurso Bíblico

Este diretório contém o alvo iOS completo (SwiftUI + SwiftData + PDFKit +
AVFoundation) que consome o pacote local `DiscursoCore` (a raiz do
repositório). Como a compilação do alvo iOS exige o Xcode, este documento
explica **como gerar o projeto, rodar os testes e o que verificar** no Mac.

> Antes de começar: `swift test` (raiz) e `Scripts/verify_app_logic.sh` já
> validam o núcleo e toda a lógica do app independente de Apple. Se algum
> desses comandos falhar, corrija antes de abrir o Xcode.

---

## 1. Requisitos

- macOS com **Xcode 16** (ou 15.4+; o alvo usa `SWIFT_VERSION 5.0` e
  implantação iOS 17).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) via Homebrew (opcional;
  sem ele dá para criar o projeto à mão em 4 passos).
- Simulador iOS 17+ ou um iPhone/iPad.

## 2. Gerar o projeto

```bash
# no macOS, dentro da pasta App/
brew install xcodegen        # se ainda não tiver
xcodegen generate
open DiscursoBiblico.xcodeproj
```

`project.yml` declara dois alvos:

- **DiscursoBiblico** — o aplicativo (fontes em `DiscursoBiblico/`), com o
  pacote local `DiscursoCore` da raiz do repositório;
- **DiscursoBiblicoTests** — os testes do aplicativo
  (`DiscursoBiblicoTests/`).

### Sem XcodeGen (criando o projeto à mão)

1. Xcode → **File ▸ New ▸ Project ▸ iOS App** (SwiftUI, Swift, sem Core Data),
   nome `DiscursoBiblico`, bundle `br.org.discursobiblico.app`.
2. Apague os arquivos de exemplo e adicione a pasta `DiscursoBiblico/` como
   grupo (referência de pasta, “Create groups”, não “Create folder references”
   — os arquivos são compilados).
3. **File ▸ Add Package Dependencies… ▸ Add Local…** e selecione a **raiz do
   repositório** (produto `DiscursoCore`); adicione o produto aos dois alvos.
4. Em **Build Settings**, informe `INFOPLIST_FILE = DiscursoBiblico/Info.plist`
   e `GENERATE_INFOPLIST_FILE = NO` (o `Info.plist` já declara esquema
   `jwlibrary`, tipos de documento e orientações). Crie o alvo de testes de
   unidade `DiscursoBiblicoTests` e adicione a pasta homônima.

## 3. Sem um Mac? Compilar e testar na nuvem

O Xcode só existe para macOS — **não há como instalá-lo em Linux** (o SDK do
iOS faz parte do Xcode e é licenciado apenas para Apple; emular o macOS viola
a licença). Ainda assim, a compilação e os testes podem ser fechados sem
possuir um Mac. Três caminhos, do mais barato ao mais caro:

### a. GitHub Actions (grátis) — recomendado

O repositório inclui o workflow [`.github/workflows/ios.yml`](../.github/workflows/ios.yml).
A cada push, num runner macOS do GitHub Actions, ele:

1. instala o XcodeGen e gera o projeto a partir de `project.yml`;
2. compila o aplicativo para o simulador (`build-for-testing`);
3. executa **todos** os testes — inclusive os 27 de SwiftData/UIKit/PDFKit
   que não rodam em Linux;
4. roda também o núcleo (`swift test`) em Linux **e** macOS;
5. guarda o `xcresult` como artefato para baixar.

Para publicar (o repositório local **já está com os dois commits feitos**):

```bash
# 1. GitHub CLI (Pop!_OS/Ubuntu)
sudo apt install gh
gh auth login

# 2. criar o repositório e enviar tudo
gh repo create discurso-biblico --public --source=. --push

# sem o GitHub CLI: crie o repositório no site e então
git remote add origin git@github.com:SEU-USUARIO/discurso-biblico.git
git push -u origin main
```

Notas:
- **Autoria dos commits:** ainda está como “Discurso Biblico (local)”. Para
  corrigir antes de publicar (reescreve os dois commits locais):
  `git config user.name "Seu Nome" && git config user.email "voce@exemplo.com"
  && git rebase --root --exec 'git commit --amend --reset-author --no-edit'`.
- **Público × privado:** runners macOS são gratuitos em repositórios
  **públicos**; em privados, cada execução consome ≈10 minutos do plano por
  minuto real (o Free dá ≈200 min/mês de macOS — uma ou duas execuções).
  Dá para começar público e trocar para privado depois (Settings ▸ General ▸
  Danger Zone), ciente do custo.

Acompanhe em **Actions ▸ iOS**. O log mostra o mesmo `xcodebuild test` que
você rodaria num Mac — cada erro de compilação aparece com arquivo e linha.
Runners macOS são gratuitos em repositórios **públicos**; em privados contam
no limite do plano Free (2.000 min/mês com multiplicador 10× para macOS,
≈ 200 min).

### b. Mac alugado na nuvem — se quiser o simulador na tela

Serviços como **MacinCloud**, **MacStadium** ou **Scaleway** alugam Mac por
hora (a partir de ~US$ 1/h; há serviços de locação de Mac no Brasil). Com
acesso remoto (VNC/SSH) você instala o Xcode e roda o checklist da seção 5 na
interface — é a única forma de “ver” o app sem ter o Mac em casa.

### c. Mac emprestado — se for só abrir e rodar

O projeto **já está gerado no repositório** (`App/DiscursoBiblico.xcodeproj`, criado
com o XcodeGen 2.46 e commitado): em qualquer Mac, é só abrir e `⌘B`/`⌘U`.
Se você editar `project.yml`, regenere no Mac com
`brew install xcodegen && xcodegen generate` (a versão Linux do XcodeGen
também funciona: `swift build -c release` no repositório do XcodeGen).

### d. xtool — compilar no próprio Linux (experimental)

O [xtool](https://github.com/xtool-org/xtool) é um "substituto do Xcode"
aberto que compila, assina e **instala** apps iOS direto do Linux — mas
atenção: ele **não dispensa o SDK da Apple**. O `xtool setup` exige:

1. uma conta Apple ID (login interativo; há modo API Key para conta paga);
2. o **`Xcode.xip`** baixado de
   [developer.apple.com/download/all](https://developer.apple.com/download/all/?q=Xcode)
   (~10 GB), do qual o xtool extrai o SDK do iOS (`swift sdk list` → `darwin`);
3. o toolchain **Swift 6.4** para Linux (swift.org) e o `usbmuxd` (para
   aparelho físico).

Feito isso, o xtool compila nosso `DiscursoCore` e as fontes do app (é
possível apontar o pacote local) e instala num iPhone por USB — sem Mac.
O ponto sensível: o app é um projeto Xcode (nosso `project.yml`), enquanto o
xtool trabalha no formato SwiftPM; a adaptação seria um `Package.swift` do
app com os mesmos fontes. E há uma ressalva legal a considerar: o SDK
continua licenciado pela Apple para uso em produtos Apple — extrair e usar o
SDK fora do macOS é área cinzenta (o xtool tem 11,6 mil estrelas e segue
publicado, mas a decisão é sua). Para **validar compilação e testes**, o
caminho (a) já resolve de graça; o xtool vale a pena pelo passo de instalar
num iPhone físico.

> **O que não funciona:** instalar o Xcode em Linux (não existe), Darling
> (não roda o Xcode), máquinas virtuais de macOS (infração de licença) e
> cross-compilação com SDK copiado (licenciamento + inviável com
> SwiftUI/SwiftData). XCUITest na nuvem também é possível, mas o projeto não
> tem testes de interface — a verificação visual é o checklist da seção 5.

## 4. Rodar os testes do aplicativo

```bash
# no macOS
xcodebuild test \
  -project App/DiscursoBiblico.xcodeproj \
  -scheme DiscursoBiblico \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

Os testes se dividem em três grupos:

| Grupo | Arquivos | Plataforma |
| --- | --- | --- |
| Lógica pura (também roda em Linux pelo `Scripts/verify_app_logic.sh`) | `PayloadCodingTests`, `BibleReferenceLinkTests`, `LibraryFileStoreTests`, `LibraryImportServiceTests`, `BackupCoordinatorTests` | Qualquer |
| Persistência | `SwiftDataRepositoriesTests` (10 testes) | iOS/macOS |
| UIKit/PDFKit | `PresentationTextBuilderTests` (12), `PDFKitTextExtractingTests` (5) | iOS/macOS |

Os arquivos dos dois últimos grupos começam com `#if canImport(SwiftData)` /
`#if canImport(UIKit)` / `#if canImport(PDFKit)`: fora da Apple eles compilam
vazios e não quebram o script de verificação.

## 5. Verificação no aparelho/simulador (checklist)

O que a verificação em Linux **não** consegue cobrir — faça nesta ordem:

### Primeiro: compilar e abrir
- [ ] O projeto compila sem erros (`⌘B`). Pontos de atenção: `@ModelActor` e
      `#Predicate` (SwiftData), `UIViewRepresentable` do modo de apresentação,
      `PDFKit` e o painel de referências.
- [ ] O app abre e mostra as abas **Discursos**, **Biblioteca**, **Pesquisa** e
      **Ajustes**.

### Discursos e editor
- [ ] Criar discurso, editar título/tópicos/blocos, escrever `*ênfase*`,
      `{pausa: 3}` e “Jo 3:16” e ver a estimativa de duração mudar.
- [ ] Fechar e reabrir o app: o discurso continua lá, com a mesma posição de
      leitura (retomada).
- [ ] Pastas, favoritos, ordenação e duplicação.
- [ ] Salvamento automático: o indicador muda para “salvo” e não perde texto ao
      trocar de tela no meio da digitação.

### Proferimento (prioridade)
- [ ] Texto grande legível; fonte, altura de linha, coluna, margens e temas
      (claro/escuro/sépia/alto contraste) sem reiniciar o app.
- [ ] Rolagem automática: inicia e para com um toque; **não dispara sozinha**;
      com a política “pausar e retomar”, o texto para ao tocar e volta depois do
      tempo configurado; com “continuar”, não para.
- [ ] Navegação por tópicos e indicador de progresso acompanham o texto.
- [ ] Tela não apaga durante a apresentação; bloqueio de rotação (se ligado)
      mantém retrato; barras do sistema ocultas conforme a preferência.
- [ ] Perfis de leitura: trocar entre “Fonte grande”, “Púlpito” etc. aplica as
      preferências imediatamente.
- [ ] Sair e voltar: o discurso reabre no tópico e na fração corretos.
- [ ] Tocar em “João 3:16” abre o painel do trecho **por cima**, sem perder a
      posição; fechar volta exatamente ao mesmo ponto.
- [ ] Dynamic Type (Ajustes ▸ Acessibilidade ▸ Texto maior) não quebra o layout.

### Biblioteca
- [ ] Importar EPUB, PDF, TXT, Markdown e HTML pela aba Biblioteca.
- [ ] Importar de novo o mesmo arquivo: aparece “já existente” e nada é
      duplicado.
- [ ] Importar um arquivo inválido (renomeie um `.txt` para `.epub`): mensagem
      clara, sem travar a importação dos demais.
- [ ] DOCX/JWPUB: entra como referência com aviso de formato sem leitura.
- [ ] Um EPUB protegido (DRM) é identificado e **não** é aberto.
- [ ] Leitor de EPUB: sumário, capítulos, notas, destaques e marcadores;
      fechar e reabrir retoma a leitura.
- [ ] Leitor de PDF: páginas, zoom e posição; PDF digitalizado gera aviso.
- [ ] Busca local encontra trecho dentro de um material importado.

### Pesquisa e Bíblia
- [ ] Pesquisar “amor de Deus”: resultados do wol.jw.org na página pública de
      pesquisa; abrir um resultado no navegador do app.
- [ ] Desligar o provedor público em Ajustes: a pesquisa continua com os
      provedores locais; sem rede, aparece o estado “sem conexão” e a pesquisa
      local continua funcionando.
- [ ] Pesquisar uma referência (“Salmo 23”): o resultado aponta para a fonte
      oficial; nada de texto bíblico inventado.
- [ ] Salvar uma fonte, escrever uma nota e vinculá-la a um discurso.
- [ ] No painel de referências, o atalho “JW Library” aparece só quando o app
      oficial está instalado (`jwlibrary:///finder`), e o link da web sempre.

### Exportação, backup e voz
- [ ] Exportar TXT, Markdown e PDF (o PDF sai com a folha de estilo), com e sem
      notas do apresentador, e compartilhar pela folha nativa (no iPad, o
      popover aparece ancorado).
- [ ] Exportar backup, restaura-lo em um app “limpo” (apague o app do
      simulador ou use outro aparelho) e conferir discursos, materiais, fontes,
      configurações e perfis.
- [ ] Restaurar um arquivo que não é backup: erro claro, dados intactos.
- [ ] Leitura por voz em pt-BR lê o discurso e para ao sair da tela.

### Privacidade
- [ ] Nenhum pedido de conta, nenhuma coleta; o app funciona em modo avião
      (exceto, claro, as pesquisas externas).

## 6. Onde ficam os arquivos do usuário

- Registros (discursos, biblioteca, pesquisa, ajustes): **SwiftData**, no
  contêiner do app; o modelo completo de cada registro fica em JSON no campo
  `payload` (colunas de índice para listas/buscas).
- Arquivos da biblioteca: `<Suporte do app>/DiscursoBiblico/Library/files/`.
- Backup exportado: arquivo JSON no formato `discurso-biblico-AAAA-MM-DD.json`
  (o `BackupService` do núcleo valida assinatura, versão e integridade).

## 7. Diagnóstico rápido

| Sintoma | Onde olhar |
| --- | --- |
| Erro de `#Predicate`/`FetchDescriptor` | `Persistence/SwiftDataRepositories.swift` e `SwiftDataSchema.swift` |
| Texto do proferimento com tamanho/rolagem errados | `Views/Presentation/PresentationTextBuilder.swift` (atributos) e `PresentationTextView.swift` (medição com TextKit 1) |
| Referência não abre | `Services/BibleReferenceLink.swift` (formato `discursoref://livro/capítulo/versículo`) e o `onOpenURL` em `PresentationView`/`SpeechDetailView` |
| Importação recusa arquivo válido | `ImportService` (núcleo) — extensões aceitas, assinatura, política em `ImportPolicy` |
| PDF sem texto | `Services/PDFKitTextExtracting.swift` (aviso de digitalizado) |
| Backup não restaura | `BackupService` (núcleo) — `format`/`formatVersion` do envelope |
