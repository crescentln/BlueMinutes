import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

enum CodexCurrentMeetingSearchTool {
    static let name = "search_current_meeting"
    static let maximumQueryUTF8Bytes = 256
    static let maximumResultCount = 8
    static let maximumExcerptUTF8Bytes = 4 * 1_024
    static let maximumOutputUTF8Bytes = 64 * 1_024

    static let specification: CodexJSONValue = .object([
        "type": .string("function"),
        "name": .string(name),
        "description": .string(
            "Search only the user-authorized current meeting transcript segments. Returns exact segment and revision identifiers with timestamps. Read-only; no files, audio, or other meetings."
        ),
        "inputSchema": .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("query")]),
            "properties": .object([
                "query": .object([
                    "type": .string("string"),
                    "minLength": .integer(1),
                    "maxLength": .integer(256)
                ]),
                "limit": .object([
                    "type": .string("integer"),
                    "minimum": .integer(1),
                    "maximum": .integer(
                        Int64(maximumResultCount)
                    )
                ]),
                "filters": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "language": .object([
                            "type": .string("string"),
                            "minLength": .integer(2),
                            "maxLength": .integer(35)
                        ]),
                        "startMilliseconds": .object([
                            "type": .string("integer"),
                            "minimum": .integer(0)
                        ]),
                        "endMilliseconds": .object([
                            "type": .string("integer"),
                            "minimum": .integer(1)
                        ])
                    ])
                ])
            ])
        ])
    ])
}

