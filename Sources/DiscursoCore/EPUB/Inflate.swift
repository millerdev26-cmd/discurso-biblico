//
//  Inflate.swift
//  DiscursoCore
//
//  Decodificador DEFLATE (RFC 1951) e CRC-32 em Swift puro.
//
//  Por que implementar em vez de usar uma biblioteca?
//   - nenhuma dependência de terceiros para auditar/manter (requisito do projeto);
//   - funciona igualmente no iOS e nos testes deste repositório (Linux);
//   - o algoritmo é pequeno, estável e coberto por testes com fluxos gerados
//     pelo zlib em todos os modos (bloco armazenado, Huffman fixo e dinâmico).
//
//  A implementação é um port fiel do algoritmo de `puff.c` (Mark Adler,
//  licença zlib), que é uma referência de clareza e correção para DEFLATE.
//  O código foi reescrito em Swift, com tratamento de erro em vez de códigos
//  de retorno negativos.
//

import Foundation

/// Erros de descompactação.
public enum CompressionError: LocalizedError, Equatable {
    case truncatedInput
    case invalidBlockType
    case invalidStoredLength
    case invalidCodeLengths
    case incompleteCode
    case invalidLiteralLengthCode
    case invalidDistanceCode
    case distanceTooFar
    case checksumMismatch
    case unsupportedMethod(UInt16)

    public var errorDescription: String? {
        switch self {
        case .truncatedInput: return "O arquivo terminou antes do esperado (dados incompletos)."
        case .invalidBlockType: return "Bloco de compressão inválido."
        case .invalidStoredLength: return "Tamanho de bloco armazenado inválido."
        case .invalidCodeLengths: return "Tabela de códigos inválida."
        case .incompleteCode: return "Código incompleto."
        case .invalidLiteralLengthCode: return "Código de literal/comprimento inválido."
        case .invalidDistanceCode: return "Código de distância inválido."
        case .distanceTooFar: return "Distância de referência fora do conteúdo."
        case .checksumMismatch: return "A verificação de integridade (CRC) falhou."
        case .unsupportedMethod(let method): return "Método de compressão não suportado (\(method))."
        }
    }
}

public enum Inflate {

    private static let maxBits = 15
    private static let maxLiteralCodes = 286
    private static let maxDistanceCodes = 30

    /// Comprimentos base dos códigos de comprimento (RFC 1951, tabela 16).
    private static let lengthBase: [Int] = [
        3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
        35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
    ]

    /// Bits extra dos códigos de comprimento.
    private static let lengthExtra: [Int] = [
        0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
        3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
    ]

    /// Distâncias base (RFC 1951, tabela 16).
    private static let distanceBase: [Int] = [
        1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
        257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
    ]

    /// Bits extra das distâncias.
    private static let distanceExtra: [Int] = [
        0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
        7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
    ]

    /// Ordem de leitura dos comprimentos de código (RFC 1951, seção 3.2.7).
    private static let codeLengthOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// Descompacta um fluxo DEFLATE (sem cabeçalho zlib/gzip).
    ///
    /// - Parameters:
    ///   - data: dados compactados.
    ///   - initialCapacity: estimativa do tamanho descompactado (só desempenho).
    public static func decompress(_ data: Data, initialCapacity: Int = 0) throws -> Data {
        var reader = BitReader(bytes: [UInt8](data))
        var output = Data()
        output.reserveCapacity(max(initialCapacity, data.count * 3))
        try inflate(reader: &reader, output: &output)
        return output
    }

    /// Descompacta e verifica o tamanho esperado.
    public static func decompress(_ data: Data, expectingSize expected: Int) throws -> Data {
        let result = try decompress(data, initialCapacity: expected)
        if expected >= 0, result.count != expected {
            throw CompressionError.truncatedInput
        }
        return result
    }

    /// Descompacta um fluxo zlib (RFC 1950): cabeçalho de 2 bytes + DEFLATE.
    ///
    /// Aceita também fluxos sem cabeçalho (alguns geradores gravam DEFLATE puro
    /// dentro de PDFs). O "adler32" final não é verificado aqui: os formatos que
    /// usam zlib (PDF) já validam o restante do documento.
    public static func decompressZlib(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        if bytes.count > 2, (bytes[0] & 0x0F) == 8, (bytes[0] >> 4) <= 7 {
            // CMF/FLG válidos de zlib: descarta o cabeçalho.
            return try decompress(Data(bytes.dropFirst(2)))
        }
        return try decompress(data)
    }

    // MARK: - Laço principal

