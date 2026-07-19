import Foundation
import MeetingBuddyApplication
import MeetingBuddyDomain

/// Explicit, no-network Markdown export confined to one local workspace.
/// A same-byte orphan left between rename and SQLite commit is reconciled on
/// retry; an existing different file is never overwritten.
public final class LocalMarkdownExportService: BriefingMarkdownExporting, @unchecked Sendable {
    private let store: SQLitePersistenceStore
    private let fileManager: FileManager

    public init(
        store: SQLitePersistenceStore,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.fileManager = fileManager
    }

    public func exportMarkdown(
        _ request: BriefingMarkdownExportRequest
    ) throws -> BriefingExportRecord {
        guard request.explicitUserAuthorization else {
            throw BriefingExportError.authorizationRequired
        }
        guard let final = try store.fetch(
            FinalBriefingV1.self,
            revisionID: request.finalBriefingRevision.revisionID
        ),
            final.finalBriefingID.canonicalString
                == request.finalBriefingRevision.logicalID.canonicalString,
            final.meetingID == request.meetingID
        else { throw BriefingExportError.finalBriefingUnavailable }
        guard final.revision.dataClassification == request.expectedClassification else {
            throw BriefingExportError.classificationMismatch
        }
        guard final.revision.lifecycleStatus == .published,
              final.revision.validationState == .valid,
              try store.staleMarks(for: request.finalBriefingRevision).isEmpty,
              let review = try store.activeBriefingReview(meetingID: request.meetingID),
              review.isCurrent,
              review.publication.finalBriefing.revision.revisionID
                == final.revision.revisionID
        else { throw BriefingExportError.staleOrInvalidFinal }

        let meetingDirectory = try WorkspacePathSecurity.createPrivateDirectory(
            store.workspace.layout.meetings.appendingPathComponent(
                request.meetingID.canonicalString,
                isDirectory: true
            ),
            within: store.workspace.layout.root,
            fileManager: fileManager
        )
        let exportsDirectory = try WorkspacePathSecurity.createPrivateDirectory(
            meetingDirectory.appendingPathComponent("exports", isDirectory: true),
            within: store.workspace.layout.root,
            fileManager: fileManager
        )
        let destination = try WorkspacePathSecurity.confinedURL(
            exportsDirectory.appendingPathComponent(request.fileName),
            within: store.workspace.layout.root,
            allowMissingLeaf: true
        )
        let bytes = Data(final.markdown.utf8)
        guard !bytes.isEmpty,
              try ContentDigest.sha256(ofUTF8Text: final.markdown) == final.markdownDigest
        else { throw BriefingExportError.integrityFailure }

        let rootPrefix = store.workspace.layout.root.path + "/"
        guard destination.path.hasPrefix(rootPrefix) else {
            throw BriefingExportError.pathDenied
        }
        let relativePath = try WorkspaceRelativePath(
            String(destination.path.dropFirst(rootPrefix.count))
        )
        let priorRecord = try store.briefingExportRecords(meetingID: request.meetingID)
            .first { $0.relativePath == relativePath }
        if let priorRecord {
            guard priorRecord.finalBriefingRevision == request.finalBriefingRevision,
                  priorRecord.markdownDigest == final.markdownDigest,
                  priorRecord.byteSize == UInt64(bytes.count),
                  priorRecord.dataClassification == final.revision.dataClassification
            else { throw BriefingExportError.destinationConflict }
        }

        if fileManager.fileExists(atPath: destination.path) {
            let existingURL = try WorkspacePathSecurity.confinedURL(
                destination,
                within: store.workspace.layout.root
            )
            let values = try existingURL.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            guard values.isRegularFile == true,
                  values.fileSize == bytes.count,
                  try Data(contentsOf: existingURL) == bytes
            else { throw BriefingExportError.destinationConflict }
        } else {
            let temporary = try WorkspacePathSecurity.confinedURL(
                exportsDirectory.appendingPathComponent(
                    ".briefing-export-\(UUID().uuidString.lowercased()).tmp"
                ),
                within: store.workspace.layout.root,
                allowMissingLeaf: true
            )
            guard fileManager.createFile(
                atPath: temporary.path,
                contents: bytes,
                attributes: [.posixPermissions: 0o600]
            ) else { throw BriefingExportError.integrityFailure }
            do {
                let staged = try WorkspacePathSecurity.confinedURL(
                    temporary,
                    within: store.workspace.layout.root
                )
                guard try Data(contentsOf: staged) == bytes else {
                    throw BriefingExportError.integrityFailure
                }
                try fileManager.moveItem(at: staged, to: destination)
                try fileManager.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: destination.path
                )
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }
        }

        if let priorRecord {
            return priorRecord
        }
        let record = try BriefingExportRecord(
            meetingID: request.meetingID,
            finalBriefingRevision: request.finalBriefingRevision,
            relativePath: relativePath,
            markdownDigest: final.markdownDigest,
            byteSize: UInt64(bytes.count),
            dataClassification: final.revision.dataClassification,
            explicitUserAuthorization: request.explicitUserAuthorization,
            exportedAt: request.requestedAt
        )
        try store.insertBriefingExportRecord(record)
        return record
    }
}
