#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gerador das fixtures de teste do DiscursoCore.

Todos os arquivos gerados são de autoria do próprio projeto (conteúdo
sintético). Nenhum material de terceiros é copiado ou redistribuído.

Uso:
    python3 Scripts/make_fixtures.py Tests/DiscursoCoreTests/Fixtures

Gera:
    epubs/epub3-nav.epub        EPUB 3 com documento de navegação (deflate)
    epubs/epub2-ncx.epub        EPUB 2 com toc.ncx (entradas armazenadas)
    epubs/sem-nav.epub          EPUB sem sumário (sumário gerado pelos títulos)
    epubs/com-drn.epub          EPUB com META-INF/encryption.xml
    epubs/sem-container.epub    ZIP sem META-INF/container.xml
    epubs/corrompido.epub       bytes aleatórios
    inflate/cases.json          fluxos DEFLATE gerados pelo zlib (todos os modos)
    wol/resultados-pesquisa.html  página de resultados com marcação equivalente
    wol/sem-resultados.html       página sem resultados
    wol/bloqueado.html            página com desafio (CAPTCHA) — deve ser recusada
    library/exemplo.txt         texto simples
    library/exemplo.md          Markdown
    library/documento.pdf       PDF mínimo válido (uma página)
    library/protegido.pdf       PDF com trailer /Encrypt (proteção declarada)
"""

import base64
import json
import os
import random
import struct
import sys
import zipfile
import zlib

MIMETYPE = "application/epub+zip"

CONTAINER_XML = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

CHAPTER_1 = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="pt-BR">
<head><title>Como preparar um discurso</title>
<link rel="stylesheet" type="text/css" href="estilo.css"/></head>
<body>
<h1>Como preparar um discurso</h1>
<p>Preparar um discurso começa por entender bem o assunto que será apresentado à assistência.</p>
<p>Anote as ideias principais em tópicos curtos, para que a leitura durante a apresentação seja rápida.</p>
<h2>Escolha das referências</h2>
<p>Uma referência como João 3:16 ajuda a explicar o amor de Deus. Outra leitura citada é (Salmo 83:18).</p>
<p>Compare também 1 Coríntios 13:4-7 e Romanos 12:1, 2 ao tratar do comportamento cristão.</p>
<h2>Ensaio</h2>
<p>Ensaiar em voz alta permite ajustar o tom e o ritmo da fala.</p>
<p>&nbsp;</p>
</body>
</html>
"""

CHAPTER_2 = """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="pt-BR">
<head><title>Material de apoio</title></head>
<body>
<h1>Material de apoio</h1>
<p>Este trecho menciona Mateus 24:14 e também Gênesis 1:1-3 para testes de reconhecimento.</p>
<p>Curiosidade: a palavra <script>alert('x')</script>está dentro de uma tag que deve ser ignorada.</p>
<ul>
  <li>Primeiro item de lista</li>
  <li>Segundo item, com &amp; entidade</li>
</ul>
<blockquote>Trecho destacado para teste de citação.</blockquote>
</body>
</html>
"""

NAV_XHTML = """<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="pt-BR">
<head><title>Sumário</title></head>
<body>
<nav epub:type="toc" id="toc">
  <h1>Sumário</h1>
  <ol>
    <li><a href="capitulo1.xhtml">Como preparar um discurso</a>
      <ol>
        <li><a href="capitulo1.xhtml#referencias">Escolha das referências</a></li>
        <li><a href="capitulo1.xhtml#ensaio">Ensaio</a></li>
      </ol>
    </li>
    <li><a href="capitulo2.xhtml">Material de apoio</a></li>
  </ol>
</nav>
</body>
</html>
"""

OPF_EPUB3 = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" xml:lang="pt-BR">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">urn:uuid:11111111-2222-3333-4444-555555555555</dc:identifier>
    <dc:title>Como preparar um discurso</dc:title>
    <dc:creator>Equipe Discurso Bíblico</dc:creator>
    <dc:language>pt-BR</dc:language>
    <dc:publisher>Projeto Discurso Bíblico</dc:publisher>
    <dc:date>2026-01-01</dc:date>
    <dc:description>Material de exemplo criado para testes automatizados.</dc:description>
    <dc:rights>Conteúdo de exemplo do próprio projeto.</dc:rights>
    <meta property="dcterms:modified">2026-01-01T00:00:00Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="capa" href="capa.jpg" media-type="image/jpeg" properties="cover-image"/>
    <item id="css" href="estilo.css" media-type="text/css"/>
    <item id="cap1" href="capitulo1.xhtml" media-type="application/xhtml+xml"/>
    <item id="cap2" href="capitulo2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="cap1"/>
    <itemref idref="cap2"/>
  </spine>
