#!/usr/bin/env bash
#
# verify_app_logic.sh
#
# Verifica, em Linux, a parte da lógica do APLICATIVO que não depende de
# SwiftUI/SwiftData/PDFKit/UIKit.
#
# O ambiente Linux não compila o alvo iOS, mas vários arquivos da camada de
# aplicativo só usam Foundation + DiscursoCore (codificação dos registros,
# ligações de referências, armazenamento de arquivos, importação, backup e o
# conteúdo de exemplo dos testes de interface). Este script monta um pacote
# SwiftPM temporário com esses arquivos e com os testes correspondentes, e roda
# `swift test` de verdade.
#
# Os arquivos de teste que dependem de estruturas da Apple estão protegidos
# por `#if canImport(...)` e compilam vazios aqui — são executados pelo Xcode
# no macOS (ver App/README.md).
#
# Uso:
#     Scripts/verify_app_logic.sh              # usa /tmp/opencode/discurso-applogic
#     WORK_DIR=/caminho Scripts/verify_app_logic.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-/tmp/opencode/discurso-applogic}"

# Toolchain Swift 6.2 usada pelo projeto (ajuste o PATH se necessário).
if [ -d "$HOME/toolchains/swift-6.2/usr/bin" ]; then
    export PATH="$HOME/toolchains/swift-6.2/usr/bin:$PATH"
fi

if ! command -v swift >/dev/null 2>&1; then
    echo "erro: 'swift' não encontrado no PATH" >&2
    exit 1
fi

echo "==> preparando $WORK_DIR"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/Sources/DiscursoBiblico" "$WORK_DIR/Tests/DiscursoBiblicoTests"

# 1. Arquivos do aplicativo que compilam fora da Apple (Foundation puro).
APP_FILES=(
    "Persistence/PayloadCoding.swift"
    "Persistence/LibraryFileStore.swift"
    "Persistence/SecurityScopedAccess.swift"
    "Services/BibleReferenceLink.swift"
    "Services/LibraryImportService.swift"
    "Services/BackupCoordinator.swift"
    "Services/DemoSeed.swift"
)

for file in "${APP_FILES[@]}"; do
    cp "$REPO_ROOT/App/DiscursoBiblico/$file" "$WORK_DIR/Sources/DiscursoBiblico/"
done

# 2. Todos os testes do app (os de plataforma compilam vazios por causa dos
#    guardas #if canImport(...)).
cp "$REPO_ROOT"/App/DiscursoBiblicoTests/*.swift "$WORK_DIR/Tests/DiscursoBiblicoTests/"

# 3. Pacote temporário reutilizando o pacote real como dependência local.
cat > "$WORK_DIR/Package.swift" <<EOF
// swift-tools-version: 6.0
//
// Pacote GERADO pelo script Scripts/verify_app_logic.sh — não editar.
// Ele existe apenas para rodar, em Linux, os testes da lógica do aplicativo
// que não depende de estruturas da Apple.

import PackageDescription

let package = Package(
    name: "DiscursoBiblicoAppLogic",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "DiscursoCore", path: "$REPO_ROOT")
    ],
    targets: [
        .target(
            name: "DiscursoBiblico",
            dependencies: [
                .product(name: "DiscursoCore", package: "DiscursoCore")
            ],
            path: "Sources/DiscursoBiblico",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "DiscursoBiblicoTests",
            dependencies: [
                "DiscursoBiblico",
                .product(name: "DiscursoCore", package: "DiscursoCore")
            ],
            path: "Tests/DiscursoBiblicoTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
EOF

echo "==> swift test (lógica do app em Linux)"
swift test --package-path "$WORK_DIR"
