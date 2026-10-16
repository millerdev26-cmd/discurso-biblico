//
//  CoreAliases.swift
//  DiscursoCoreTests
//
//  Desambigua `LibraryItem` nos testes do núcleo.
//
//  No macOS, o `XCTest` do Xcode deixa `DeveloperToolsSupport` no escopo — e
//  esse framework também declara um `LibraryItem` (usado pelas
//  pré-visualizações do Xcode). Sem um apelido do próprio módulo, o nome fica
//  ambíguo ("'LibraryItem' is ambiguous for type lookup") e o módulo de testes
//  nem é emitido. Em Linux o framework não existe, mas o apelido é inofensivo
//  e mantém os dois ambientes iguais.
//
//  Vale para os três alvos: aplicativo, testes do aplicativo e testes do
//  núcleo (o mesmo apelido aparece em `App/DiscursoBiblico/CoreAliases.swift` e
//  `App/DiscursoBiblicoTests/CoreAliases.swift`).
//

import DiscursoCore

/// Material da biblioteca (modelo do `DiscursoCore`).
typealias LibraryItem = DiscursoCore.LibraryItem
