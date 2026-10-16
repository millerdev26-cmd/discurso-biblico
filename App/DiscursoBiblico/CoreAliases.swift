//
//  CoreAliases.swift
//  DiscursoBiblico
//
//  Nomes do núcleo que colidem com frameworks da Apple.
//
//  O `DeveloperToolsSupport` (framework das pré-visualizações do Xcode, que
//  entra no escopo de vários arquivos via SwiftUI) também declara
//  `LibraryItem`; sem um desambiguador, o nome fica ambíguo nos arquivos onde
//  esse framework está visível ("'LibraryItem' is ambiguous for type lookup").
//  Um apelido declarado no próprio módulo tem precedência sobre os tipos
//  importados, então `LibraryItem` passa a significar, em todo o aplicativo,
//  o modelo do `DiscursoCore`.
//

import DiscursoCore

/// Material da biblioteca (modelo do `DiscursoCore`).
typealias LibraryItem = DiscursoCore.LibraryItem
