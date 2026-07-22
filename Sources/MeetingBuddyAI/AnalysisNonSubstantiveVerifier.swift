import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

/// A deliberately narrow application-owned omission policy. It recognizes
/// only punctuation/symbol-only text and a closed set of conventional markers
/// in the transcript and any translation; meaningful language always requires
/// analysis or manual review.
public enum AnalysisNonSubstantiveVerifier {
    public static func confirmation(
        for request: AnalysisRequest
    ) throws -> AnalysisOmissionConfirmation? {
        guard isNonSemantic(request.transcriptText),
              request.translatedText.map(isNonSemantic) ?? true
        else {
            return nil
        }
        return try AnalysisOmissionConfirmation(
            segmentRevision: request.transcriptRevision,
            sourceTextDigest: ContentDigest.sha256(ofUTF8Text: request.transcriptText),
            translationRevision: request.translationRevision,
            translationTextDigest: try request.translatedText.map(
                ContentDigest.sha256(ofUTF8Text:)
            )
        )
    }

    private static func isNonSemantic(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let recognizedMarkers: Set<String> = [
            "[applause]", "(applause)",
            "[laughter]", "(laughter)",
            "[silence]", "(silence)",
            "[inaudible]", "(inaudible)",
            "[music]", "(music)"
        ]
        return recognizedMarkers.contains(normalized)
            || (!normalized.isEmpty
                && normalized.unicodeScalars.allSatisfy { scalar in
                    CharacterSet.whitespacesAndNewlines.contains(scalar)
                        || CharacterSet.punctuationCharacters.contains(scalar)
                        || CharacterSet.symbols.contains(scalar)
                })
    }
}
