# Fixtures de teste

Arquivos usados pelos testes automatizados do núcleo (`DiscursoCoreTests`).

- `epubs/` — livros EPUB sintéticos (criados pelo projeto, conteúdo próprio):
  - `epub3-nav.epub` — EPUB 3 com `nav.xhtml`, entradas comprimidas (DEFLATE).
  - `epub2-ncx.epub` — EPUB 2 com `toc.ncx`, entradas sem compressão (STORE).
  - `com-drm.epub` — EPUB com `META-INF/encryption.xml` (deve ser recusado).
  - `corrompido.epub` — arquivo inválido (deve falhar com erro claro).
- `wol/` — páginas HTML **sintéticas** com a mesma estrutura de marcação das
  páginas públicas de resultado de pesquisa do WOL, usadas para testar o
  analisador (`WolSearchResultParser`) sem depender de rede nem redistribuir
  conteúdo de terceiros.
- `bible/` — amostras de texto bíblico **de domínio público** (tradução
  fictícia criada para testes) no formato aceito por `LocalBibleTextProvider`,
  ilustrando como carregar um texto autorizado pelo próprio usuário.

Regenerar as fixtures de EPUB:

```bash
python3 Scripts/make_epub_fixtures.py Tests/DiscursoCoreTests/Fixtures/epubs
```
