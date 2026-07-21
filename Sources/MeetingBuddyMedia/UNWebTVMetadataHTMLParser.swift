import Foundation
import CryptoKit
import MeetingBuddyApplication
import MeetingBuddyDomain

public struct UNWebTVMetadataHTMLParser: Sendable {
    public static let version: UInt32 = 1

    public init() {}

    public func parse(
        _ data: Data,
        requestedURL: ValidatedUNWebTVAssetURL,
        finalURL: ValidatedUNWebTVAssetURL,
        fetchedAt: UTCInstant
    ) throws -> UNWebTVMetadataCandidate {
        guard !data.isEmpty, data.count <= 1_048_576,
              let html = String(data: data, encoding: .utf8)
        else {
            throw UNWebTVMetadataError.malformedResponse
        }

        let sanitized = try removingBlockedElements(from: html)
        let tags = try boundedTags(in: sanitized)
        var candidates: [UNWebTVFieldCandidate] = []

        if let title = try elementText(named: "title", in: sanitized) {
            try append(
                field: .title,
                value: title,
                source: .htmlTitle,
                key: "title",
                to: &candidates
            )
        }

        for tag in tags {
            let attributes = try parseAttributes(tag.attributes)
            switch tag.name {
            case "meta":
                guard let value = attributes["content"] else { continue }
                if let property = attributes["property"]?.lowercased() {
                    switch property {
                    case "og:title":
                        try append(field: .title, value: value, source: .metaProperty, key: "og:title", to: &candidates)
                    case "og:description":
                        try append(field: .description, value: value, source: .metaProperty, key: "og:description", to: &candidates)
                    default:
                        break
                    }
                }
                if let name = attributes["name"]?.lowercased() {
                    switch name {
                    case "description":
                        try append(field: .description, value: value, source: .metaName, key: "description", to: &candidates)
                    case "date", "production-date", "production_date":
                        try append(field: .productionDate, value: value, source: .metaName, key: name, to: &candidates)
                    default:
                        break
                    }
                }
            case "link":
                let relations = attributes["rel"]?.lowercased().split(whereSeparator: \.isWhitespace) ?? []
                guard relations.contains("canonical"), let href = attributes["href"],
                      let canonical = try? ValidatedUNWebTVAssetURL(decodeEntities(href))
                else { continue }
                try append(
                    field: .canonicalURL,
                    value: canonical.absoluteString,
                    source: .canonicalLink,
                    key: "canonical",
                    to: &candidates
                )
            case "time":
                if let value = attributes["datetime"] {
                    try append(field: .productionDate, value: value, source: .visibleLabel, key: "time.datetime", to: &candidates)
                }
            default:
                break
            }
        }

        let visibleText = try visiblePlainText(from: sanitized)
        let labels: [(String, UNWebTVMetadataField)] = [
            ("duration", .duration),
            ("category", .category),
            ("languages", .languageAvailability),
            ("language availability", .languageAvailability),
            ("broadcasting entity", .broadcastingEntity),
            ("summary", .summary)
        ]
        for line in visibleText.split(separator: "\n", omittingEmptySubsequences: true).prefix(2_048) {
            let text = String(line)
            let lowered = text.lowercased()
            for (label, field) in labels {
                let prefix = label + ":"
                guard lowered.hasPrefix(prefix) else { continue }
                let value = String(text.dropFirst(prefix.count))
                try append(field: field, value: value, source: .visibleLabel, key: label, to: &candidates)
            }
        }

        let deduplicated = deduplicate(candidates)
        return try UNWebTVMetadataCandidate(
            requestedURL: requestedURL,
            finalURL: finalURL,
            fields: Array(deduplicated.prefix(64)),
            fetchedAt: fetchedAt
        )
    }

    private struct Tag {
        let name: String
        let attributes: Substring
    }

    private func boundedTags(in html: String) throws -> [Tag] {
        var tags: [Tag] = []
        var cursor = html.startIndex
        while cursor < html.endIndex, tags.count < 4_096,
              let start = html[cursor...].firstIndex(of: "<")
        {
            guard let end = html[start...].firstIndex(of: ">") else { break }
            guard html.distance(from: start, to: end) <= 8_192 else {
                throw UNWebTVMetadataError.parserDrift
            }
            let bodyStart = html.index(after: start)
            let body = html[bodyStart..<end].drop(while: \.isWhitespace)
            if !body.isEmpty, body.first != "/", body.first != "!", body.first != "?" {
                let nameEnd = body.firstIndex(where: { $0.isWhitespace || $0 == "/" }) ?? body.endIndex
                let name = body[..<nameEnd].lowercased()
                if name.utf8.count <= 64 {
                    tags.append(Tag(name: name, attributes: body[nameEnd...]))
                }
            }
            cursor = html.index(after: end)
        }
        guard tags.count < 4_096 else { throw UNWebTVMetadataError.parserDrift }
        return tags
    }