</package>
"""

NCX = """<?xml version="1.0" encoding="utf-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head><meta name="dtb:uid" content="urn:uuid:66666666-7777-8888-9999-000000000000"/></head>
  <docTitle><text>Manual de estudo</text></docTitle>
  <navMap>
    <navPoint id="np1" playOrder="1">
      <navLabel><text>Introdução</text></navLabel>
      <content src="capitulo1.xhtml"/>
      <navPoint id="np1a" playOrder="2">
        <navLabel><text>Detalhe do primeiro capítulo</text></navLabel>
        <content src="capitulo1.xhtml#referencias"/>
      </navPoint>
    </navPoint>
    <navPoint id="np2" playOrder="3">
      <navLabel><text>Material de apoio</text></navLabel>
      <content src="capitulo2.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
"""

OPF_EPUB2 = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Manual de estudo (EPUB 2)</dc:title>
    <dc:creator>Equipe Discurso Bíblico</dc:creator>
    <dc:language>pt-BR</dc:language>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="cap1" href="capitulo1.xhtml" media-type="application/xhtml+xml"/>
    <item id="cap2" href="capitulo2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="cap1"/>
    <itemref idref="cap2-linear-no" linear="no"/>
    <itemref idref="cap2"/>
  </spine>
  <guide><reference type="text" title="Início" href="capitulo1.xhtml"/></guide>
</package>
"""

OPF_SEM_NAV = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">sem-nav-1</dc:identifier>
    <dc:title>Sem sumário</dc:title>
    <dc:language>pt-BR</dc:language>
  </metadata>
  <manifest>
    <item id="cap1" href="capitulo1.xhtml" media-type="application/xhtml+xml"/>
    <item id="cap2" href="capitulo2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="cap1"/>
    <itemref idref="cap2"/>
  </spine>
</package>
"""

ENCRYPTION_XML = """<?xml version="1.0" encoding="UTF-8"?>
<encryption xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <enc:EncryptedData xmlns:enc="http://www.w3.org/2001/04/xmlenc#">
    <enc:EncryptionMethod Algorithm="http://www.w3.org/2001/04/xmlenc#aes128-cbc"/>
    <enc:CipherData><enc:CipherReference URI="OEBPS/capitulo1.xhtml"/></enc:CipherData>
    <enc:EncryptedKey><enc:CipherData/></enc:EncryptedKey>
  </enc:EncryptedData>
