//
//  ZipArchive.swift
//  DiscursoCore
//
//  Leitor de arquivos ZIP (necessário para EPUB, que é um ZIP).
//
//  Características:
//   - lê o diretório central (fonte confiável dos metadados), não o cabeçalho local;
//   - suporta os métodos "armazenado" (0) e "deflate" (8), que são os únicos
//     usados em EPUBs legítimos;
//   - entende os campos ZIP64 (arquivos grandes);
//   - recusa entradas criptografadas em vez de tentar contornar a proteção;
//   - valida o CRC-32 das entradas extraídas.
//

import Foundation

/// Erros de leitura de ZIP.
public enum ZipArchiveError: LocalizedError, Equatable {
    case invalidArchive
    case endOfCentralDirectoryNotFound
    case entryNotFound(String)
    case encryptedEntry(String)
    case unsupportedCompression(UInt16, entry: String)
    case corruptedEntry(String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive:
            return "O arquivo não é um pacote ZIP válido."
        case .endOfCentralDirectoryNotFound:
            return "O índice do arquivo ZIP não foi encontrado (arquivo incompleto ou danificado)."
        case .entryNotFound(let name):
            return "O item \(name) não existe dentro do pacote."
        case .encryptedEntry(let name):
            return "O item \(name) está protegido por criptografia. O aplicativo não remove proteções."
        case .unsupportedCompression(let method, let entry):
            return "O item \(entry) usa um método de compressão não suportado (\(method))."
        case .corruptedEntry(let entry, let reason):
            return "O item \(entry) está corrompido: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .encryptedEntry:
            return "Use o aplicativo ou o serviço oficial indicado pelo fornecedor do conteúdo."
        case .corruptedEntry, .invalidArchive, .endOfCentralDirectoryNotFound:
            return "Tente importar novamente o arquivo original."
        default:
            return nil
        }
    }
}

/// Metadados de uma entrada do ZIP.
public struct ZipEntry: Hashable, Sendable {
    public var name: String
    public var compressionMethod: UInt16
    public var crc32: UInt32
    public var compressedSize: Int
    public var uncompressedSize: Int
    /// Deslocamento do cabeçalho local dentro do arquivo.
    public var localHeaderOffset: Int
    /// `true` para diretórios.
    public var isDirectory: Bool
    /// `true` para entradas criptografadas.
    public var isEncrypted: Bool

    public init(
        name: String,
        compressionMethod: UInt16,
        crc32: UInt32,
        compressedSize: Int,
        uncompressedSize: Int,
        localHeaderOffset: Int,
        isDirectory: Bool,
        isEncrypted: Bool
    ) {
        self.name = name
        self.compressionMethod = compressionMethod
        self.crc32 = crc32
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.localHeaderOffset = localHeaderOffset
        self.isDirectory = isDirectory
        self.isEncrypted = isEncrypted
    }
}

/// Leitor de arquivos ZIP baseado no diretório central.
public struct ZipArchive {

    private let data: Data
    public let entries: [ZipEntry]
    private let indicesByName: [String: Int]
    /// Quantidade de avisos não fatais (entradas ignoradas etc.).
    public private(set) var warnings: [String] = []

    // Assinaturas.
    private static let endOfCentralDirectorySignature: UInt32 = 0x06054b50
    private static let zip64LocatorSignature: UInt32 = 0x07064b50
    private static let zip64EndOfCentralDirectorySignature: UInt32 = 0x06064b50
    private static let centralDirectorySignature: UInt32 = 0x02014b50
    private static let localHeaderSignature: UInt32 = 0x04034b50

