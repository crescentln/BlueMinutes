import CryptoKit
import Foundation

/// Internal SHA-256 support for the documented MeetingBuddy semantic projection.
enum SemanticHash {
    static func sha256<Value: Encodable>(of value: Value) throws -> ContentDigest {
        let canonicalBytes = try CanonicalJSON.encode(value)
        let digest = SHA256.hash(data: canonicalBytes)
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
