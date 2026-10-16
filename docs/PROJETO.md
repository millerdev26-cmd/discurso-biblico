# Arquitetura do projeto

Documento de referência da estrutura: o que existe, onde está, como os dados
andam e como cada parte é verificada.

---

## 1. Camadas

```
┌──────────────────────────────────────────────────────────────────────┐
│ Aplicativo iOS (App/DiscursoBiblico)                                 │
│   SwiftUI · SwiftData · PDFKit · AVFoundation · UIKit                │
│                                                                      │
│   Views ──► ViewModels ──► Serviços (AppEnvironment) ──► Protocolos   │
│                                                        do núcleo     │
└───────────────────────────────┬──────────────────────────────────────┘
                                │  depende de
┌───────────────────────────────▼──────────────────────────────────────┐
│ Núcleo DiscursoCore (Sources/DiscursoCore)                           │
│   Swift puro · Foundation apenas · zero dependências externas         │
│                                                                      │
│   Models · Persistence · Support · Bible · EPUB · ImportExport        │
│   Research                                                           │
└───────────────────────────────┬──────────────────────────────────────┘
                                │  depende de
┌───────────────────────────────▼──────────────────────────────────────┐
│ Platforma do sistema (Foundation; no app: SwiftData/PDFKit/UIKit)     │
└──────────────────────────────────────────────────────────────────────┘
```

Regra de ouro: **decisões de domínio não conhecem a Apple**. O que é
específico da Apple fica no app, atrás de protocolos do núcleo
(`SpeechRepository`, `LibraryRepository`, `PDFTextExtracting`,
`BibleTextProvider`, `ResearchProvider`, `HTTPFetching`).

## 2. Mapa de arquivos

### Núcleo — `Sources/DiscursoCore/`

| Pasta | Arquivos | Responsabilidade |
| --- | --- | --- |
| `Models/` | `Speech`, `SpeechSection` (+`SpeechBlock`, `CueKind`), `PresentationPreferences` (+`ReadingProfile`), `ReadingPosition` (+`ReadingLocator`, `LibraryReadingPosition`), `SourceLink`, `LibraryItem` (+anotações/marcadores/destaques), `Research` (+provedores, resultados, histórico), `AppSettings` | Modelos serializáveis (Codable/Hashable), regras simples (progresso, contagens, duração, resumo) |
| `Persistence/` | `Repositories` (protocolos), `DocumentStore` (JSON atômico), `FileRepositories`, `InMemoryRepositories`, `AutosaveCoordinator` | Armazenamento agnóstico e salvamento automático |
| `Support/` | `PortugueseText`, `InlineMarkup`, `SpeechDurationEstimator`, `SpeechTextRenderer`, `AutoScroll`, `PresentationSession` | Texto em português, marcações em linha, estimativa, renderização TXT/MD/HTML, rolagem automática e sessão de proferimento |
| `Bible/` | `BibleBookCatalog` (66 livros, abreviações pt-BR), `BibleReference` (+parser), `BibleTextProvider` | Reconhecimento e ligações de referências; texto bíblico só por ligação oficial ou texto importado |
| `EPUB/` | `ZipArchive`, `Inflate` (+CRC-32), `EPUBModels`, `EPUBParser`, `HTMLTextExtractor` | Leitura de EPUB sem bibliotecas externas, com diagnóstico e detecção de proteção |
| `ImportExport/` | `ImportService`, `LibraryIndexer`, `TextIndex`, `PDFTextExtractor`, `SpeechExporter`, `BackupService` | Triagem de importação, indexação/pesquisa local, exportação e backup |
| `Research/` | `ResearchProviders`, `ResearchService`, `LocalResearchProviders`, `WolSearchProvider`, `WOLSearchResultParser` | Provedores isolados, cache/histórico, parser da página pública do WOL |

### Aplicativo — `App/DiscursoBiblico/`

| Pasta | Arquivos | Responsabilidade |
| --- | --- | --- |
| raiz | `DiscursoBiblicoApp`, `AppEnvironment`, `Info.plist` | Composição (contêiner SwiftData, repositórios, serviços, ajustes), ciclo de vida |
| `Persistence/` | `SwiftDataSchema` (`@Model`s), `SwiftDataRepositories` (`@ModelActor` + repositórios), `PayloadCoding`, `LibraryFileStore`, `SecurityScopedAccess` | Registros do banco, arquivos da biblioteca, acesso escopado |
| `Services/` | `NetworkMonitor`, `SystemSupport` (orientação, tela acesa, háptica, área de transferência), `PDFKitTextExtracting`, `LibraryImportService`, `BackupCoordinator`, `SpeechPDFRenderer`, `SpeechReaderService`, `BibleReferenceLink` | Integrações com o sistema |
| `ViewModels/` | `SpeechList`, `SpeechDetail`, `SpeechEditor`, `Presentation`, `Library`, `Research`, `Settings` | Estado das telas e chamadas aos repositórios/serviços |
| `Views/` | `RootView` (abas), `Speeches/` (lista, detalhe, editor), `Presentation/` (tela, texto, construtor, folha de ajustes), `Bible/` (painel e seletor de referências), `Library/` (lista e leitor), `Research/`, `Settings/`, `Components/` | Interface SwiftUI |

### Testes e scripts

