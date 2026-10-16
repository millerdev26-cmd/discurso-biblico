//
//  SecurityScopedAccess.swift
//  DiscursoBiblico
//
//  Acesso a arquivos escolhidos pelo usuário no `fileImporter`.
//
//  No iOS/macOS o acesso exige `startAccessingSecurityScopedResource()`; fora
//  da Apple (a verificação de lógica em Linux, em
//  `Scripts/verify_app_logic.sh`) esses métodos não existem. Este auxiliar
//  centraliza a diferença para que os demais arquivos compilem nos dois
//  ambientes sem `#if` espalhados.
//

import Foundation

enum SecurityScopedAccess {

    /// Executa o bloco com acesso ao recurso com escopo de segurança.
    ///
    /// Quando o sistema não oferece o escopo (ou o arquivo não é escopado),
    /// o bloco é executado do mesmo modo: ler um caminho comum continua
    /// funcionando normalmente.
    static func withAccess<T>(to url: URL, _ body: () throws -> T) rethrows -> T {
        #if canImport(Darwin)
        let didStart = url.startAccessingSecurityScopedResource()
        defer { if didStart { url.stopAccessingSecurityScopedResource() } }
        return try body()
        #else
        return try body()
        #endif
    }
}
