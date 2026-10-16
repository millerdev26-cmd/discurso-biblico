# Relatório — Fase 4: Bíblia e Biblioteca pessoal

## Objetivo
Duas frentes que se completam: (a) reconhecer e consultar referências bíblicas
dentro do discurso, sem redistribuir texto bíblico; (b) importar, organizar,
pesquisar e ler materiais próprios (EPUB/PDF/TXT/Markdown/HTML) offline.

## Entregas

### Bíblia (núcleo e app)
- `BibleBookCatalog` — os 66 livros, nomes e abreviações em pt-BR (com
  ambiguidades tratadas), números canônicos.
- `BibleReference` + `BibleReferenceParser` — “Jo 3:16”, “Salmos 23:1-4”,
  “1Co 13:4, 5”, listas e capítulos inteiros; descrição, identificadores,
  ligação oficial (`wol.jw.org/pt/wol/b/r5/lp-t/nwt/{livro}/{capítulo}#{v}`),
  ligação de busca e atalho opcional para o app oficial (`jwlibrary:///finder`).
- `BibleTextProvider` — `OfficialLinkBibleProvider` (padrão; nunca inventa
  texto) e `LocalBibleTextProvider` (usa texto que o usuário importou).
- `Views/Bible/BibleReferencePicker` (escolher livro/capítulo/versículos) e
  `BiblePassagePanel` (painel por cima, sem perder a posição do discurso).
- `BibleReferenceLink` (app) — `discursoref://` ligações internas tocáveis.

### Biblioteca (núcleo e app)
- `ImportService` — triagem: extensão → tamanho → assinatura → DRM → hash
  (FNV-1a 64) + tamanho para duplicidade; erros e avisos prontos.
- `LibraryFileStore` (app) — arquivos em `<Suporte>/DiscursoBiblico/Library/files/`.
- EPUB sem dependências: `ZipArchive`, `Inflate` (+CRC-32), `EPUBParser`
  (container, OPF, metadados, spine, nav/NCX, títulos), `HTMLTextExtractor`,
  `protectionStatus` (DRM declarado, nunca removido).
- `LibraryIndexer` + `TextIndex` — índice pesquisável com localizador para
  reabrir no ponto exato (capítulo de EPUB, página de PDF, parágrafo de texto).
- `PDFTextExtracting` — protocolo no núcleo; no app, `PDFKitTextExtracting`
  (páginas, avisos de página sem texto e de PDF digitalizado).
- `LibraryImportService` (app) — lote sem parar nos erros, reindexação.
- `Views/Library/LibraryListView` (categorias, favoritos, busca, filtros) e
  `LibraryReaderView` (leitor de EPUB com sumário/capítulos, leitor de PDF via
  PDFKit, leitor de texto) com notas, destaques, marcadores e retomada de
  leitura.

## Testes
- Núcleo: `BibleReferenceParserTests` (29), `BibleTextProviderTests` (14),
  `EPUBTests` (26 — ZIP, DEFLATE, nav/NCX, proteção, HTML, corrompido),
  `ImportServiceTests` (33 — válidos, rejeições, duplicados, formatos sem
  leitura, DRM, PDF).
- Aplicativo (Linux): `LibraryFileStoreTests` (8),
  `LibraryImportServiceTests` (17 — lote, duplicado, extensão inválida, vazio,
  assinatura de PDF, protegido por senha, digitalizado, reindexação),
  `BibleReferenceLinkTests` (11 — todos os 66 livros, faixas, capítulo
  inteiro, endereços inválidos).
- Aplicativo (Apple/Xcode): `PDFKitTextExtractingTests` (5).

## Limitações desta fase
- EPUB de layout fixo (quadrinhos/FXL) não é reproduzido — o conteúdo é lido
  como texto.
- DOCX e JWPUB são guardados como referência, mas não lidos (sem quebra de
  proteção) — ver `LIMITACOES.md`.
- O backup não inclui os arquivos importados; a restauração recria os
  registros e pede a reimportação dos arquivos.

## Como verificar
```bash
swift test
Scripts/verify_app_logic.sh
```