    /// Abre um arquivo ZIP em memória.
    public init(data: Data) throws {
        self.data = data
        var entries: [ZipEntry] = []
        var warnings: [String] = []

        let reader = ByteReader(data: data)
        let centralDirectory = try Self.locateCentralDirectory(reader: reader)
        var offset = centralDirectory.offset

        for _ in 0..<centralDirectory.count {
            guard reader.hasBytes(at: offset, count: 46),
                  reader.uint32(at: offset) == Self.centralDirectorySignature
            else { break }

            let flags = reader.uint16(at: offset + 8)
            let method = reader.uint16(at: offset + 10)
            let crc = reader.uint32(at: offset + 16)
            var compressedSize = Int(reader.uint32(at: offset + 20))
            var uncompressedSize = Int(reader.uint32(at: offset + 24))
            let nameLength = Int(reader.uint16(at: offset + 28))
            let extraLength = Int(reader.uint16(at: offset + 30))
            let commentLength = Int(reader.uint16(at: offset + 32))
            var localHeaderOffset = Int(reader.uint32(at: offset + 42))

            guard let name = reader.string(at: offset + 46, length: nameLength, encoding: .utf8)
                ?? reader.string(at: offset + 46, length: nameLength, encoding: .isoLatin1)
            else {
                warnings.append("Uma entrada sem nome legível foi ignorada.")
                break
            }

            // Campos ZIP64, quando os valores de 32 bits estão saturados.
            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF || localHeaderOffset == 0xFFFF_FFFF {
                let extraOffset = offset + 46 + nameLength
                if let zip64 = Self.parseZip64Extra(
                    reader: reader,
                    offset: extraOffset,
                    length: extraLength,
                    needsUncompressed: uncompressedSize == 0xFFFF_FFFF,
                    needsCompressed: compressedSize == 0xFFFF_FFFF,
                    needsOffset: localHeaderOffset == 0xFFFF_FFFF
                ) {
                    if let value = zip64.uncompressedSize { uncompressedSize = value }
                    if let value = zip64.compressedSize { compressedSize = value }
                    if let value = zip64.localHeaderOffset { localHeaderOffset = value }
                }
            }

            let entry = ZipEntry(
                name: name,
                compressionMethod: method,
                crc32: crc,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset,
                isDirectory: name.hasSuffix("/"),
                isEncrypted: (flags & 0x0001) != 0
            )
            entries.append(entry)

            offset += 46 + nameLength + extraLength + commentLength
        }

        guard !entries.isEmpty else { throw ZipArchiveError.invalidArchive }

        var indices: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            indices[entry.name] = index
        }
        self.entries = entries
        self.indicesByName = indices
        self.warnings = warnings
    }

    /// Abre um arquivo ZIP do disco (com mapeamento em memória quando possível).
    public init(contentsOf url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw ZipArchiveError.invalidArchive
        }
        try self.init(data: data)
    }

    // MARK: - Consultas

    public func contains(_ name: String) -> Bool {
        indicesByName[name] != nil
    }

    public func entry(named name: String) -> ZipEntry? {
        indicesByName[name].map { entries[$0] }
    }

    /// Primeira entrada cujo nome termina com o sufixo informado.
    public func firstEntry(withSuffix suffix: String) -> ZipEntry? {
        entries.first { $0.name.hasSuffix(suffix) }
    }

    /// Lista entradas que satisfazem um teste.
    public func entries(where predicate: (ZipEntry) -> Bool) -> [ZipEntry] {
        entries.filter(predicate)
    }

    // MARK: - Extração

    /// Extrai e descompacta uma entrada.
    public func data(for entry: ZipEntry, verifyChecksum: Bool = true) throws -> Data {
        if entry.isEncrypted { throw ZipArchiveError.encryptedEntry(entry.name) }
        if entry.isDirectory { return Data() }

        let reader = ByteReader(data: data)
        let headerOffset = entry.localHeaderOffset
        guard reader.hasBytes(at: headerOffset, count: 30),
              reader.uint32(at: headerOffset) == Self.localHeaderSignature
        else {
            throw ZipArchiveError.corruptedEntry(entry.name, reason: "cabeçalho local inválido")
        }
        let nameLength = Int(reader.uint16(at: headerOffset + 26))
        let extraLength = Int(reader.uint16(at: headerOffset + 28))
        let dataOffset = headerOffset + 30 + nameLength + extraLength
        guard reader.hasBytes(at: dataOffset, count: entry.compressedSize) else {
            throw ZipArchiveError.corruptedEntry(entry.name, reason: "dados incompletos")
        }

        let compressed = data.subdata(in: dataOffset..<(dataOffset + entry.compressedSize))
        let output: Data
        switch entry.compressionMethod {
        case 0:
            output = compressed
        case 8:
            do {
                output = try Inflate.decompress(compressed, initialCapacity: entry.uncompressedSize)
            } catch {
                throw ZipArchiveError.corruptedEntry(
                    entry.name,
                    reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                )
            }
        default:
            throw ZipArchiveError.unsupportedCompression(entry.compressionMethod, entry: entry.name)
        }

        if verifyChecksum, entry.crc32 != 0 {
            let checksum = CRC32.checksum(output)
            guard checksum == entry.crc32 else {
                throw ZipArchiveError.corruptedEntry(entry.name, reason: "CRC-32 não confere")
            }
        }
        return output
    }

    /// Extrai uma entrada pelo nome.
    public func data(forName name: String, verifyChecksum: Bool = true) throws -> Data? {
        guard let entry = entry(named: name) else { return nil }
        return try data(for: entry, verifyChecksum: verifyChecksum)
    }

    /// Extrai e decodifica como texto.
    public func string(
        for entry: ZipEntry,
        encoding: String.Encoding = .utf8,
        verifyChecksum: Bool = true
    ) throws -> String? {
        let bytes = try data(for: entry, verifyChecksum: verifyChecksum)
        if let text = String(data: bytes, encoding: encoding) { return text }
        return String(data: bytes, encoding: .isoLatin1)
    }

    /// Extrai e decodifica uma entrada pelo nome.
    public func string(
        forName name: String,
        encoding: String.Encoding = .utf8,
        verifyChecksum: Bool = true
    ) throws -> String? {
        guard let entry = entry(named: name) else { return nil }
        return try string(for: entry, encoding: encoding, verifyChecksum: verifyChecksum)
    }

    // MARK: - Diretório central

    private struct CentralDirectoryLocation {
        var offset: Int
        var count: Int
    }

    private static func locateCentralDirectory(reader: ByteReader) throws -> CentralDirectoryLocation {
        // O comentário do ZIP tem no máximo 65535 bytes, portanto o EOCD está
        // nos últimos 65557 bytes.
        let searchLimit = min(reader.count, 65_557 + 22)
        var endOffset: Int?
        var candidate = reader.count - 22
        let lowerBound = max(0, reader.count - searchLimit)
        while candidate >= lowerBound {
            if reader.uint32(at: candidate) == endOfCentralDirectorySignature {
                let commentLength = Int(reader.uint16(at: candidate + 20))
                if candidate + 22 + commentLength == reader.count {
                    endOffset = candidate
                    break
                }
                if endOffset == nil { endOffset = candidate }
            }
            candidate -= 1
        }
        guard let eocd = endOffset else { throw ZipArchiveError.endOfCentralDirectoryNotFound }

        var entriesCount = Int(reader.uint16(at: eocd + 10))
        var directoryOffset = Int(reader.uint32(at: eocd + 16))

        // ZIP64: localizador logo antes do EOCD.
        if entriesCount == 0xFFFF || directoryOffset == 0xFFFF_FFFF {
            let locatorOffset = eocd - 20
            if locatorOffset >= 0, reader.uint32(at: locatorOffset) == zip64LocatorSignature,
               let rawZip64Offset = reader.uint64(at: locatorOffset + 8) {
                let zip64Offset = Int(rawZip64Offset)
                if zip64Offset >= 0, zip64Offset + 56 <= reader.count,
                   reader.uint32(at: zip64Offset) == zip64EndOfCentralDirectorySignature {
                    if let count = reader.uint64(at: zip64Offset + 32) { entriesCount = Int(count) }
                    if let offset = reader.uint64(at: zip64Offset + 48) { directoryOffset = Int(offset) }
                }
            }
        }

        guard directoryOffset >= 0, directoryOffset < reader.count else {
            throw ZipArchiveError.invalidArchive
        }
        return CentralDirectoryLocation(offset: directoryOffset, count: entriesCount)
    }

    private struct Zip64Extra {
        var uncompressedSize: Int?
        var compressedSize: Int?
        var localHeaderOffset: Int?
    }

    private static func parseZip64Extra(
        reader: ByteReader,
        offset: Int,
        length: Int,
        needsUncompressed: Bool,
        needsCompressed: Bool,
        needsOffset: Bool
    ) -> Zip64Extra? {
        var cursor = offset
        let end = offset + length
        while cursor + 4 <= end {
            let identifier = reader.uint16(at: cursor)
            let fieldLength = Int(reader.uint16(at: cursor + 2))
            let fieldStart = cursor + 4
            if identifier == 0x0001, fieldStart + fieldLength <= end {
                var extra = Zip64Extra()
                var fieldCursor = fieldStart
                if needsUncompressed, let value = reader.uint64(at: fieldCursor) {
                    extra.uncompressedSize = Int(value)
                    fieldCursor += 8
                }
                if needsCompressed, let value = reader.uint64(at: fieldCursor) {
                    extra.compressedSize = Int(value)
                    fieldCursor += 8
                }
                if needsOffset, let value = reader.uint64(at: fieldCursor) {
                    extra.localHeaderOffset = Int(value)
                    fieldCursor += 8
                }
                return extra
            }
            cursor = fieldStart + fieldLength
        }
        return nil
    }
}