/// Mutable only within the same exact authorized meeting revision. It exposes
/// no filesystem, audio, database, or workspace-wide capability.
public actor CodexCurrentMeetingTranscriptIndex {
    private let workspaceID: WorkspaceID
    private let meetingID: MeetingID
    private let meetingRevision: SemanticRevisionReference
    private var segments: [CodexTranscriptContextSegment]

    public init(context: CodexMeetingTextContext) {
        workspaceID = context.workspaceID
        meetingID = context.meetingID
        meetingRevision = context.meetingRevision
        segments = context.segments
    }

    public func replace(
        with context: CodexMeetingTextContext
    ) throws {
        guard context.workspaceID == workspaceID,
              context.meetingID == meetingID,
              context.meetingRevision == meetingRevision
        else {
            throw CodexIntegrationContractError.invalidContext(
                "The read-only Codex index cannot cross its authorized meeting revision."
            )
        }
        segments = context.segments
    }

    func call(arguments: CodexJSONValue) throws -> CodexJSONValue {
        let query = try SearchQuery(arguments: arguments)
        let normalizedTerms = normalize(query.text).split(
            whereSeparator: \.isWhitespace
        )
        guard !normalizedTerms.isEmpty else {
            throw CodexAppServerError.protocolViolation(
                .forbiddenServerRequest
            )
        }

        let matches = segments.filter { segment in
            guard query.matchesFilters(segment) else { return false }
            let text = normalize(segment.text)
            return normalizedTerms.allSatisfy { text.contains($0) }
        }
        let selected = Array(matches.prefix(query.limit))
        let rows = selected.map { segment -> CodexJSONValue in
            let excerpt = boundedExcerpt(segment.text)
            return .object([
                "segment_id": .string(
                    segment.segmentRevision.logicalID.canonicalString
                ),
                "revision_id": .string(
                    segment.segmentRevision.revisionID.canonicalString
                ),
                "start_milliseconds": .integer(
                    segment.startMilliseconds
                ),
                "end_milliseconds": .integer(
                    segment.endMilliseconds
                ),
                "language": .string(segment.language.value),
                "text": .string(excerpt),
                "text_truncated": .bool(excerpt != segment.text)
            ])
        }
        let payload: CodexJSONValue = .object([
            "meeting_id": .string(meetingID.canonicalString),
            "meeting_revision_id": .string(
                meetingRevision.revisionID.canonicalString
            ),
            "results": .array(rows),
            "returned_count": .integer(Int64(rows.count)),
            "more_matches_available": .bool(
                matches.count > selected.count
            )
        ])
        guard let data = try? JSONEncoder().encode(payload),
              data.count
                  <= CodexCurrentMeetingSearchTool
                  .maximumOutputUTF8Bytes,
              let text = String(data: data, encoding: .utf8)
        else {
            throw CodexAppServerError.protocolViolation(
                .outputLimitExceeded
            )
        }
        return .object([
            "contentItems": .array([
                .object([
                    "type": .string("inputText"),
                    "text": .string(text)
                ])
            ]),
            "success": .bool(true)
        ])
    }

    private func normalize(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private func boundedExcerpt(_ text: String) -> String {
        if text.utf8.count
            <= CodexCurrentMeetingSearchTool.maximumExcerptUTF8Bytes
        {
            return text
        }
        var result = ""
        result.reserveCapacity(
            CodexCurrentMeetingSearchTool.maximumExcerptUTF8Bytes
        )
        for character in text {
            let candidateBytes = result.utf8.count
                + String(character).utf8.count
            if candidateBytes
                > CodexCurrentMeetingSearchTool.maximumExcerptUTF8Bytes
            {
                break
            }
            result.append(character)
        }
        return result
    }
}

private struct SearchQuery {
    let text: String
    let limit: Int
    let language: LanguageTag?
    let startMilliseconds: Int64?
    let endMilliseconds: Int64?

    init(arguments: CodexJSONValue) throws {
        guard let object = arguments.objectValue,
              Set(object.keys).isSubset(
                  of: ["query", "limit", "filters"]
              ),
              let text = object["query"]?.stringValue,
              text == text.trimmingCharacters(
                  in: .whitespacesAndNewlines
              ),
              !text.isEmpty,
              text.utf8.count
                  <= CodexCurrentMeetingSearchTool.maximumQueryUTF8Bytes
        else {
            throw CodexAppServerError.protocolViolation(
                .forbiddenServerRequest
            )
        }
        let limit64 = object["limit"]?.int64Value ?? 5
        guard (1...Int64(
            CodexCurrentMeetingSearchTool.maximumResultCount
        )).contains(limit64) else {
            throw CodexAppServerError.protocolViolation(
                .forbiddenServerRequest
            )
        }

        let filters: [String: CodexJSONValue]
        if let value = object["filters"] {
            guard let object = value.objectValue,
                  Set(object.keys).isSubset(
                      of: [
                          "language",
                          "startMilliseconds",
                          "endMilliseconds"
                      ]
                  )
            else {
                throw CodexAppServerError.protocolViolation(
                    .forbiddenServerRequest
                )
            }
            filters = object
        } else {
            filters = [:]
        }
        let language: LanguageTag?
        if let value = filters["language"]?.stringValue {
            do {
                language = try LanguageTag(value)
            } catch {
                throw CodexAppServerError.protocolViolation(
                    .forbiddenServerRequest
                )
            }
        } else {
            language = nil
        }
        let start = filters["startMilliseconds"]?.int64Value
        let end = filters["endMilliseconds"]?.int64Value
        guard start.map({ $0 >= 0 }) ?? true,
              end.map({ $0 > 0 }) ?? true,
              start == nil || end == nil || start! < end!
        else {
            throw CodexAppServerError.protocolViolation(
                .forbiddenServerRequest
            )
        }
        self.text = text
        limit = Int(limit64)
        self.language = language
        startMilliseconds = start
        endMilliseconds = end
    }

    func matchesFilters(
        _ segment: CodexTranscriptContextSegment
    ) -> Bool {
        if let language, segment.language != language {
            return false
        }
        if let startMilliseconds,
           segment.endMilliseconds <= startMilliseconds
        {
            return false
        }
        if let endMilliseconds,
           segment.startMilliseconds >= endMilliseconds
        {
            return false
        }
        return true
    }
}
