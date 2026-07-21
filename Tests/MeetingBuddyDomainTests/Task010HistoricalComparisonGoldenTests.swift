import Foundation
import Testing
@testable import MeetingBuddyDomain

@Suite
struct Task010HistoricalComparisonGoldenTests {
    @Test
    func falseChangeVocabularyAndQualifiedLanguageMatchTheReviewedGoldenFixture() throws {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "Task010FalseChangeGolden",
                withExtension: "json"
            )
        )
        let data = try Data(contentsOf: fixtureURL)
        let rows = try JSONDecoder().decode([GoldenRow].self, from: data)
        #expect(rows.count == 5)
        for row in rows {
            let state = HistoricalDifferenceState(encodedValue: row.differenceState)
            let finding = HistoricalFinding(encodedValue: row.finding)
            #expect(state.isKnown)
            #expect(finding.isKnown)
            #expect(finding.qualifiedSummary == row.summary)
            #expect(finding.isCompatible(with: state))
            switch finding {
            case .insufficientEvidence:
                #expect(state == .insufficientEvidence)
            case .repeatedPosition, .wordingOnlyDifference, .noConfirmedChange:
                #expect(state == .noConfirmedDifference)
            case .possibleChange, .potentiallyStrongerWording, .possibleNewReservation:
                #expect(state == .possibleDifference)
            case .userConfirmedChange, .unrecognized:
                Issue.record("The false-change Golden fixture cannot assert a confirmed change.")
            }
        }
        #expect(!HistoricalFinding.insufficientEvidence.isCompatible(with: .possibleDifference))
        #expect(!HistoricalFinding.wordingOnlyDifference.isCompatible(with: .userConfirmedDifference))
        #expect(!HistoricalFinding.possibleChange.isCompatible(with: .noConfirmedDifference))
        #expect(!HistoricalFinding.userConfirmedChange.isCompatible(with: .possibleDifference))
    }

    private struct GoldenRow: Decodable {
        let differenceState: String
        let finding: String
        let summary: String

        private enum CodingKeys: String, CodingKey {
            case differenceState = "difference_state"
            case finding
            case summary
        }
    }
}
