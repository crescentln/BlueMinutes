import Foundation

/// MeetingBuddy's deterministic v1 JSON encoding profile.
///
/// The profile uses UTF-8 JSON, sorted keys, explicit snake_case coding keys,
/// integer time/confidence values, and lowercase UUID/hash values. It is not a
/// claim of general RFC 8785 conformance.
public enum CanonicalJSON {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func encodeValidated<Value: Encodable & DomainValidatable>(
        _ value: Value
    ) throws -> Data {
        try value.validate()
        return try encode(value)
    }

    static func decode<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }

    public static func decodeValidated<Value: Decodable & DomainValidatable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let value = try decode(type, from: data)
        try value.validate()
        return value
    }
}
