//
//  CoreAliases.swift
//  DiscursoBiblicoTests
//
//  Espelho do apelido do alvo do aplicativo (`App/DiscursoBiblico/CoreAliases.swift`).
//
//  Os arquivos de teste importam `DiscursoCore` (modelos) e o aplicativo
//  (`@testable import DiscursoBiblico`); além disso, o framework
//  `DeveloperToolsSupport` — que entra no escopo pelas pré-visualizações —
//  também declara `LibraryItem`. Sem este apelido, o nome fica ambíguo nos
//  testes; um apelido do próprio módulo tem precedência sobre os importados.
//

import DiscursoCore

/// Material da biblioteca (modelo do `DiscursoCore`).
typealias LibraryItem = DiscursoCore.LibraryItem
