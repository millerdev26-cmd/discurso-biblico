// swift-tools-version: 6.0
//
// Manifesto SwiftPM do APLICATIVO, usado apenas para compilar e instalar o
// app no aparelho pelo xtool (sem precisar de um Mac). Ver `xtool.yml` e a
// seção 3 do App/README.md.
//
// O projeto Xcode continua sendo gerado pelo XcodeGen a partir de
// `project.yml` — é ele que o CI usa para compilar e rodar os testes. Este
// manifesto reutiliza exatamente as mesmas fontes (`DiscursoBiblico/`), sem
// duplicar código.
//
// Uso (exige xtool configurado — login na conta Apple e SDK extraído de
// `Xcode.xip` — e uma toolchain Swift com suporte a Swift SDKs):
//
//     cd App
//     xtool dev build --ipa      # gera o .ipa assinado
//     xtool dev                  # compila, instala e abre no aparelho
//
// Confira o manifesto sem compilar:
//
//     cd App && swift package describe

import PackageDescription

let package = Package(
    name: "DiscursoBiblico",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        // Um projeto xtool deve ter exatamente um produto de biblioteca:
        // é ele que vira o aplicativo.
        .library(
            name: "DiscursoBiblico",
            targets: ["DiscursoBiblico"]
        )
    ],
    dependencies: [
        // Mesmo pacote usado pelo projeto Xcode (o nome da pasta do
        // repositório não é "DiscursoCore", por isso a identidade explícita).
        .package(name: "DiscursoCore", path: "..")
    ],
    targets: [
        .target(
            name: "DiscursoBiblico",
            dependencies: [
                .product(name: "DiscursoCore", package: "DiscursoCore")
            ],
            path: "DiscursoBiblico",
            // O Info.plist do alvo Xcode é substituído por `Info-xtool.plist`
            // (xtool gera o restante e faz a mesclagem das chaves).
            exclude: ["Info.plist"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
