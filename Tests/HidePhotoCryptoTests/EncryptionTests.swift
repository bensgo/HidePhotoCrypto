// Copyright (c) 2026 YueGe
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// 仅限非商业使用；商业使用须获得版权所有者书面授权。详见 LICENSE。
import CryptoKit
import Foundation
import Testing
import HidePhotoCrypto

struct EncryptionTests {
    @Test(arguments: [0, 1, 1024, 1_048_577])
    func messageRoundTrip(size: Int) throws {
        let key = EncryptionKey.generate()
        let data = Data(repeating: 0x36, count: size)
        let sealed = try Encryption.encrypt(data, using: key)
        #expect(try Encryption.decrypt(sealed, using: key) == data)
        #expect(try Encryption.encrypt(data, using: key) != sealed)
        let restoredKey = try EncryptionKey(bytes: key.exportBytes())
        #expect(try Encryption.decrypt(sealed, using: restoredKey) == data)
    }

    @Test func wrongKeyTamperingAndContextAreRejected() throws {
        let key = EncryptionKey.generate()
        let context = Data("synthetic context".utf8)
        let sealed = try Encryption.encrypt(Data("synthetic test bytes".utf8), using: key, authenticating: context)
        #expect(throws: EncryptionError.authenticationFailed) {
            try Encryption.decrypt(sealed, using: EncryptionKey.generate(), authenticating: context)
        }
        #expect(throws: EncryptionError.authenticationFailed) { try Encryption.decrypt(sealed, using: key) }
        for index in [0, 12, sealed.count - 1] {
            var damaged = sealed
            damaged[index] ^= 1
            #expect(throws: EncryptionError.authenticationFailed) {
                try Encryption.decrypt(damaged, using: key, authenticating: context)
            }
        }
        #expect(throws: EncryptionError.invalidKeyLength) { try EncryptionKey(bytes: Data(count: 31)) }
        #expect(throws: EncryptionError.authenticationFailed) { try Encryption.decrypt(Data(), using: key) }
    }

    @Test(arguments: [0, 1, 63, 64, 65, 128, 193])
    func fileBoundaries(size: Int) throws {
        try temporaryDirectory { directory in
            let key = EncryptionKey.generate()
            let original = directory.appendingPathComponent("original")
            let sealed = directory.appendingPathComponent("encrypted")
            let restored = directory.appendingPathComponent("restored")
            let bytes = Data(repeating: 0x81, count: size)
            try bytes.write(to: original)
            try FileEncryption.encrypt(from: original, to: sealed, using: key, chunkSize: 64)
            try FileEncryption.decrypt(from: sealed, to: restored, using: key)
            #expect(try Data(contentsOf: restored) == bytes)
            #expect(try Data(contentsOf: original) == bytes)
            #expect(try FileManager.default.attributesOfItem(atPath: restored.path)[.posixPermissions] as? Int == 0o600)
        }
    }

    @Test func largeFileUsesMultipleChunks() throws {
        try temporaryDirectory { directory in
            let original = directory.appendingPathComponent("original")
            let sealed = directory.appendingPathComponent("encrypted")
            let restored = directory.appendingPathComponent("restored")
            FileManager.default.createFile(atPath: original.path, contents: nil)
            let handle = try FileHandle(forWritingTo: original)
            let block = Data(repeating: 0x54, count: 1_048_576)
            for _ in 0..<32 { try handle.write(contentsOf: block) }
            try handle.write(contentsOf: Data([7, 8, 9]))
            try handle.close()
            let key = EncryptionKey.generate()
            try FileEncryption.encrypt(from: original, to: sealed, using: key)
            try FileEncryption.decrypt(from: sealed, to: restored, using: key)
            #expect(try digest(original) == digest(restored))
            let second = directory.appendingPathComponent("second")
            try FileEncryption.encrypt(from: original, to: second, using: key)
            #expect(try digest(sealed) != digest(second))
        }
    }

    @Test func fileRejectsWrongKeyAndCleansPartialPlaintext() throws {
        try temporaryDirectory { directory in
            let key = EncryptionKey.generate()
            let original = directory.appendingPathComponent("original")
            let sealed = directory.appendingPathComponent("encrypted")
            let restored = directory.appendingPathComponent("restored")
            try Data(repeating: 1, count: 200).write(to: original)
            try FileEncryption.encrypt(from: original, to: sealed, using: key, chunkSize: 64)
            #expect(throws: EncryptionError.authenticationFailed) {
                try FileEncryption.decrypt(from: sealed, to: restored, using: EncryptionKey.generate())
            }
            var data = try Data(contentsOf: sealed)
            data[data.count - 1] ^= 1
            try data.write(to: sealed)
            #expect(throws: EncryptionError.authenticationFailed) {
                try FileEncryption.decrypt(from: sealed, to: restored, using: key)
            }
            #expect(!FileManager.default.fileExists(atPath: restored.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == ["encrypted", "original"])
        }
    }

    @Test func headerTruncationAndReorderingAreRejected() throws {
        try temporaryDirectory { directory in
            let key = EncryptionKey.generate()
            let original = directory.appendingPathComponent("original")
            let sealed = directory.appendingPathComponent("encrypted")
            let damaged = directory.appendingPathComponent("damaged")
            let restored = directory.appendingPathComponent("restored")
            try Data(repeating: 3, count: 128).write(to: original)
            try FileEncryption.encrypt(from: original, to: sealed, using: key, chunkSize: 64)
            let data = try Data(contentsOf: sealed)
            for offset in [0, 4, 36, 40] {
                var changed = data
                changed[offset] ^= 1
                try changed.write(to: damaged)
                #expect(throws: (any Error).self) { try FileEncryption.decrypt(from: damaged, to: restored, using: key) }
            }
            // 将尾块连同头部长度一起截短，仍须因头部 AAD 改变而失败。
            var truncated = Data(data.prefix(48 + 92))
            truncated[47] = 64
            try truncated.write(to: damaged)
            #expect(throws: EncryptionError.authenticationFailed) { try FileEncryption.decrypt(from: damaged, to: restored, using: key) }
            let reordered = data.prefix(48) + data[140..<232] + data[48..<140]
            try reordered.write(to: damaged)
            #expect(throws: EncryptionError.authenticationFailed) { try FileEncryption.decrypt(from: damaged, to: restored, using: key) }
            try Data(data.dropLast()).write(to: damaged)
            #expect(throws: EncryptionError.invalidFileFormat) { try FileEncryption.decrypt(from: damaged, to: restored, using: key) }
            #expect(!FileManager.default.fileExists(atPath: restored.path))
        }
    }

    @Test func emptyFileStillAuthenticatesAndOutputNeverOverwrites() throws {
        try temporaryDirectory { directory in
            let key = EncryptionKey.generate()
            let original = directory.appendingPathComponent("original")
            let sealed = directory.appendingPathComponent("encrypted")
            let restored = directory.appendingPathComponent("restored")
            try Data().write(to: original)
            try FileEncryption.encrypt(from: original, to: sealed, using: key)
            #expect(throws: EncryptionError.authenticationFailed) {
                try FileEncryption.decrypt(from: sealed, to: restored, using: EncryptionKey.generate())
            }
            let existing = Data("do not overwrite".utf8)
            try existing.write(to: restored)
            #expect(throws: EncryptionError.destinationExists) { try FileEncryption.decrypt(from: sealed, to: restored, using: key) }
            #expect(try Data(contentsOf: restored) == existing)
            #expect(throws: EncryptionError.invalidChunkSize) { try FileEncryption.encrypt(from: original, to: sealed, using: key, chunkSize: 0) }
            #expect(throws: EncryptionError.localFileRequired) {
                try FileEncryption.decrypt(from: URL(string: "https://example.invalid/file")!, to: directory.appendingPathComponent("unused"), using: key)
            }
        }
    }

    private func temporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    private func digest(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return Data(hash.finalize())
    }
}
