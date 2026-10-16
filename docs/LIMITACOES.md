# Limitações conhecidas

Este documento lista, sem maquiagem, o que o projeto **não** faz, o que faz com
ressalvas e o que **ainda não pôde ser verificado** neste ambiente. Ele é a
referência para decidir o que fazer antes de publicar.

---

## 1. Verificação do alvo iOS (o item mais importante)

O alvo iOS foi escrito por completo e passou por:

- análise sintática de todos os 49 arquivos Swift (`Scripts/parse_check_app.sh`);
- testes reais da lógica independente de Apple — 54 testes
  (`Scripts/verify_app_logic.sh`), incluindo codificação dos registros,
  ligações de referências, armazenamento de arquivos, importação e backup;
- **compilação real e execução dos 81 testes no simulador** (iPhone 16,
  iOS 26.2, Xcode 16.4), na nuvem, pelo workflow
  `.github/workflows/ios.yml` (GitHub Actions, runner macOS): a cada push,
  `xcodebuild build-for-testing` + `test-without-building` e o núcleo em
  Linux e macOS (168 testes em cada). O `xcresult` fica guardado como
  artefato do workflow.

O que **ainda não está verificado**, porque exige um Mac com simulador
interativo ou um aparelho real:

- nada foi medido em aparelho: desempenho da rolagem automática, precisão da
  medição de seções, PDFKit renderizando/salvando o arquivo de verdade, vozes
  do sistema (AVSpeechSynthesizer), brilho da tela, folha de Compartilhar no
  iPad;
- nenhum fluxo foi percorrido à mão no simulador (toques, gestos, navegação
  entre abas), embora toda a lógica com teste automatizado passe;
- nada foi instalado num iPhone/iPad: instalar exige Xcode, TestFlight com
  conta de desenvolvedor ou xtool (que depende do `Xcode.xip` da Apple).

**Próximo passo:** siga o checklist do [`App/README.md`](../App/README.md),
na ordem (“Primeiro: compilar e abrir”). Áreas de maior risco no uso real,
em ordem: SwiftData (`@ModelActor`, `#Predicate`), `PresentationTextView`
(TextKit 1 e a medição dos tópicos), `SpeechPDFRenderer`,
`SpeechReaderService` e a folha de Compartilhar no iPad.

**Sem um Mac, a compilação e os testes já estão fechados na nuvem:** o
workflow `.github/workflows/ios.yml` roda num runner macOS do GitHub Actions,
gera o projeto com o XcodeGen, compila o alvo iOS e executa os 81 testes do
app (inclusive os 27 que só existem na Apple), além do núcleo em Linux e
macOS. O projeto Xcode também **já vem gerado e commitado**
(`App/DiscursoBiblico.xcodeproj`, com o XcodeGen 2.46 rodando no Linux). O que
continua exigindo um Mac (ou Mac alugado com acesso remoto) é a verificação
**na tela**: simulador interativo e aparelho físico (instalação em iPhone
exige Xcode ou TestFlight com conta de desenvolvedor — ou o xtool, que
também depende do `Xcode.xip` da Apple). O Xcode em si **não** roda em Linux —
não existe instalação oficial, e emulação de macOS viola a licença da Apple;
veja as opções na seção 3 do [`App/README.md`](../App/README.md).

## 2. Formatos de arquivo

| Formato | Situação |
| --- | --- |
| EPUB (reflowable) | Leitura, sumário, capítulos e indexação implementados no núcleo |
| EPUB de layout fixo (FXL), quadrinhos, mídia | **Não** suportado: o parser trata o conteúdo como texto; páginas com posicionamento especial não são reproduzidas |
| PDF | Lido e renderizado com PDFKit no app; PDFs digitalizados (imagens) geram aviso e ficam sem índice de texto |
| TXT, Markdown, HTML | Suportados, com indexação local |
| DOCX | **Não** lido. Pode ser importado como referência com aviso claro; adiado por não haver biblioteca adequada sem dependência de terceiros (decisão 2 em `DECISOES.md`) |
| JWPUB | **Não** lido e **não** desprotegido. É guardado como referência com mensagem que orienta a usar o aplicativo oficial |

O extrator mínimo de PDF do núcleo (usado em testes e como último recurso) só
entende fluxos de texto simples (`Tj`/`TJ` com codificação direta). No app a
extração usa PDFKit; a limitação afeta apenas diagnósticos/fallback.

