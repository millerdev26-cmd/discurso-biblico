#!/usr/bin/env bash
#
# parse_check_app.sh
#
# Verificação leve do código do aplicativo em qualquer plataforma: roda
# `swiftc -frontend -parse` em cada arquivo Swift de `App/DiscursoBiblico/` e
# de `App/DiscursoBiblicoTests/`.
#
# O `-parse` faz apenas a análise sintática: não valida APIs do SwiftUI,
# SwiftData, PDFKit ou UIKit (isso exige o Xcode no macOS), mas pega erros de
# digitação/sintaxe em qualquer arquivo.
#
# Uso:
#     Scripts/parse_check_app.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -d "$HOME/toolchains/swift-6.2/usr/bin" ]; then
    export PATH="$HOME/toolchains/swift-6.2/usr/bin:$PATH"
fi

if ! command -v swiftc >/dev/null 2>&1; then
    echo "erro: 'swiftc' não encontrado no PATH" >&2
    exit 1
fi

failures=0
count=0

while IFS= read -r -d '' file; do
    count=$((count + 1))
    if ! swiftc -frontend -parse "$file" 2>/tmp/opencode/parse-check.err; then
        echo "--- falha em $file ---"
        cat /tmp/opencode/parse-check.err
        failures=$((failures + 1))
    fi
done < <(find "$REPO_ROOT/App/DiscursoBiblico" "$REPO_ROOT/App/DiscursoBiblicoTests" -name '*.swift' -print0)

if [ "$failures" -gt 0 ]; then
    echo "==> $failures de $count arquivos com erro de sintaxe"
    exit 1
fi

echo "==> $count arquivos analisados, nenhum erro de sintaxe"