    private static func inflate(reader: inout BitReader, output: inout Data) throws {
        var lastBlock = false
        repeat {
            lastBlock = try reader.readBit() == 1
            let type = try reader.readBits(2)
            switch type {
            case 0:
                try readStoredBlock(reader: &reader, output: &output)
            case 1:
                let tables = fixedTables()
                try decodeBlock(reader: &reader, output: &output, lengths: tables.lengths, distances: tables.distances)
            case 2:
                let tables = try dynamicTables(reader: &reader)
                try decodeBlock(reader: &reader, output: &output, lengths: tables.lengths, distances: tables.distances)
            default:
                throw CompressionError.invalidBlockType
            }
        } while !lastBlock
    }

    private static func readStoredBlock(reader: inout BitReader, output: inout Data) throws {
        reader.alignToByte()
        let length = try reader.readBits(16)
        let complement = try reader.readBits(16)
        guard (length ^ 0xFFFF) == complement else { throw CompressionError.invalidStoredLength }
        let bytes = try reader.readBytes(count: length)
        output.append(contentsOf: bytes)
    }

    private static func decodeBlock(
        reader: inout BitReader,
        output: inout Data,
        lengths: HuffmanTable,
        distances: HuffmanTable
    ) throws {
        while true {
            let symbol = try lengths.decode(reader: &reader)
            if symbol < 256 {
                output.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                let lengthIndex = symbol - 257
                guard lengthIndex >= 0, lengthIndex < lengthBase.count else {
                    throw CompressionError.invalidLiteralLengthCode
                }
                let length = lengthBase[lengthIndex] + (try reader.readBits(lengthExtra[lengthIndex]))
                let distanceSymbol = try distances.decode(reader: &reader)
                guard distanceSymbol >= 0, distanceSymbol < distanceBase.count else {
                    throw CompressionError.invalidDistanceCode
                }
                let distance = distanceBase[distanceSymbol] + (try reader.readBits(distanceExtra[distanceSymbol]))
                guard distance > 0, distance <= output.count else { throw CompressionError.distanceTooFar }
                try copyMatch(output: &output, distance: distance, length: length)
            }
        }
    }

    /// Copia uma referência histórica (permite sobreposição, byte a byte).
    private static func copyMatch(output: inout Data, distance: Int, length: Int) throws {
        var remaining = length
        // Índice absoluto de origem dentro de `output`.
        var sourceIndex = output.count - distance
        while remaining > 0 {
            guard sourceIndex >= 0, sourceIndex < output.count else {
                throw CompressionError.distanceTooFar
            }
            let byte = output[output.startIndex + sourceIndex]
            output.append(byte)
            sourceIndex += 1
            remaining -= 1
        }
    }

    // MARK: - Tabelas

    private struct Tables {
        let lengths: HuffmanTable
        let distances: HuffmanTable
    }

    private static let fixed: Tables = {
        var lengthCodeLengths = [Int](repeating: 0, count: 288)
        for symbol in 0...143 { lengthCodeLengths[symbol] = 8 }
        for symbol in 144...255 { lengthCodeLengths[symbol] = 9 }
        for symbol in 256...279 { lengthCodeLengths[symbol] = 7 }
        for symbol in 280...287 { lengthCodeLengths[symbol] = 8 }
        let distanceCodeLengths = [Int](repeating: 5, count: 30)
        return Tables(
            lengths: HuffmanTable(codeLengths: lengthCodeLengths),
            distances: HuffmanTable(codeLengths: distanceCodeLengths)
        )
    }()

    private static func fixedTables() -> Tables { fixed }

    private static func dynamicTables(reader: inout BitReader) throws -> Tables {
        let literalCount = try reader.readBits(5) + 257
        let distanceCount = try reader.readBits(5) + 1
        let codeLengthCount = try reader.readBits(4) + 4

        guard literalCount <= 286, distanceCount <= 30, codeLengthCount <= 19 else {
            throw CompressionError.invalidCodeLengths
        }

        var codeLengthCodeLengths = [Int](repeating: 0, count: 19)
        for index in 0..<codeLengthCount {
            codeLengthCodeLengths[codeLengthOrder[index]] = try reader.readBits(3)
        }
        let codeLengthTable = HuffmanTable(codeLengths: codeLengthCodeLengths)

        var lengths = [Int](repeating: 0, count: literalCount + distanceCount)
        var index = 0
        while index < literalCount + distanceCount {
            let symbol = try codeLengthTable.decode(reader: &reader)
            switch symbol {
            case 0...15:
                lengths[index] = symbol
                index += 1
            case 16:
                guard index > 0 else { throw CompressionError.invalidCodeLengths }
                let repeatCount = 3 + (try reader.readBits(2))
                let previous = lengths[index - 1]
                for _ in 0..<repeatCount {
                    guard index < lengths.count else { throw CompressionError.invalidCodeLengths }
                    lengths[index] = previous
                    index += 1
                }
            case 17:
                let repeatCount = 3 + (try reader.readBits(3))
                for _ in 0..<repeatCount {
                    guard index < lengths.count else { throw CompressionError.invalidCodeLengths }
                    lengths[index] = 0
                    index += 1
                }
            case 18:
                let repeatCount = 11 + (try reader.readBits(7))
                for _ in 0..<repeatCount {
                    guard index < lengths.count else { throw CompressionError.invalidCodeLengths }
                    lengths[index] = 0
                    index += 1
                }
            default:
                throw CompressionError.invalidCodeLengths
            }
        }

        let literalLengths = Array(lengths[0..<literalCount])
        let distanceLengths = Array(lengths[literalCount..<(literalCount + distanceCount)])

        // Códigos de distância ausentes são permitidos (bloco sem referências).
        let lengthsTable = HuffmanTable(codeLengths: literalLengths)
        let distancesTable = distanceLengths.allSatisfy { $0 == 0 }
            ? HuffmanTable(codeLengths: [1, 1])
            : HuffmanTable(codeLengths: distanceLengths)

        guard !lengthsTable.isEmpty else { throw CompressionError.invalidCodeLengths }
        return Tables(lengths: lengthsTable, distances: distancesTable)
    }
}

