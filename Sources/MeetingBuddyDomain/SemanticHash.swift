import CryptoKit
import Foundation

/// Internal SHA-256 support for the documented MeetingBuddy semantic projection.
enum SemanticHash {
    static func sha256<Value: Encodable>(of value: Value) throws -> ContentDigest {
        let canonicalBytes = try CanonicalJSON.encode(value)
        return try sha256(data: canonicalBytes)
    }

    static func sha256(data: Data) throws -> ContentDigest {
        let digest = SHA256.hash(data: data)
        let alphabet = Array("0123456789abcdef".utf8)
        var encoded = [UInt8]()
        encoded.reserveCapacity(64)

        for byte in digest {
            encoded.append(alphabet[Int(byte >> 4)])
            encoded.append(alphabet[Int(byte & 0x0f)])
        }

        return try ContentDigest(
            algorithm: .sha256,
            lowercaseHex: String(decoding: encoded, as: UTF8.self)
        )
    }
}

public extension ContentDigest {
    /// SHA-256 over the exact UTF-8 bytes without normalization or trimming.
    static func sha256(ofUTF8Text text: String) throws -> ContentDigest {
        try SemanticHash.sha256(data: Data(text.utf8))
    }
}
