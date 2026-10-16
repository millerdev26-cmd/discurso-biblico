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
| `xcodebuild test` (macOS) | **Pendente** — exigia Xcode (27 testes + compilação do alvo); concluído na atualização abaixo |

## Atualização (16/10/2026) — verificação na nuvem concluída

| Comando | Resultado |
| --- | --- |
| `swift test` | **168 testes, 0 falhas** (Linux e macOS) |
| `Scripts/verify_app_logic.sh` | **54 testes, 0 falhas** |
| `Scripts/parse_check_app.sh` | **49 arquivos, 0 erros de sintaxe** |
| `xcodebuild test` (runner macOS do GitHub Actions, simulador iPhone 16) | **81 testes, 0 falhas** + aplicativo compilado |

A primeira compilação real encontrou **16 defeitos** que a análise sintática não
via — inclusive dois de lógica: as marcações em linha perdiam acentos
(“joao 3:16”) e a nota do apresentador não aparecia no modo de proferimento.
Todos foram corrigidos e estão listados na decisão 17 de
[`DECISOES.md`](../docs/DECISOES.md); os 8 testes novos das marcações
(`InlineMarkupTests`) também estão no CI. O que continua pendente é a
verificação **na tela** (simulador interativo) e em aparelho real — veja
[`LIMITACOES.md`](../docs/LIMITACOES.md) (item 1) e o checklist da seção 5
deste documento.

> A verificação na tela avançou na **fase 7**
> ([`RELATORIO-FASE-7.md`](RELATORIO-FASE-7.md)): testes de interface no CI,
> com capturas de tela. Os números desta tabela são os do fechamento da fase 6.

## Limitações desta fase
- O backup não leva os arquivos da biblioteca (só os registros e anotações).
- DOCX/JWPUB continuam fora da exportação/importação de conteúdo.
- A compilação no iOS foi **concluída** na nuvem (ver atualização acima); o
  que permanece é a verificação na tela e em aparelho — `docs/LIMITACOES.md`
  (item 1) e o checklist de `App/README.md`.

## Próximo passo recomendado
Verificação **na tela**: abrir o projeto num Mac (ou Mac alugado com acesso
remoto), rodar `xcodebuild test` e seguir o checklist na ordem; as áreas de
maior risco no uso real (SwiftData, `PresentationTextView` — TextKit 1 —,
`SpeechPDFRenderer`, `SpeechReaderService`) são as primeiras a verificar.
Para instalar num iPhone sem Mac, decidir entre TestFlight (conta de
desenvolvedor) e xtool (ver `App/README.md`, seção 3).
