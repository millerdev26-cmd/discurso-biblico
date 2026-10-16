# Relatório — Fase 1: Fundamentos

## Objetivo
Ter a base sobre a qual todas as fases seguintes se apoiam: modelos de dados
completos, persistência agnóstica (arquivo e memória), o pacote de núcleo
compilável/testável fora do Xcode e a estrutura do aplicativo iOS
(composição, registros do SwiftData, telas básicas).

## Entregas

### Núcleo (`Sources/DiscursoCore`)
- `Package.swift` — pacote `DiscursoCore` (swift-tools 6.0, iOS 17/macOS 14,
  **zero dependências**, modo de linguagem Swift 5).
- `Models/` — `Speech`, `SpeechSection`, `SpeechBlock` (`SpeechBlockKind`,
  `CueKind`), `PresentationPreferences`, `ReadingProfile`, `ReadingPosition`,
  `ReadingLocator`, `LibraryReadingPosition`, `SourceLink`, `LibraryItem`
  (anotações, marcadores, destaques), modelos de pesquisa, `AppSettings`
  (com `ResearchAccessPolicy` e `ResearchProviderID`).
- `Persistence/` — protocolos `SpeechRepository`, `LibraryRepository`,
  `ResearchRepository`, `SettingsRepository`; `DocumentStore` (JSON atômico,
  leitura tolerante); `FileRepositories`; `InMemoryRepositories`.
- `Support/` — `PortugueseText` (normalização, sílabas, palavras), `InlineMarkup`
  (segmentos, `plainText`, resumo de indicações), `SpeechDurationEstimator`,
  `SpeechTextRenderer` (TXT/Markdown/HTML).

### Aplicativo (`App/DiscursoBiblico`)
- `DiscursoBiblicoApp`, `AppEnvironment` (contêiner, repositórios, serviços,
  ajustes, `preview()`), `Views/RootView` (abas) e `Components/CommonViews`.
- Persistência: `SwiftDataSchema` (`@Model` de discursos, pastas, biblioteca,
  índice, pesquisa, ajustes, perfis), `SwiftDataRepositories` (`@ModelActor` +
  repositório que encaminha), `PayloadCoding` (ISO 8601 + chaves ordenadas,
  iguais ao `DocumentStore`), `LibraryFileStore`, `SecurityScopedAccess`.
- `App/project.yml` (XcodeGen), `App/DiscursoBiblico/Info.plist` (esquema
  `jwlibrary`, tipos de documento EPUB/PDF/TXT/HTML, orientações).
- `App/DiscursoBiblicoTests/` iniciado com os auxiliares e os testes de
  codificação dos registros.

## Testes
- Núcleo: suítes de modelos/persistência/apoio dentro dos 160 testes
  (`swift test`).
- Aplicativo: `PayloadCodingTests` (9 testes) — ida e volta de discurso,
  material, índice, ajustes/perfil, pesquisa/histórico/cache, ISO 8601,
  determinismo, dados inválidos.
- `Scripts/verify_app_logic.sh` criado nesta fase rodou os primeiros testes de
  app em Linux.

## Limitações desta fase
- O alvo iOS não é compilado neste ambiente (ver `LIMITACOES.md`, item 1).
- Sem migração de esquema: só a versão 1 dos modelos.

## Como verificar
```bash
swift test
Scripts/verify_app_logic.sh
```