// MARK: - Leitor de bits

/// Leitor de bits na ordem usada pelo DEFLATE (LSB primeiro).
private struct BitReader {
    let bytes: [UInt8]
    private(set) var bitIndex: Int = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    var isAtEnd: Bool { bitIndex >= bytes.count * 8 }

    mutating func readBit() throws -> Int {
        guard bitIndex < bytes.count * 8 else { throw CompressionError.truncatedInput }
        let byte = bytes[bitIndex >> 3]
        let bit = (byte >> UInt8(bitIndex & 7)) & 1
        bitIndex += 1
        return Int(bit)
    }

    /// Lê `count` bits (até 16) e devolve o valor.
    mutating func readBits(_ count: Int) throws -> Int {
        guard count > 0 else { return 0 }
        guard count <= 16 else { throw CompressionError.truncatedInput }
        var value = 0
        for offset in 0..<count {
            value |= (try readBit()) << offset
        }
        return value
    }

    mutating func alignToByte() {
        if bitIndex % 8 != 0 {
            bitIndex += 8 - (bitIndex % 8)
        }
    }

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0 else { return [] }
        let start = bitIndex >> 3
        let end = start + count
        guard end <= bytes.count else { throw CompressionError.truncatedInput }
        bitIndex += count * 8
        return Array(bytes[start..<end])
    }
}

// MARK: - Tabela de Huffman

/// Tabela de decodificação de Huffman canônica (como em `puff.c`).
private struct HuffmanTable {
    private let counts: [Int]
    private let symbols: [Int]

    /// `true` quando a tabela não tem nenhum símbolo.
    var isEmpty: Bool { symbols.isEmpty }

    init(codeLengths: [Int]) {
        let maxBits = 15
        var counts = [Int](repeating: 0, count: maxBits + 1)
        for length in codeLengths where length > 0 {
            counts[min(length, maxBits)] += 1
        }

        var offsets = [Int](repeating: 0, count: maxBits + 2)
        for length in 1...maxBits {
            offsets[length + 1] = offsets[length] + counts[length]
        }

        var symbols = [Int](repeating: 0, count: codeLengths.filter { $0 > 0 }.count)
        var cursor = Array(offsets)
        for (symbol, length) in codeLengths.enumerated() where length > 0 {
            let index = cursor[min(length, maxBits)]
            if index < symbols.count {
                symbols[index] = symbol
            }
            cursor[min(length, maxBits)] += 1
        }

        self.counts = counts
        self.symbols = symbols
    }

    /// Decodifica um símbolo, lendo um bit por vez.
    func decode(reader: inout BitReader) throws -> Int {
        var code = 0
        var first = 0
        var index = 0
        for length in 1...15 {
            code |= (try reader.readBit())
            let count = counts[length]
            if code - count < first {
                let symbolIndex = index + (code - first)
                guard symbolIndex >= 0, symbolIndex < symbols.count else {
                    throw CompressionError.incompleteCode
                }
                return symbols[symbolIndex]
            }
            index += count
            first += count
            first <<= 1
            code <<= 1
        }
        throw CompressionError.incompleteCode
    }
}

// MARK: - CRC-32

/// Cálculo de CRC-32 (IEEE 802.3), usado para validar entradas ZIP.
public enum CRC32 {

    private static let table: [UInt32] = {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB88320 ^ (value >> 1)) : (value >> 1)
            }
            table[index] = value
        }
        return table
    }()

    /// Calcula o CRC-32 de uma sequência de bytes.
    public static func checksum(_ bytes: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}
