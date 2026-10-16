# Discurso Bíblico

Aplicativo iOS (Swift + SwiftUI + SwiftData) para **estudar, preparar, editar,
organizar e proferir discursos bíblicos** em português, com uma experiência de
leitura própria — diferente da biblioteca oficial — e prioridade absoluta no
**modo de proferimento** (texto grande, rolagem automática segura, temas,
perfis de leitura e retomada do ponto em que parou).

O projeto é organizado em duas camadas:

| Camada | Onde | O que contém | Como é verificada |
| --- | --- | --- | --- |
| **Núcleo** (`DiscursoCore`) | `Sources/DiscursoCore` | Todos os modelos, persistência, editor, referências bíblicas, EPUB, indexação/pesquisa local, importação/exportação, backup, pesquisa externa e rolagem automática — em Swift puro, sem dependências de terceiros | `swift test` (**168 testes, 0 falhas**, roda em Linux e macOS) |
| **Aplicativo** (iOS) | `App/DiscursoBiblico` | SwiftUI, SwiftData, PDFKit, AVFoundation: telas, navegação, armazenamento dos registros, importação de arquivos, PDF e leitura por voz | `Scripts/verify_app_logic.sh` (**54 testes**, Linux) + `Scripts/parse_check_app.sh` (**49 arquivos**); compilação real e **81 testes no simulador** pelo CI macOS (`.github/workflows/ios.yml`) |