## 3. Bíblia e pesquisa externa

- O aplicativo **não** inclui tradução da Bíblia e **não** busca copiar texto
  de sites: o painel de trechos mostra a ligação oficial (ou um texto que o
  usuário importou). Sem internet e sem texto importado, o painel mostra
  apenas o caminho para a fonte.
- A pesquisa no `wol.jw.org` usa a **página pública de pesquisa**
  (`/pt/wol/s/r5/lp-t?q=…`). Mudanças no HTML da página podem esvaziar os
  resultados: o parser tem testes com HTML sintético, mas não há garantia
  contra mudanças do site — nesse caso o app mostra a ligação oficial.
- Não há login, CAPTCHA, contorno de bloqueios nem download de publicações:
  essas operações ficam fora do escopo por decisão (item 10 e 11 em
  `DECISOES.md`).
- Resultados externos não são guardados em massa: só o cache com validade, o
  histórico e o que o usuário **salvar** explicitamente.

## 4. Backup

- O backup leva **os registros** (discursos, metadados e anotações da
  biblioteca, pesquisa, ajustes, perfis) — **não** leva os arquivos importados
  (EPUB/PDF/…). Depois de restaurar em outro aparelho, os materiais aparecem
  listados, mas é preciso **reimportar os arquivos** para lê-los.
- Só existe a versão 1 do envelope; não há plano de migração de dados ainda
  (o inspecionador avisa quando o arquivo vem de versão mais nova).
- Não há sincronização automática entre aparelhos nem backup na nuvem.

## 5. Recursos ausentes ou parciais

- **Sync/iCloud**: nenhum.
- **Notificações/lembretes**: nenhum.
- **Colaboração/multiusuário**: nenhum.
- **Leitura por voz**: lê bloco a bloco em pt-BR com as vozes do sistema; não
  faz realce palavra a palavra nem sincroniza com a rolagem.
- **Exportação DOCX**: não existe (TXT, Markdown, HTML e PDF sim).
- **Importação em massa por arrastar e soltar** no iPad: apenas pelo seletor
  de arquivos/compartilhamento.
- **Widgets, Apple Watch, atalhos do sistema**: nenhum.
- **Testes de interface (XCUITest)**: não existem; a verificação visual está
  no checklist manual.
- **Acessibilidade**: Dynamic Type e áreas seguras são respeitados no código;
  VoiceOver foi considerado (rótulos, `accessibilityLabel` onde necessário),
  mas **não** foi verificado em aparelho.
- **Idioma**: apenas português (pt-BR). Nada de internacionalização.

## 6. Desempenho e escala

- As fixtures são pequenas (sintéticas). Os testes cobrem textos longos e
  arquivos malformados no nível de lógica, mas **não** há medição em aparelho
  de: abertura de EPUB grande, indexação de PDF de centenas de páginas,
  rolagem automática em discurso muito longo e busca local em biblioteca cheia.
- O índice local é reconstruído na importação e pode ser reconstruído pelo
  botão de reindexação; não há indexação incremental.

## 7. Ambiente de verificação

- O script `Scripts/verify_app_logic.sh` cobre **6 arquivos** do app
  (`PayloadCoding`, `LibraryFileStore`, `SecurityScopedAccess`,
  `BibleReferenceLink`, `LibraryImportService`, `BackupCoordinator`); os outros
  **33 arquivos de código** da camada de aplicativo (telas, view models,
  integrações com o sistema) só têm a análise sintática
  (`Scripts/parse_check_app.sh`) e a revisão linha a linha.
- O toolchain usado é o Swift 6.2 em Linux (`~/toolchains/swift-6.2`); os
  comandos do README funcionam em macOS também (`swift test`,
  `xcodebuild test`).

## 8. Riscos aceitos conscientemente

- **SwiftData + payload JSON**: duplica armazenamento (colunas de índice +
  JSON). É deliberado (decisão 4); o custo é o tamanho do banco e o trabalho
  de manter as colunas em sincronia — feito em um único lugar
  (`applyIndexColumns`/`update(with:)`).
- **Dependência do PDFKit e do AVSpeechSynthesizer**: são do sistema; mudanças
  de comportamento entre versões do iOS podem exigir ajustes.
- **Parser do WOL**: depende do HTML público; teste com HTML sintético, não
  com o site real (para não criar dependência de terceiros nos testes).
