import Foundation
import MeetingBuddyDomain

public enum BriefingExportError: Error, Equatable, Sendable {
    case authorizationRequired
    case invalidFileName
    case finalBriefingUnavailable
    case staleOrInvalidFinal
    case classificationMismatch
    case destinationConflict
    case pathDenied
    case integrityFailure
}

public struct BriefingMarkdownExportRequest: Hashable, Sendable {
    public let meetingID: MeetingID
    public let finalBriefingRevision: SemanticRevisionReference
    public let fileName: String
    public let expectedClassification: DataClassification
    public let explicitUserAuthorization: Bool
    public let requestedAt: UTCInstant

    public init(
        meetingID: MeetingID,
        finalBriefingRevision: SemanticRevisionReference,
        fileName: String,
        expectedClassification: DataClassification,
        explicitUserAuthorization: Bool,
        requestedAt: UTCInstant
    ) throws {
        guard finalBriefingRevision.objectType == .finalBriefing else {
            throw BriefingExportError.finalBriefingUnavailable
        }
        guard Self.isValidFileName(fileName) else {
            throw BriefingExportError.invalidFileName
        }
        guard expectedClassification.isKnown else {
            throw BriefingExportError.classificationMismatch
        }
        self.meetingID = meetingID
        self.finalBriefingRevision = finalBriefingRevision
        self.fileName = fileName.lowercased().hasSuffix(".md") ? fileName : fileName + ".md"
        self.expectedClassification = expectedClassification
        self.explicitUserAuthorization = explicitUserAuthorization
        self.requestedAt = requestedAt
    }

    private static func isValidFileName(_ value: String) -> Bool {
        let stem = value.lowercased().hasSuffix(".md") ? String(value.dropLast(3)) : value
        return !stem.isEmpty
            && stem.utf8.count <= 128
            && !stem.hasPrefix(".")
            && !stem.contains("..")
            && stem.unicodeScalars.allSatisfy { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || scalar == "-"
                    || scalar == "_"
            }
    }
}

public struct BriefingExportRecord: Codable, Hashable, Sendable {
    public static let schemaVersion: UInt32 = 1

    public let exportID: BriefingExportID
    public let meetingID: MeetingID
    public let finalBriefingRevision: SemanticRevisionReference
    public let relativePath: WorkspaceRelativePath
    public let markdownDigest: ContentDigest
    public let byteSize: UInt64
    public let dataClassification: DataClassification
    public let explicitUserAuthorization: Bool
    public let exportedAt: UTCInstant

    public init(
        exportID: BriefingExportID = BriefingExportID(UUID()),
        meetingID: MeetingID,
        finalBriefingRevision: SemanticRevisionReference,
        relativePath: WorkspaceRelativePath,
        markdownDigest: ContentDigest,
        byteSize: UInt64,
        dataClassification: DataClassification,
        explicitUserAuthorization: Bool,
        exportedAt: UTCInstant
    ) throws {
        guard finalBriefingRevision.objectType == .finalBriefing,
              relativePath.rawValue.hasPrefix("Meetings/\(meetingID.canonicalString)/exports/"),
              relativePath.rawValue.hasSuffix(".md"),
              byteSize > 0,
              dataClassification.isKnown,
              explicitUserAuthorization
        else {
            throw BriefingExportError.integrityFailure
        }
        self.exportID = exportID
        self.meetingID = meetingID
        self.finalBriefingRevision = finalBriefingRevision
        self.relativePath = relativePath
        self.markdownDigest = markdownDigest
        self.byteSize = byteSize
        self.dataClassification = dataClassification
        self.explicitUserAuthorization = explicitUserAuthorization
        self.exportedAt = exportedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            exportID: container.decode(BriefingExportID.self, forKey: .exportID),
            meetingID: container.decode(MeetingID.self, forKey: .meetingID),
            finalBriefingRevision: container.decode(SemanticRevisionReference.self, forKey: .finalBriefingRevision),
            relativePath: container.decode(WorkspaceRelativePath.self, forKey: .relativePath),
            markdownDigest: container.decode(ContentDigest.self, forKey: .markdownDigest),
            byteSize: container.decode(UInt64.self, forKey: .byteSize),
            dataClassification: container.decode(DataClassification.self, forKey: .dataClassification),
            explicitUserAuthorization: container.decode(Bool.self, forKey: .explicitUserAuthorization),
            exportedAt: container.decode(UTCInstant.self, forKey: .exportedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case exportID = "export_id"
        case meetingID = "meeting_id"
        case finalBriefingRevision = "final_briefing_revision"
        case relativePath = "relative_path"
        case markdownDigest = "markdown_digest"
        case byteSize = "byte_size"
        case dataClassification = "data_classification"
        case explicitUserAuthorization = "explicit_user_authorization"
        case exportedAt = "exported_at"
    }
}

public protocol BriefingMarkdownExporting: Sendable {
    func exportMarkdown(_ request: BriefingMarkdownExportRequest) throws -> BriefingExportRecord
}

public protocol BriefingExportRepository: Sendable {
    func insertBriefingExportRecord(_ record: BriefingExportRecord) throws
    func briefingExportRecords(meetingID: MeetingID) throws -> [BriefingExportRecord]
}
