// Copyright (c) 2026 YueGe
// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// 仅限非商业使用；商业使用须获得版权所有者书面授权。详见 LICENSE。
import CryptoKit
import Foundation

public enum EncryptionError: Error, Equatable, Sendable {
    case invalidKeyLength
    case authenticationFailed
    case invalidFileFormat
    case invalidChunkSize
    case localFileRequired
    case destinationExists
    case sourceChanged
}

/// 通用 256 位密钥。密钥的安全持久化由调用方负责，不接入任何业务状态。
public struct EncryptionKey: Sendable {
    let value: SymmetricKey

    public init(bytes: Data) throws {
        guard bytes.count == 32 else { throw EncryptionError.invalidKeyLength }
        value = SymmetricKey(data: bytes)
    }

    private init(value: SymmetricKey) { self.value = value }

    public static func generate() -> EncryptionKey {
        EncryptionKey(value: SymmetricKey(size: .bits256))
    }

    /// 仅供调用方写入其安全密钥存储；不要记录或随密文公开。
    public func exportBytes() -> Data { value.withUnsafeBytes { Data($0) } }
}

/// 单个消息使用 CryptoKit 标准 combined 格式：12 字节 nonce、密文、16 字节 tag。
public enum Encryption {
    public static func encrypt(_ plaintext: Data, using key: EncryptionKey, authenticating context: Data = Data()) throws -> Data {
        guard let result = try AES.GCM.seal(plaintext, using: key.value, authenticating: context).combined else {
            throw EncryptionError.authenticationFailed
        }
        return result
    }

    public static func decrypt(_ ciphertext: Data, using key: EncryptionKey, authenticating context: Data = Data()) throws -> Data {
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key.value, authenticating: context)
        } catch {
            throw EncryptionError.authenticationFailed
        }
    }
}