// MARK: - Leitor de bytes little-endian

/// Acesso posicional seguro a bytes little-endian.
private struct ByteReader {
    let data: Data

    var count: Int { data.count }

    func hasBytes(at offset: Int, count: Int) -> Bool {
        offset >= 0 && count >= 0 && offset + count <= data.count
    }

    func uint16(at offset: Int) -> UInt16 {
        guard hasBytes(at: offset, count: 2) else { return 0 }
        let base = data.startIndex + offset
        return UInt16(data[base]) | (UInt16(data[base + 1]) << 8)
    }

    func uint32(at offset: Int) -> UInt32 {
        guard hasBytes(at: offset, count: 4) else { return 0 }
        let base = data.startIndex + offset
        return UInt32(data[base])
            | (UInt32(data[base + 1]) << 8)
            | (UInt32(data[base + 2]) << 16)
            | (UInt32(data[base + 3]) << 24)
    }

    func uint64(at offset: Int) -> UInt64? {
        guard hasBytes(at: offset, count: 8) else { return nil }
        let base = data.startIndex + offset
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[base + index]) << (8 * UInt64(index))
        }
        return value
    }

    func string(at offset: Int, length: Int, encoding: String.Encoding) -> String? {
        guard hasBytes(at: offset, count: length) else { return nil }
        let base = data.startIndex + offset
        let slice = data.subdata(in: base..<(base + length))
        return String(data: slice, encoding: encoding)
    }
}
