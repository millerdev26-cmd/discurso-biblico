# Relatório — Fase 5: Pesquisa externa, JWPUB e texto bíblico por ligação

## Objetivo
Pesquisar material de estudo em fontes oficiais **de forma documentável e
respeitosa** (sem raspagem indiscriminada, sem contornar CAPTCHA ou login),
manter tudo isolado em provedores desligáveis, com cache/histórico locais, e
tratar JWPUB com a postura correta: nenhuma quebra de proteção.

## Entregas

### Provedores e serviço (núcleo)
- `ResearchProvider` (protocolo) + `ResearchProviderID`:
  - `local.library` — pesquisa nos materiais importados (índice local);
  - `local.scripture` — referências no texto bíblico importado;
  - `wol.public.search` — página **pública** de pesquisa do WOL
    (`/pt/wol/s/r5/lp-t?q=…`), com política de acesso;
  - `jworg.official.link` — devolve ligações oficiais (jw.org/wol.jw.org)
    sempre que não é possível ler conteúdo;
  - `local.saved` — pesquisa entre as fontes que o usuário salvou.
- `ResearchService` (actor) — cache com chave `"<provedor>|<consulta>"`
  (validade configurável), histórico (200 mais recentes), deduplicação,
  estado (`success`/`empty`/`offline`/`failed`), política por provedor.
- `ResearchAccessPolicy` — intervalo mínimo entre requisições, tempo limite,
  validade do cache, máximo de resultados, `User-Agent` identificado,
  preferir cache, páginas públicas e ligações oficiais ligadas/desligadas.
- `WolSearchProvider` + `WOLSearchResultParser` — parser do HTML da página
  pública, com testes de HTML sintético; `HTTPFetching` abstrato
  (`URLSessionHTTPFetcher` no app, dublê nos testes).
- `BibleTextProvider` — ligação oficial como caminho padrão; texto do usuário
  quando existir; nada inventado.

### Aplicativo
- `Views/Research/ResearchView` + `ResearchViewModel` — busca, resultados por
  provedor, salvar fonte, nota, vincular a discurso, abrir material local sem
  sair da tela, abrir no navegador do app, estados de rede.
- `Services/NetworkMonitor` — estado de conexão para a pesquisa local
  continuar e o resultado externo avisar “sem conexão”.
- `Services/SystemSupport`/`Clipboard`, abrir ligação oficial, atalho
  `jwlibrary:///finder` **somente** quando o app oficial está instalado
  (`LSApplicationQueriesSchemes` no `Info.plist`).
- Ajustes: provedores ligados/desligados individualmente e política de acesso
  visível e editável (`SettingsView`).

### JWPUB
- Reconhecido na triagem como formato **sem leitura**: pode ser guardado como
  referência, com aviso explícito (“foi guardado como referência e não será
  indexado; use o aplicativo oficial”).
- Nenhuma tentativa de abrir, extrair ou contornar o arquivo.
- Alternativas oferecidas na interface: converter para PDF/EPUB/TXT/Markdown ou
  manter como referência.

## Testes
- `ResearchTests` (23, Linux) — provedores locais, ligações oficiais, parser do
  WOL (HTML sintético), cache com validade, histórico, deduplicação, estados de
  erro/offline com provedores restritos, política padrão.
- `BibleTextProviderTests` (14) — provedor oficial, texto importado, e a regra
  de nunca inventar texto.
- Aplicativo: provedores/cache/histórico usados pela `ResearchViewModel` são os
  mesmos já cobertos no núcleo; a tela tem a verificação manual descrita no
  `App/README.md`.

## Limitações desta fase
- Sem login, sem download de publicações, sem espelho local do site: só
  páginas públicas oficiais e ligações.
- Mudanças no HTML do WOL podem reduzir resultados; nesse caso o app mostra a
  ligação oficial (comportamento coberto por teste de fallback).
- O atalho do app oficial depende do app JW Library estar instalado; a ligação
  da web é sempre oferecida.

## Como verificar
```bash
swift test --filter ResearchTests
```