    private func parseAttributes(_ source: Substring) throws -> [String: String] {
        var result: [String: String] = [:]
        var index = source.startIndex
        var count = 0
        while index < source.endIndex {
            while index < source.endIndex, source[index].isWhitespace || source[index] == "/" {
                index = source.index(after: index)
            }
            guard index < source.endIndex else { break }
            let keyStart = index
            while index < source.endIndex,
                  source[index].isLetter || source[index].isNumber
                    || source[index] == "-" || source[index] == "_" || source[index] == ":"
            {
                index = source.index(after: index)
            }
            guard index > keyStart else {
                index = source.index(after: index)
                continue
            }
            let key = source[keyStart..<index].lowercased()
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            var value = ""
            if index < source.endIndex, source[index] == "=" {
                index = source.index(after: index)
                while index < source.endIndex, source[index].isWhitespace {
                    index = source.index(after: index)
                }
                if index < source.endIndex, source[index] == "\"" || source[index] == "'" {
                    let quote = source[index]
                    index = source.index(after: index)
                    let valueStart = index
                    while index < source.endIndex, source[index] != quote {
                        index = source.index(after: index)
                    }
                    value = String(source[valueStart..<index])
                    if index < source.endIndex { index = source.index(after: index) }
                } else {
                    let valueStart = index
                    while index < source.endIndex, !source[index].isWhitespace, source[index] != "/" {
                        index = source.index(after: index)
                    }
                    value = String(source[valueStart..<index])
                }
            }
            if result[key] == nil { result[key] = decodeEntities(value) }
            count += 1
            guard count <= 64 else { throw UNWebTVMetadataError.parserDrift }
        }
        return result
    }

    private func elementText(named name: String, in html: String) throws -> String? {
        let lower = html.lowercased()
        guard let open = lower.range(of: "<\(name)"),
              let openEnd = lower[open.lowerBound...].firstIndex(of: ">"),
              let close = lower.range(of: "</\(name)>", range: openEnd..<lower.endIndex)
        else { return nil }
        let contentStart = html.index(after: openEnd)
        guard html.distance(from: contentStart, to: close.lowerBound) <= 16_384 else {
            throw UNWebTVMetadataError.parserDrift
        }
        return normalizedPlainText(String(html[contentStart..<close.lowerBound]))
    }

    private func removingBlockedElements(from html: String) throws -> String {
        var output = html
        for name in ["script", "style", "template", "noscript"] {
            var scans = 0
            while let open = output.range(of: "<\(name)", options: [.caseInsensitive]),
                  let close = output.range(
                      of: "</\(name)>",
                      options: [.caseInsensitive],
                      range: open.lowerBound..<output.endIndex
                  )
            {
                output.removeSubrange(open.lowerBound..<close.upperBound)
                scans += 1
                guard scans <= 256 else { throw UNWebTVMetadataError.parserDrift }
            }
        }
        return output
    }

    private func visiblePlainText(from html: String) throws -> String {
        var output = ""
        output.reserveCapacity(min(html.count, 65_536))
        var insideTag = false
        for character in html {
            if character == "<" { insideTag = true; output.append("\n"); continue }
            if character == ">" { insideTag = false; output.append("\n"); continue }
            if !insideTag { output.append(character) }
            guard output.utf8.count <= 262_144 else { throw UNWebTVMetadataError.parserDrift }
        }
        return decodeEntities(output)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { normalizedText(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func append(
        field: UNWebTVMetadataField,
        value: String,
        source: UNWebTVParserSource,
        key: String,
        to candidates: inout [UNWebTVFieldCandidate]
    ) throws {
        guard candidates.count < 64 else { throw UNWebTVMetadataError.parserDrift }
        let normalized = normalizedPlainText(value)
        guard !normalized.isEmpty else { return }
        candidates.append(
            try UNWebTVFieldCandidate(
                field: field,
                value: normalized,
                provenance: UNWebTVFieldProvenance(
                    parserVersion: Self.version,
                    source: source,
                    sourceKey: key,
                    normalizedValueDigest: try normalizedValueDigest(normalized),
                    confidence: confidence(for: source)
                )
            )
        )
    }

    private func deduplicate(_ values: [UNWebTVFieldCandidate]) -> [UNWebTVFieldCandidate] {
        var seen: Set<String> = []
        return values.filter { candidate in
            seen.insert("\(candidate.field.rawValue)\u{1f}\(candidate.value)").inserted
        }
    }

    private func normalizedValueDigest(_ value: String) throws -> ContentDigest {
        let digest = SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try ContentDigest(algorithm: .sha256, lowercaseHex: digest)
    }

    private func confidence(for source: UNWebTVParserSource) -> UNWebTVMetadataConfidence {
        switch source {
        case .canonicalLink:
            .high
        case .htmlTitle, .metaName, .metaProperty, .jsonLD:
            .medium
        case .visibleLabel:
            .low
        }
    }

    private func normalizedText(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func normalizedPlainText(_ value: String) -> String {
        let decoded = decodeEntities(value)
        var output = ""
        var insideTag = false
        for character in decoded {
            if character == "<" {
                insideTag = true
                output.append(" ")
            } else if character == ">" {
                insideTag = false
                output.append(" ")
            } else if !insideTag {
                output.append(character)
            }
        }
        return normalizedText(output)
    }

    private func decodeEntities(_ value: String) -> String {
        var result = value
        for (entity, replacement) in [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")
        ] {
            result = result.replacingOccurrences(of: entity, with: replacement, options: [.caseInsensitive])
        }
        return result
    }
}
