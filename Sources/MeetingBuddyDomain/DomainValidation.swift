import Foundation

/// Stable categories for deterministic domain-validation failures.
public enum ValidationIssueCode: String, Codable, Hashable, Sendable {
    case duplicateValue = "duplicate_value"
    case emptyValue = "empty_value"
    case inconsistentValue = "inconsistent_value"
    case invalidFormat = "invalid_format"
    case invalidRange = "invalid_range"
    case missingRequiredValue = "missing_required_value"
    case unsupportedValue = "unsupported_value"
}

/// One deterministic validation failure at a stable field path.
public struct ValidationIssue: Codable, Hashable, Sendable {
    public let code: ValidationIssueCode
    public let path: String
    public let message: String

    public init(code: ValidationIssueCode, path: String, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }
}

/// Aggregates validation failures without discarding their stable order.
public struct DomainValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let issues: [ValidationIssue]

    public init(issues: [ValidationIssue]) {
        self.issues = issues
    }

    public var description: String {
        issues
            .map { "\($0.path): \($0.code.rawValue) — \($0.message)" }
            .joined(separator: "\n")
    }
}

/// A domain value that can be checked without I/O or mutable state.
public protocol DomainValidatable {
    func validationIssues() -> [ValidationIssue]
}

public extension DomainValidatable {
    /// Throws all validation issues in deterministic contract order.
    func validate() throws {
        let issues = validationIssues()
        guard issues.isEmpty else {
            throw DomainValidationError(issues: issues)
        }
    }
}

extension String {
    var meetingBuddyTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var meetingBuddyContainsControlCharacter: Bool {
        unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

func duplicateIssues<Value: Hashable>(
    in values: [Value],
    path: String
) -> [ValidationIssue] {
    var observed: Set<Value> = []
    for value in values where !observed.insert(value).inserted {
        return [
            ValidationIssue(
                code: .duplicateValue,
                path: path,
                message: "Values must be unique."
            )
        ]
    }
    return []
}

func boundedLabelIssues(
    _ value: String,
    path: String,
    maximumUTF8Bytes: Int = 512
) -> [ValidationIssue] {
    guard
        value == value.meetingBuddyTrimmed,
        !value.isEmpty,
        value.utf8.count <= maximumUTF8Bytes,
        !value.meetingBuddyContainsControlCharacter
    else {
        return [
            ValidationIssue(
                code: .invalidFormat,
                path: path,
                message: "The value must be non-empty, trimmed, bounded text without control characters."
            )
        ]
    }
    return []
}

func preservedSourceTextIssues(
    _ value: String,
    path: String,
    maximumUTF8Bytes: Int = 65_536
) -> [ValidationIssue] {
    guard
        !value.meetingBuddyTrimmed.isEmpty,
        value.utf8.count <= maximumUTF8Bytes,
        !value.contains("\u{0}")
    else {
        return [
            ValidationIssue(
                code: .invalidFormat,
                path: path,
                message: "Source text must be non-empty, bounded, and contain no null byte."
            )
        ]
    }
    return []
}

func reviewConfirmationIssues(
    reviewStatus: ReviewStatus,
    userConfirmed: Bool,
    path: String = "review_status"
) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    if !reviewStatus.isKnown {
        issues.append(
            ValidationIssue(
                code: .unsupportedValue,
                path: path,
                message: "The review status is not supported by this contract version."
            )
        )
    }
    if userConfirmed != (reviewStatus == .confirmed) {
        issues.append(
            ValidationIssue(
                code: .inconsistentValue,
                path: "user_confirmed",
                message: "User confirmation and confirmed review status must agree."
            )
        )
    }
    return issues
}

func semanticHashIssues(
    storedHash: ContentDigest?,
    calculatedHash: () throws -> ContentDigest,
    objectName: String
) -> [ValidationIssue] {
    guard let storedHash else { return [] }
    do {
        guard storedHash != (try calculatedHash()) else { return [] }
        return [
            ValidationIssue(
                code: .inconsistentValue,
                path: "revision.semantic_content_hash",
                message: "The stored semantic hash does not match \(objectName) content."
            )
        ]
    } catch {
        return [
            ValidationIssue(
                code: .invalidFormat,
                path: "revision.semantic_content_hash",
                message: "\(objectName) semantic content could not be hashed canonically."
            )
        ]
    }
}