| Caminho | Conteúdo |
| --- | --- |
| `Tests/DiscursoCoreTests/` | 160 testes do núcleo + `Fixtures/` (EPUB, DEFLATE, WOL, biblioteca) |
| `App/DiscursoBiblicoTests/` | 81 testes do app (54 rodam em Linux; 27 exigem Apple) |
| `Scripts/make_fixtures.py` | Gera as fixtures sintéticas |
| `Scripts/verify_app_logic.sh` | Pacote SwiftPM temporário com a lógica do app que roda fora da Apple |
| `Scripts/parse_check_app.sh` | `swiftc -frontend -parse` em todos os arquivos do app |

## 3. Fluxos principais

### Edição e salvamento automático
```
Editor (View) ──► SpeechEditorViewModel ──► AutosaveCoordinator (núcleo)
                        │                         │  debounce
                        │                         ▼
                        └────────────────► SpeechRepository.save(Speech)
                                                  │
                                ┌─────────────────┴──────────────────┐
                                ▼                                    ▼
                   SwiftDataSpeechRepository              InMemory/File (testes,
                   (payload JSON + colunas de índice)      previews, diagnóstico)
```

### Proferimento
```
PresentationView ──► PresentationViewModel
      │                     │  monta NSAttributedString (PresentationTextBuilder)
      │                     │  mede seções (TextKit 1 no PresentationTextView)
      │                     ▼
      │             AutoScrollEngine (pt/s, política de interação)
      ▼
toque em "João 3:16" ──► discursoref://43/3/16 ──► painel do trecho (sheet)
                                                   ├─ ligação oficial (WOL/jw.org)
                                                   └─ texto importado (se houver)
```

### Biblioteca
```
fileImporter ──► LibraryImportService
                   │  1. ImportService.prepare (extensão, tamanho, assinatura,
                   │     DRM, hash/duplicidade)  ← nada é gravado antes
                   │  2. LibraryFileStore.store (cópia para o app)
                   │  3. LibraryIndexer.buildIndex (EPUB/PDF/texto → índice)
                   │  4. LibraryRepository.save + saveIndex
                   ▼
        Leitor (EPUB/PDF/texto) com notas, destaques, marcadores e retomada
```

### Pesquisa
```
ResearchView ──► ResearchViewModel ──► ResearchService
                                          │ escolhe provedores habilitados
                                          │ cache "<id>|<consulta>" e histórico
                                          ├─ local.library / local.scripture / local.saved
                                          ├─ wol.public.search (página pública, com política)
                                          └─ jworg.official.link (ligações oficiais)
```

### Backup
```
exportar ──► BackupCoordinator ──► BackupService.export (envelope v1) ──► arquivo
restaurar ──► BackupCoordinator.inspect (resumo, sem tocar nos dados)
                └──► BackupService.restore/merge (.merge ou .replace) ──► repositórios
```

## 4. Matriz de verificação

| Área | Suíte | Plataforma | Nº |
| --- | --- | --- | --- |
| Rolagem automática, sessão, autosave, posições | `AutoScrollAndSessionTests` | Linux | 17 |
| Referências bíblicas (catálogo, abreviações, intervalos) | `BibleReferenceParserTests` | Linux | 29 |
| Texto bíblico importado + ligações oficiais | `BibleTextProviderTests` | Linux | 14 |
| EPUB (ZIP, DEFLATE, nav/NCX, proteção, HTML) | `EPUBTests` | Linux | 26 |
| Exportação TXT/MD/HTML e backup | `ExportBackupTests` | Linux | 18 |
| Importação, indexação, pesquisa local | `ImportServiceTests` | Linux | 33 |
| Pesquisa (provedores, cache, histórico, política) | `ResearchTests` | Linux | 23 |
| Codificação dos registros do SwiftData | `PayloadCodingTests` | Linux | 9 |
| Ligações `discursoref://` | `BibleReferenceLinkTests` | Linux | 11 |
| Arquivos da biblioteca | `LibraryFileStoreTests` | Linux | 8 |
| Importação no app (lote, duplicados, DRM, avisos) | `LibraryImportServiceTests` | Linux | 17 |
| Backup no app (exportar, inspecionar, restaurar) | `BackupCoordinatorTests` | Linux | 9 |
| Registros SwiftData (CRUD, pastas, índices, perfis, histórico) | `SwiftDataRepositoriesTests` | Apple (Xcode) | 10 |
| Texto do proferimento (faixas, marcações, links, temas) | `PresentationTextBuilderTests` | Apple (Xcode) | 12 |
| Extração de PDF com PDFKit | `PDFKitTextExtractingTests` | Apple (Xcode) | 5 |
| Sintaxe de todos os arquivos do app | `parse_check_app.sh` | Qualquer | 47 arquivos |

Comandos:

```bash
swift test                     # 160 testes do núcleo
Scripts/verify_app_logic.sh    # 54 testes do app em Linux
Scripts/parse_check_app.sh     # sintaxe
# no macOS: xcodebuild test …  # + 27 testes e o app inteiro
```

## 5. Convenções do código

- **Idioma**: nomes de tipos, métodos e variáveis em português (o domínio é
  brasileiro: discurso, tópico, trecho, estante), com termos técnicos
  consagrados quando fizer sentido (`payload`, `hash`).
- **Erros**: `LocalizedError` com `errorDescription`/`recoverySuggestion` em
  português, prontos para a interface; nunca `fatalError` em caminho de dados.
- **Datas**: ISO 8601, sem fração de segundo, na serialização; `Date` em
  memória.
- **Testes**: nomes descritivos em português; um comportamento por teste;
  fixtures sintéticas.
- **Comentários**: explicam *por que*, no cabeçalho de cada arquivo
  (a decisão e o contexto), não o óbvio linha a linha.