</encryption>
"""

ESTILO_CSS = """body { font-family: serif; } h1 { color: #333; } .destaque { font-weight: bold; }"""

# JPEG mínimo (1x1 cinza) — dados de exemplo, sem conteúdo de terceiros.
CAPA_JPG = bytes.fromhex(
    "ffd8ffe000104a46494600010100000100010000ffdb004300"
    + "08" * 12 + "0b" * 12 + "0a" * 12 + "0c" * 12 + "09" * 12 + "0b" * 12 + "10" * 12
    + "ffc0000b080001000101011100ffc40014000100000000000000000000000000000009ffc40014100100000000000000000000000000000000ffda0008010100003f00d2cf20ffd9"
)


def write_zip(path: str, entries, mimetype_store: bool = True):
    """Escreve um ZIP; `mimetype` é sempre o primeiro e sem compressão (regra EPUB)."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        if mimetype_store:
            archive.writestr(
                zipfile.ZipInfo("mimetype", date_time=(2026, 1, 1, 0, 0, 0)),
                MIMETYPE,
                compress_type=zipfile.ZIP_STORED,
            )
        for name, content in entries:
            archive.writestr(name, content)


def build_epubs(directory: str):
    base = [
        ("META-INF/container.xml", CONTAINER_XML),
        ("OEBPS/content.opf", OPF_EPUB3),
        ("OEBPS/nav.xhtml", NAV_XHTML),
        ("OEBPS/capitulo1.xhtml", CHAPTER_1),
        ("OEBPS/capitulo2.xhtml", CHAPTER_2),
        ("OEBPS/estilo.css", ESTILO_CSS),
        ("OEBPS/capa.jpg", CAPA_JPG),
    ]
    write_zip(os.path.join(directory, "epub3-nav.epub"), base)

    epub2 = [
        ("META-INF/container.xml", CONTAINER_XML),
        ("OEBPS/content.opf", OPF_EPUB2),
        ("OEBPS/toc.ncx", NCX),
        ("OEBPS/capitulo1.xhtml", CHAPTER_1),
        ("OEBPS/capitulo2.xhtml", CHAPTER_2),
    ]
    # EPUB 2 com entradas armazenadas (sem compressão) para exercitar o método 0.
    os.makedirs(directory, exist_ok=True)
    with zipfile.ZipFile(os.path.join(directory, "epub2-ncx.epub"), "w", zipfile.ZIP_STORED) as archive:
        archive.writestr(zipfile.ZipInfo("mimetype", date_time=(2026, 1, 1, 0, 0, 0)), MIMETYPE)
        for name, content in epub2:
            archive.writestr(name, content)

    write_zip(
        os.path.join(directory, "sem-nav.epub"),
        [
            ("META-INF/container.xml", CONTAINER_XML),
            ("OEBPS/content.opf", OPF_SEM_NAV),
            ("OEBPS/capitulo1.xhtml", CHAPTER_1),
            ("OEBPS/capitulo2.xhtml", CHAPTER_2),
        ],
    )

    write_zip(
        os.path.join(directory, "com-drn.epub"),
        base + [("META-INF/encryption.xml", ENCRYPTION_XML)],
    )

    write_zip(
        os.path.join(directory, "sem-container.epub"),
        [("OEBPS/content.opf", OPF_EPUB3), ("OEBPS/capitulo1.xhtml", CHAPTER_1)],
    )

    os.makedirs(directory, exist_ok=True)
    with open(os.path.join(directory, "corrompido.epub"), "wb") as handle:
        handle.write(b"PK\x03\x04" + bytes(random.Random(7).getrandbits(8) for _ in range(512)))


def build_inflate_cases(path: str):
    cases = []

    def add(name, payload, level=6, strategy=zlib.Z_DEFAULT_STRATEGY, wbits=-15):
        compressor = zlib.compressobj(level, zlib.DEFLATED, wbits, 9, strategy)
        stream = compressor.compress(payload) + compressor.flush()
        cases.append({
            "name": name,
            "compressed": base64.b64encode(stream).decode("ascii"),
            "expected": base64.b64encode(payload).decode("ascii"),
            "expectedSize": len(payload),
        })

    texto = (
        "Preparar um discurso exige organização. João 3:16 e Salmo 83:18 aparecem aqui "
        "para que o texto tenha conteúdo em português, com acentos e pontuação. "
    ) * 40

    add("vazio", b"", level=0)
    add("um-byte", b"A", level=0)
    add("armazenado", texto.encode("utf-8"), level=0)
    add("huffman-fixo", texto.encode("utf-8"), level=1, strategy=zlib.Z_FIXED)
    add("huffman-dinamico", texto.encode("utf-8"), level=9)
    add("huffman-only", texto.encode("utf-8"), level=9, strategy=zlib.Z_HUFFMAN_ONLY)
    add("rle", texto.encode("utf-8"), level=6, strategy=zlib.Z_RLE)
    add("multibloco", (texto * 20).encode("utf-8"), level=6)
    add("binario", bytes(random.Random(42).getrandbits(8) for _ in range(20000)), level=6)
    add("acentos", "áàâãéêíóôõúç ÁÀÂÃÉÊÍÓÔÕÚÇ".encode("utf-8") * 60, level=6)
    add("linhas-longas", ("linha sem quebras " * 400).encode("utf-8"), level=6)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(cases, handle, ensure_ascii=False, indent=2)


def result_block(title, ref, href, subitems=()):
    sub = "".join(
        f'<li><a href="{item_href}">{item_title}</a></li>' for item_title, item_href in subitems
    )
    return f"""
    <ul class="directory resultContentTopic">
      <li class="caption">
        <span class="iconTopic"><span class="icon"></span></span>
        <a class="lnk" href="{href}" data-nav-scope-data="[]">{title}</a>
      </li>
      <li class="result">
        <ul class="resultItems"><li class="ref">{ref}</li></ul>
      </li>
      <li class="resultSubheadings"><ul class="resultItems">{sub}</ul></li>
    </ul>
    """


def build_wol_fixtures(directory: str):
    os.makedirs(directory, exist_ok=True)

    results = "".join([
        result_block("Oração", "Estudo Perspicaz das Escrituras, Volume 2",
                     "/pt/wol/d/r5/lp-t/1200003543"),
        result_block("Oração-modelo", "Índice das Publicações — 1991-2026",
                     "/pt/wol/d/r5/lp-t/1200273879",
                     (("Lista por frase", "/pt/wol/d/r5/lp-t/1200273879#p14"),)),
        result_block("Seja constante na oração", "A Sentinela (edição de estudo), janeiro de 2026",
                     "/pt/wol/d/r5/lp-t/1975486"),
    ])
    page = f"""<!DOCTYPE html>
<html dir="ltr" lang="pt">
<head><title>Pesquisa &mdash; BIBLIOTECA ON-LINE da Torre de Vigia</title></head>
<body>
<form id="searchForm"><input name="q" value="oração"/>
  <span>Resultados: 3</span>
</form>
<div class="resultsContainer"><div class="section"><div class="results">{results}</div></div></div>
</body></html>
"""
    with open(os.path.join(directory, "resultados-pesquisa.html"), "w", encoding="utf-8") as handle:
        handle.write(page)

    empty = """<!DOCTYPE html>
<html dir="ltr" lang="pt"><head><title>Pesquisa</title></head><body>
<div class="resultsContainer"><div class="section"><div class="results"></div></div></div>
<p>Nenhum resultado encontrado.</p></body></html>
"""
    with open(os.path.join(directory, "sem-resultados.html"), "w", encoding="utf-8") as handle:
        handle.write(empty)

    blocked = """<!DOCTYPE html>
<html dir="ltr" lang="pt"><head><title>Verificação</title></head><body>
<h1>Confirme que você é humano</h1>
<form action="/captcha"><div class="g-recaptcha" data-sitekey="exemplo"></div></form>
</body></html>
"""
    with open(os.path.join(directory, "bloqueado.html"), "w", encoding="utf-8") as handle:
        handle.write(blocked)


def build_library_files(directory: str):
    os.makedirs(directory, exist_ok=True)

    texto = (
        "ESBOÇO DE ESTUDO\n\n"
        "1. Introdução\n"
        "A oração é uma provisão amorosa. Veja Filipenses 4:6, 7.\n\n"
        "2. Desenvolvimento\n"
        "Use tópicos curtos e uma referência por ideia principal.\n"
        "João 3:16 e Mateus 24:14 servem de exemplo.\n\n"
        "3. Conclusão\n"
        "Resuma o que foi apresentado em uma frase.\n"
    )
    with open(os.path.join(directory, "exemplo.txt"), "w", encoding="utf-8") as handle:
        handle.write(texto)

    markdown = (
        "# Material em Markdown\n\n"
        "## Seção 1\n"
        "Texto de exemplo com **ênfase** e uma referência: Salmo 83:18.\n\n"
        "- Item um\n"
        "- Item dois\n\n"
        "## Seção 2\n"
        "Mais texto para indexação local.\n"
    )
    with open(os.path.join(directory, "exemplo.md"), "w", encoding="utf-8") as handle:
        handle.write(markdown)

    # PDF mínimo de uma página, escrito à mão (conteúdo próprio).
    content = b"BT /F1 18 Tf 72 720 Td (PDF de exemplo do projeto) Tj ET"
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
        b"<< /Length " + str(len(content)).encode() + b" >>\nstream\n" + content + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    pdf = b"%PDF-1.4\n"
    offsets = []
    for index, body in enumerate(objects, start=1):
        offsets.append(len(pdf))
        pdf += f"{index} 0 obj\n".encode() + body + b"\nendobj\n"
    xref_offset = len(pdf)
    pdf += f"xref\n0 {len(objects) + 1}\n".encode()
    pdf += b"0000000000 65535 f \n"
    for offset in offsets:
        pdf += f"{offset:010d} 00000 n \n".encode()
    pdf += (
        f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref_offset}\n%%EOF\n"
    ).encode()
    with open(os.path.join(directory, "documento.pdf"), "wb") as handle:
        handle.write(pdf)

    # PDF com proteção declarada (mesma estrutura + /Encrypt no trailer).
    protegido = pdf.replace(
        b"trailer\n<< /Size",
        b"trailer\n<< /Encrypt 9 0 R /Size",
    )
    with open(os.path.join(directory, "protegido.pdf"), "wb") as handle:
        handle.write(protegido)

    with open(os.path.join(directory, "sem-extensao"), "wb") as handle:
        handle.write(b"conteudo sem extensao reconhecivel\n")


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "Tests/DiscursoCoreTests/Fixtures"
    build_epubs(os.path.join(root, "epubs"))
    build_inflate_cases(os.path.join(root, "inflate", "cases.json"))
    build_wol_fixtures(os.path.join(root, "wol"))
    build_library_files(os.path.join(root, "library"))
    print(f"Fixtures geradas em {os.path.abspath(root)}")


if __name__ == "__main__":
    main()
