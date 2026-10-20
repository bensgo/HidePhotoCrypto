// Copyright (c) 2026 YueGe
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// 仅限非商业使用；商业使用须获得版权所有者书面授权。详见 LICENSE。
import CryptoKit
import Foundation

/// 通用分块文件处理；使用本包独立的 HPC1 格式，不读取或修改现有 App 文件。
public enum FileEncryption {
    public static let defaultChunkSize = 1_048_576
    private static let headerSize = 48
    private static let magic = Data("HPC1".utf8)
    private static let keyContext = Data("HidePhotoCrypto/HPC1/file-key".utf8)

    public static func encrypt(from source: URL, to destination: URL, using key: EncryptionKey,
                               chunkSize: Int = defaultChunkSize) throws {
        guard (1...16_777_216).contains(chunkSize) else { throw EncryptionError.invalidChunkSize }
        try output(from: source, to: destination) { input, result in
            let length = try input.seekToEnd()
            try input.seek(toOffset: 0)
            let salt = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            var header = magic
            header.append(salt)
            header.append(encode(UInt32(chunkSize)))
            header.append(encode(length))
            try result.write(contentsOf: header)
            let fileKey = derive(key, salt: salt)
            for index in 0..<chunkCount(length, chunkSize) {
                try Task.checkCancellation()
                try autoreleasepool {
                    let wanted = Int(min(UInt64(chunkSize), length - min(length, index * UInt64(chunkSize))))
                    let data = try read(input, count: wanted)
                    guard data.count == wanted else { throw EncryptionError.sourceChanged }
                    let box = try AES.GCM.seal(data, using: fileKey, nonce: nonce(index),
                                               authenticating: header + encode(index))
                    guard let combined = box.combined else { throw EncryptionError.authenticationFailed }
                    try result.write(contentsOf: combined)
                }
            }
            guard try read(input, count: 1).isEmpty else { throw EncryptionError.sourceChanged }
        }
    }

    public static func decrypt(from source: URL, to destination: URL, using key: EncryptionKey) throws {
        try output(from: source, to: destination) { input, result in
            let header = try read(input, count: headerSize)
            guard header.count == headerSize, header.prefix(4) == magic else { throw EncryptionError.invalidFileFormat }
            let chunkSize = Int(decode(header[36..<40]))
            guard (1...16_777_216).contains(chunkSize) else { throw EncryptionError.invalidFileFormat }
            let length = decode(header[40..<48])
            let count = chunkCount(length, chunkSize)
            let (overhead, overflow1) = count.multipliedReportingOverflow(by: 28)
            let (bodySize, overflow2) = length.addingReportingOverflow(overhead)
            let (fileSize, overflow3) = bodySize.addingReportingOverflow(UInt64(headerSize))
            guard !overflow1, !overflow2, !overflow3, try input.seekToEnd() == fileSize else {
                throw EncryptionError.invalidFileFormat
            }
            try input.seek(toOffset: UInt64(headerSize))
            let fileKey = derive(key, salt: Data(header[4..<36]))
            for index in 0..<count {
                try Task.checkCancellation()
                try autoreleasepool {
                    let wanted = Int(min(UInt64(chunkSize), length - min(length, index * UInt64(chunkSize)))) + 28
                    let combined = try read(input, count: wanted)
                    guard combined.count == wanted else { throw EncryptionError.invalidFileFormat }
                    let plaintext: Data
                    do {
                        let box = try AES.GCM.SealedBox(combined: combined)
                        guard Data(box.nonce) == (try Data(nonce(index))) else { throw EncryptionError.authenticationFailed }
                        plaintext = try AES.GCM.open(box, using: fileKey, authenticating: header + encode(index))
                    } catch {
                        throw EncryptionError.authenticationFailed
                    }
                    try result.write(contentsOf: plaintext)
                }
            }
            guard try read(input, count: 1).isEmpty else { throw EncryptionError.invalidFileFormat }
        }
    }

    private static func derive(_ key: EncryptionKey, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: key.value, salt: salt, info: keyContext, outputByteCount: 32)
    }

    private static func chunkCount(_ length: UInt64, _ size: Int) -> UInt64 {
        max(1, length / UInt64(size) + (length % UInt64(size) == 0 ? 0 : 1))
    }

    private static func nonce(_ index: UInt64) throws -> AES.GCM.Nonce {
        try AES.GCM.Nonce(data: Data(repeating: 0, count: 4) + encode(index))
    }

    private static func encode<T: FixedWidthInteger>(_ number: T) -> Data {
        withUnsafeBytes(of: number.bigEndian) { Data($0) }
    }

    private static func decode(_ bytes: Data.SubSequence) -> UInt64 {
        bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    private static func read(_ handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            let part = try handle.read(upToCount: count - data.count) ?? Data()
            if part.isEmpty { break }
            data.append(part)
        }
        return data
    }

    /// 仅发布完成的文件；正常失败时清理临时目录，绝不覆盖已有目标或删除源文件。
    private static func output(from source: URL, to destination: URL,
                               operation: (FileHandle, FileHandle) throws -> Void) throws {
        guard source.isFileURL, destination.isFileURL else { throw EncryptionError.localFileRequired }
        let manager = FileManager.default
        guard !manager.fileExists(atPath: destination.path) else { throw EncryptionError.destinationExists }
        let directory = destination.deletingLastPathComponent().appendingPathComponent(".hpc-\(UUID().uuidString)")
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: attributes)
        defer { try? manager.removeItem(at: directory) }
        let temporary = directory.appendingPathComponent("output")
        var fileAttributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        fileAttributes[.protectionKey] = FileProtectionType.complete
        #endif
        guard manager.createFile(atPath: temporary.path, contents: nil, attributes: fileAttributes) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let result = try FileHandle(forWritingTo: temporary)
        defer { try? result.close() }
        try operation(input, result)
        try result.synchronize()
        try result.close()
        try manager.moveItem(at: temporary, to: destination)
    }
}