> **Estado atual (verificado):** o núcleo compila e passa em **168 testes** em Linux e macOS. A camada de aplicativo **compila e passa nos 81 testes** no simulador do iOS (iPhone 16, Xcode 16.4, iOS 26.2). Como este ambiente de desenvolvimento não tem Mac, a compilação foi fechada na **nuvem** (GitHub Actions, `.github/workflows/ios.yml`), que roda o mesmo `xcodebuild test` de um Mac a cada push. O que a nuvem **não** cobre — comportamento na tela, aparelho real, vozes do sistema, PDFKit em uso — está listado em [`docs/LIMITACOES.md`](docs/LIMITACOES.md) e no checklist item por item de [`App/README.md`](App/README.md).
>
> **Sem um Mac?** Foi exatamente assim que o alvo iOS foi compilado e testado neste projeto: o workflow `.github/workflows/ios.yml` gera o projeto com o XcodeGen, compila o aplicativo e executa **todos** os testes num runner macOS do GitHub Actions — inclusive os 27 exclusivos de Apple (SwiftData/UIKit/PDFKit) que não rodam em Linux. O projeto Xcode também **já vem gerado** no repositório (`App/DiscursoBiblico.xcodeproj`, com o XcodeGen 2.46 compilado e executado no próprio Linux), pronto para abrir em qualquer Mac. O Xcode em si não roda em Linux; para compilar localmente existe o [xtool](https://github.com/xtool-org/xtool) (que, porém, exige baixar o `Xcode.xip` da Apple). Veja as três opções em [`App/README.md`](App/README.md), seção 3.

---

## O que o aplicativo faz

### Preparação e edição
- Editor por **tópicos e blocos** (título, subtítulo, parágrafo, lista, citação,
  texto bíblico, nota, indicação de orador, separador).
- Marcações em linha simples de digitar: `*ênfase*`, `{pausa: 3}`,
  `{tom: solene}`, `{lento}`, `{olhar}`, `{nota: ...}`.
- Referências bíblicas abreviadas são reconhecidas no texto (“Jo 3:16”,
  “Salmos 23:1-4”, “1Co 13:4, 5”) e podem virar ligações tocáveis.
- Estimativa de duração pela contagem de palavras e marcações de pausa.
- Pastas, etiquetas, favoritos, ordenação, progresso de preparação,
  duplicação de discursos e **salvamento automático** com indicador de estado.
- Notas particulares (do tópico e do discurso) que nunca aparecem na
  apresentação.

### Proferimento (prioridade do projeto)
- Texto grande com controles de **fonte, altura de linha, espaçamento, coluna e
  margens**; temas claro, escuro, sépia, alto contraste e acompanhar o sistema.
- **Rolagem automática** com velocidade ajustável, limites sãos, início/parada
  com um toque e política configurável quando o usuário interage
  (pausar e retomar depois, pausar de vez ou continuar).
- Navegação por tópicos, indicador de progresso, brilho natural da tela
  mantido ligado, bloqueio de rotação opcional, áreas seguras respeitadas.
- **Perfis de leitura** prontos e personalizados (ex.: púlpito, fonte grande).
- **Retomada**: ao voltar para um discurso, o texto reabre no tópico e na
  fração em que o orador parou.
- Toque em uma referência abre o **painel do trecho** por cima, sem perder a
  posição do discurso; o texto bíblico nunca é redistribuído pelo aplicativo —
  abre a fonte oficial (ou o texto que o próprio usuário importou).

### Biblioteca pessoal
- Importação de **EPUB, PDF, TXT, Markdown e HTML** (formato por extensão,
  tamanho, assinatura, DRM e hash de conteúdo).
- Categorias, favoritos, busca local com trechos, offline por padrão.
- Leitor de EPUB (capítulos e sumário próprios), leitor de PDF (PDFKit) e
  leitor de texto, com **notas, destaques e marcadores** e retomada de leitura.
- Arquivos inválidos, duplicados, corrompidos ou protegidos geram mensagens
  claras; DOCX/JWPUB podem ser guardados como referência, mas não são lidos
  (sem quebra de DRM).
- Leitura por voz offline (AVSpeechSynthesizer, pt-BR) para revisar o discurso.

### Pesquisa
- Provedores isolados e desligáveis: biblioteca local, textos bíblicos
  importados, **pesquisa pública no wol.jw.org**, **ligações oficiais
  (jw.org/wol.jw.org)** e pesquisa entre as fontes já salvas.
- Cache com validade, histórico (limitado a 200 consultas), fontes salvas com
  notas e vinculação a discursos.
- Só mecanismos oficiais/documentáveis: sem contornar CAPTCHA, sem páginas de
  login, com respeito a `robots.txt`, limite de requisições e identificação
  (`User-Agent`); quando algo não pode ser lido, o app oferece a **ligação
  oficial** em vez de inventar conteúdo.

### Exportação, backup e privacidade
- Exportação em **TXT, Markdown e PDF** (via PDFKit) com folha de opções
  (notas do apresentador, fontes, metadados) e Compartilhar nativo.
- **Backup** em um arquivo único (`discurso-biblico-AAAA-MM-DD.json`) com
  inspeção antes de restaurar, mesclagem com os dados atuais e avisos de
  compatibilidade.
- Sem contas, sem anúncios, sem telemetria; tudo fica no aparelho; nenhum
  segredo/chave no código.

---

## Estrutura do repositório

```
Package.swift                  Pacote SwiftPM `DiscursoCore` (núcleo, sem dependências)
Sources/DiscursoCore/          Modelos, persistência, editor, EPUB, Bíblia, pesquisa…
Tests/DiscursoCoreTests/       Suíte do núcleo (168 testes) + fixtures sintéticas
App/DiscursoBiblico/           Aplicativo iOS (SwiftUI + SwiftData + PDFKit + AVFoundation)
App/DiscursoBiblicoTests/      Testes do aplicativo (alguns exigem Apple, outros rodam em Linux)
App/project.yml                Especificação XcodeGen do projeto iOS
App/README.md                  Como gerar/abrir/rodar o app no macOS e o que verificar
Scripts/verify_app_logic.sh    Roda, em Linux, a lógica do app que não depende de Apple
Scripts/parse_check_app.sh     Análise sintática de todos os arquivos do app
Scripts/make_fixtures.py       Regenera as fixtures sintéticas dos testes
docs/DECISOES.md               Decisões de engenharia e por quê
docs/LIMITACOES.md             Limites conhecidos e o que ainda falta verificar
docs/PROJETO.md                Arquitetura, módulos, fluxos e matriz de verificação
docs/RELATORIO-FASE-1..6.md    Relatórios por fase (entregas, testes, limites)
```

---

## Como verificar (Linux ou macOS)

```bash
# 1. Suíte do núcleo — 168 testes
swift test

# 2. Lógica do aplicativo que não depende de Apple — 54 testes
Scripts/verify_app_logic.sh

# 3. Sintaxe de todos os arquivos do aplicativo — 0 erros
Scripts/parse_check_app.sh
```

Para compilar e rodar o aplicativo iOS (macOS + Xcode 16+, opcionalmente
XcodeGen), siga [`App/README.md`](App/README.md); lá está a lista do que
verificar no aparelho/simulador, item por item.

Sem um Mac, use o caminho da nuvem — **já usado neste projeto, com o CI verde**:
o repositório está publicado no GitHub e o workflow
`.github/workflows/ios.yml` compila e testa tudo num runner macOS do GitHub
Actions a cada push (`Actions ▸ iOS`); veja o passo a passo em
[`App/README.md`](App/README.md), seção 3.

---

## Documentação

| Documento | Assunto |
| --- | --- |
| [`docs/PROJETO.md`](docs/PROJETO.md) | Arquitetura, módulos, fluxos de dados e matriz de verificação |
| [`docs/DECISOES.md`](docs/DECISOES.md) | Decisões técnicas e justificativas (dependências, SwiftData, rolagem, pesquisa, DRM) |
| [`docs/LIMITACOES.md`](docs/LIMITACOES.md) | Limites conhecidos, o que não é suportado e o que falta verificar no Mac |
| [`docs/RELATORIO-FASE-1.md`](docs/RELATORIO-FASE-1.md) … [`-6`](docs/RELATORIO-FASE-6.md) | Relatórios por fase: entregas, testes, limitações |
| [`App/README.md`](App/README.md) | Gerar o projeto, rodar no simulador/aparelho e checklist de verificação |

## Privacidade e conteúdo

- Todo o conteúdo do usuário (discursos, materiais, anotações, posições de
  leitura, histórico) fica **no aparelho**; não há sincronização obrigatória.
- Nenhuma tradução da Bíblia é redistribuída pelo aplicativo: o app aponta
  para a fonte oficial ou usa um texto importado pelo próprio usuário.
- Arquivos com proteção de conteúdo (DRM) são identificados e **não** são
  abertos nem contornados.
- As consultas externas usam apenas páginas públicas oficiais, com
  identificação, limite de requisições e cache local.
