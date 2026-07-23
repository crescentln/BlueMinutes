import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct ResearchIntegrationValueTests {
    @Test
    func researchIdentifiersEncodeAsCanonicalUUIDsAndRejectMalformedValues() throws {
        let identifier = try ResearchWorkspaceID(
            validating: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
        )

        #expect(identifier.canonicalString == "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        #expect(
            String(decoding: try JSONEncoder().encode(identifier), as: UTF8.self)
                == #""aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa""#
        )
        #expect(throws: DomainValidationError.self) {
            _ = try ResearchWorkspaceID(validating: "not-a-uuid")
        }
    }

    @Test
    func researchValuesPreserveUnknownFutureCasesWithoutTrustingThem() throws {
        let known = SourceAuthority.official
        let future = SourceAuthority.unrecognized("future_authority")
        let encoded = try JSONEncoder().encode(future)
        let decoded = try JSONDecoder().decode(SourceAuthority.self, from: encoded)

        #expect(known.encodedValue == "official")
        #expect(known.isKnown)
        #expect(decoded == future)
        #expect(decoded.encodedValue == "future_authority")
        #expect(!decoded.isKnown)
        #expect(SourceCompleteness.complete.encodedValue == "complete")
    }

    @Test
    func instructionScopePrecedenceIsDeterministic() {
        let scopes: [InstructionProfileScope] = [
            .request,
            .global,
            .researchWorkspace,
            .template
        ]

        #expect(scopes.sorted() == [.global, .template, .researchWorkspace, .request])
    }

    @Test
    func newContractValuesRemainHashableCodableAndSendable() throws {
        requireSendable(ResearchWorkspaceID.self)
        requireSendable(ArtifactID.self)
        requireSendable(ConversationID.self)
        requireSendable(SourceAuthority.self)

        let first = ResearchWorkspaceID(
            UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        )
        let second = ResearchWorkspaceID(
            UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        )
        let identifiers: Set<ResearchWorkspaceID> = [first, second, first]

        #expect(identifiers.count == 2)
        #expect(
            try JSONDecoder().decode(
                ResearchWorkspaceID.self,
                from: JSONEncoder().encode(first)
            ) == first
        )
    }
}

private func requireSendable<Value: Sendable>(_: Value.Type) {}
