import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct IdentifierAndScalarTests {
    @Test
    func stableIDUsesLowercaseSingleStringWireFormat() throws {
        let id = SourceAssetID(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)
        let data = try CanonicalJSON.encode(id)

        #expect(String(decoding: data, as: UTF8.self) == #""aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee""#)
        #expect(try CanonicalJSON.decode(SourceAssetID.self, from: data) == id)
        #expect(throws: DecodingError.self) {
            try CanonicalJSON.decode(SourceAssetID.self, from: Data(#""not-a-uuid""#.utf8))
        }
    }

    @Test
    func schemaVersionDefaultsMissingMinorToZero() throws {
        let version = try CanonicalJSON.decode(SchemaVersion.self, from: Data(#"{"major":1}"#.utf8))
        #expect(version == .v1)
    }

    @Test
    func fixedWidthScalarsRejectInvalidRanges() throws {
        #expect(throws: DomainValidationError.self) { try UTCInstant(millisecondsSinceUnixEpoch: -1) }
        #expect(throws: DomainValidationError.self) { try ConfidenceScore(millionths: 1_000_001) }
        #expect(throws: DomainValidationError.self) { try UTF8TextRange(startOffset: 0, length: 0) }
        #expect(throws: DomainValidationError.self) {
            try MediaTimeRange(startMilliseconds: 10, endMilliseconds: 10)
        }
        #expect(throws: DomainValidationError.self) { try DocumentLocation(pageNumber: 0) }
        #expect(throws: DomainValidationError.self) { try CalendarDate(year: 2025, month: 2, day: 29) }
        #expect(throws: DomainValidationError.self) { try CountryCode("X1") }
        #expect(try CalendarDate(year: 2024, month: 2, day: 29).day == 29)
        #expect(try CountryCode("xe").value == "XE")
    }

    @Test
    func directJSONDecoderCannotConstructInvalidValidatedScalars() {
        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(UTCInstant.self, from: Data("-1".utf8))
        }
        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(ConfidenceScore.self, from: Data("1000001".utf8))
        }
        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(
                UTF8TextRange.self,
                from: Data(#"{"length":0,"start_offset":0}"#.utf8)
            )
        }
        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(
                DocumentLocation.self,
                from: Data(#"{"section":" padded "}"#.utf8)
            )
        }
        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(
                CalendarDate.self,
                from: Data(#"{"day":31,"month":4,"year":2026}"#.utf8)
            )
        }
        #expect(throws: DomainValidationError.self) {
            try JSONDecoder().decode(CountryCode.self, from: Data(#""USA""#.utf8))
        }
    }

    @Test
    func classificationAggregationIsFailClosedAndOrderIndependent() {
        let future = DataClassification.unrecognized("future_class")
        #expect(DataClassification.mostRestrictive([.public, .restricted, .internal]) == .restricted)
        #expect(DataClassification.mostRestrictive([.restricted, future]) == future)
        #expect(
            DataClassification.mostRestrictive([.sensitive, .public])
                == DataClassification.mostRestrictive([.public, .sensitive])
        )
        let alpha = DataClassification.unrecognized("alpha_future")
        let omega = DataClassification.unrecognized("omega_future")
        #expect(
            DataClassification.mostRestrictive([alpha, omega])
                == DataClassification.mostRestrictive([omega, alpha])
        )
    }

    @Test
    func unknownOpenEnumRoundTripsWithoutBecomingKnown() throws {
        let data = Data(#""future_source_kind""#.utf8)
        let value = try CanonicalJSON.decode(SpeechSourceKind.self, from: data)

        #expect(value == .unrecognized("future_source_kind"))
        #expect(!value.isKnown)
        #expect(try CanonicalJSON.encode(value) == data)
        #expect(value != .unknown)
    }

    @Test
    func digestLanguageAndMIMEValidation() throws {
        #expect(throws: DomainValidationError.self) {
            try ContentDigest(algorithm: .sha256, lowercaseHex: "abcd")
        }
        #expect(throws: DomainValidationError.self) { try LanguageTag("e") }
        #expect(throws: DomainValidationError.self) { try MIMEType("audio") }

        #expect(try LanguageTag("ZH-Hans").value == "zh-hans")
        #expect(try MIMEType("Audio/MPEG").value == "audio/mpeg")
    }

    @Test
    func httpsURLRejectsPathsFileURLsAndUserInfo() throws {
        #expect(throws: DomainValidationError.self) {
            try HTTPSURL("file:///Users/example/meeting.wav")
        }
        #expect(throws: DomainValidationError.self) {
            try HTTPSURL("https://user:secret@example.invalid/meeting")
        }
        #expect(throws: DomainValidationError.self) { try HTTPSURL("../meeting.wav") }
        #expect(throws: DomainValidationError.self) { try HTTPSURL("HTTPS://example.invalid/meeting") }
        _ = try HTTPSURL("https://example.invalid/meeting?id=1")
    }
}
