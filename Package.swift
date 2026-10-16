// swift-tools-version: 6.0
//
//  Package.swift
//  DiscursoCore
//
//  Núcleo (domínio) do aplicativo "Discurso Bíblico".
//
//  Este pacote contém TODA a lógica independente de plataforma: modelos de
//  dados, persistência em disco (JSON atômico), editor (blocos/markup),
//  reconhecimento de referências bíblicas, leitura de EPUB (ZIP + DEFLATE
//  próprios, sem dependências externas), indexação/pesquisa local,
//  importação/validação de arquivos, exportação (TXT/Markdown/HTML) e
//  backup, além dos provedores de pesquisa externa isolados.
//
//  Ele compila e é testado em Linux (`swift build` / `swift test`) e é
//  consumido pelo app iOS (SwiftUI + SwiftData + PDFKit) como pacote local,
//  exatamente o mesmo código, sem duplicação.
//
//  Decisões de engenharia registradas em `docs/DECISOES.md`.
//

import PackageDescription

let package = Package(
    name: "DiscursoCore",
    defaultLocalization: "pt-BR",
    platforms: [
        // Requisitos mínimos do app. No Linux estas linhas são ignoradas,
        // permitindo rodar a suíte de testes neste ambiente.
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "DiscursoCore", targets: ["DiscursoCore"])
    ],
    dependencies: [
        // Intencionalmente vazio: nenhuma dependência de terceiros.
        // Justificativa em docs/DECISOES.md ("Dependências").
    ],
    targets: [
        .target(
            name: "DiscursoCore",
            path: "Sources/DiscursoCore",
            swiftSettings: [
                // Modo de linguagem Swift 5: o código é compatível com Swift 6,
                // mas mantemos o modo 5 para não exigir concorrência estrita em
                // todo o código de UI/domínio e preservar compatibilidade com
                // Xcode 15.4+ (Swift 5.10) além do Xcode 16/26.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "DiscursoCoreTests",
            dependencies: ["DiscursoCore"],
            path: "Tests/DiscursoCoreTests",
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
