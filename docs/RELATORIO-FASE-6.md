# Relatório — Fase 6: Exportação, backup, qualidade e entrega

## Objetivo
Fechar o ciclo do discurso (sair do app em TXT/Markdown/PDF e voltar por
backup), completar os testes do aplicativo, criar a verificação possível fora
do macOS e documentar tudo — inclusive o que não pôde ser verificado.

## Entregas

### Exportação
- `SpeechExporter` (núcleo) — TXT, Markdown e HTML autocontido, com opções
  (notas do apresentador, fontes, metadados) e nome sugerido de arquivo;
  `PDFSpeechRequest` descreve o PDF sem depender de UIKit.
- `SpeechPDFRenderer` (app) — PDF via `UIGraphicsPDFRenderer` com a folha de
  estilo do núcleo.
- `Views/Components/ShareSheet` — `UIActivityViewController` para compartilhar
  (inclui o arquivo de backup; no iPad, popover ancorado).
- Exportação a partir do detalhe do discurso e dos ajustes, com folha de
  opções e prévia do nome do arquivo.

### Backup
- `BackupService` (núcleo) — envelope JSON versionado (`format`,
  `formatVersion`, `exportedAt`, `appVersion`), `inspect` (valida e resume sem
  tocar nos dados), `restore`, `merge` (mesclar por data; substituir sem
  apagar o que não veio no arquivo), `suggestedFileName`.
- `BackupCoordinator` (app) — monta o arquivo temporário para compartilhar,
  lê o escolhido pelo usuário e aplica nos repositórios; a tela mostra resumo,
  modo escolhido e avisos.
- Configurações: seção de backup com exportar, inspecionar/restaurar e
  explicação do que é (e não é) incluído.

### Voz
- `SpeechReaderService` — leitura do discurso em pt-BR com as vozes do sistema
  (offline), bloco a bloco, com pausa/retomada/parada ao sair da tela.

### Qualidade e entrega
- `App/DiscursoBiblicoTests/` completo — 81 testes:
  - Linux: `PayloadCodingTests` (9), `BibleReferenceLinkTests` (11),
    `LibraryFileStoreTests` (8), `LibraryImportServiceTests` (17),
    `BackupCoordinatorTests` (9);
  - Apple (compilados vazios fora dela): `SwiftDataRepositoriesTests` (10),
    `PresentationTextBuilderTests` (12), `PDFKitTextExtractingTests` (5).
- `Scripts/verify_app_logic.sh` — monta um pacote SwiftPM temporário com a
  lógica do app que não depende de Apple e roda **54 testes de verdade** em
  Linux.
- `Scripts/parse_check_app.sh` — `swiftc -frontend -parse` nos 47 arquivos do
  app (limpo).
- Documentação: `README.md` (raiz), `App/README.md` (passo a passo macOS e
  checklist no aparelho), `docs/PROJETO.md`, `docs/DECISOES.md`,
  `docs/LIMITACOES.md` e estes relatórios por fase.

## Defeitos reais encontrados nesta fase (e corrigidos)

1. **`LibraryImportService` não compilaria no Xcode** — a chamada de
   `ImportService.prepare` passava `existingItems`/`policy` antes de
   `sourceURL`, fora da ordem da assinatura. Encontrado pelo
   `verify_app_logic.sh`; corrigido (`App/DiscursoBiblico/Services/LibraryImportService.swift`).
2. **Marcações em linha cruas no modo de proferimento** —
   `PresentationTextBuilder` exibia `*ênfase*`, `{pausa}` e afins
   literalmente. Passou a resolver com `InlineMarkup.plainText`, igual à
   exportação e à estimativa.
3. **Acesso com escopo de segurança impossível de testar fora da Apple** —
   `startAccessingSecurityScopedResource()` centralizado em
   `SecurityScopedAccess` (no-op fora da Apple), permitindo rodar a importação
   e o backup de verdade nos testes em Linux.

## Resultado da verificação

| Comando | Resultado |
| --- | --- |
| `swift test` | **160 testes, 0 falhas** |
| `Scripts/verify_app_logic.sh` | **54 testes, 0 falhas** |
| `Scripts/parse_check_app.sh` | **47 arquivos, 0 erros de sintaxe** |
| `xcodebuild test` (macOS) | **Pendente** — exige Xcode (27 testes + compilação do alvo) |

## Limitações desta fase
- O backup não leva os arquivos da biblioteca (só os registros e anotações).
- DOCX/JWPUB continuam fora da exportação/importação de conteúdo.
- A compilação e a execução no iOS permanecem a maior lacuna — o que fazer
  está em `docs/LIMITACOES.md` (item 1) e no checklist de `App/README.md`.

## Próximo passo recomendado
Abrir o projeto no Mac conforme `App/README.md`, rodar `xcodebuild test` e
seguir o checklist na ordem; as áreas de maior risco (SwiftData,
`PresentationTextView`, `SpeechPDFRenderer`, `SpeechReaderService`) são as
primeiras a verificar.
