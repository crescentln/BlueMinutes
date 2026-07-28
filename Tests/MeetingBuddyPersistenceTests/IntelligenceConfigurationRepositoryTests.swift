import Foundation
import MeetingBuddyApplication
import MeetingBuddyPersistence
import Testing

@Suite
struct IntelligenceConfigurationRepositoryTests {
    @Test
    func repositoryRoundTripsCanonicalMetadataWithPrivatePermissions()
        throws
    {
        let fixture = try IntelligenceRepositoryFixture()
        defer { fixture.remove() }
        let repository =
            try LocalIntelligenceConfigurationRepository(
                fileURL: fixture.configurationURL
            )
        let initial = try repository.load()
        let provider = try
            RemoteProviderConfiguration
            .openAISpeechToText(
                modelIdentifier: "whisper-1"
            )
        let next = try initial.replacing(
            providers: [provider]
        )

        try repository.save(
            next,
            expectedRevision: initial.revision
        )

        #expect(try repository.load() == next)
        let attributes =
            try FileManager.default
            .attributesOfItem(
                atPath: fixture.configurationURL.path
            )
        #expect(
            (attributes[.posixPermissions] as? NSNumber)?
                .uint16Value == 0o600
        )
        let parentAttributes =
            try FileManager.default
            .attributesOfItem(
                atPath: fixture.configurationURL
                    .deletingLastPathComponent().path
            )
        #expect(
            (parentAttributes[.posixPermissions] as? NSNumber)?
                .uint16Value == 0o700
        )
        let stored = try String(
            contentsOf: fixture.configurationURL,
            encoding: .utf8
        )
        #expect(!stored.lowercased().contains("api_key"))
        #expect(!stored.contains("sk-"))
    }

    @Test
    func optimisticRevisionConflictPreservesTheAcceptedFile()
        throws
    {
        let fixture = try IntelligenceRepositoryFixture()
        defer { fixture.remove() }
        let repository =
            try LocalIntelligenceConfigurationRepository(
                fileURL: fixture.configurationURL
            )
        let initial = try repository.load()
        let accepted = try initial.replacing(
            defaultSpeechLanguageTag: "fr"
        )
        try repository.save(
            accepted,
            expectedRevision: 0
        )
        let stale = try initial.replacing(
            defaultSpeechLanguageTag: "de"
        )

        #expect(
            throws:
                IntelligenceConfigurationError
                    .revisionConflict
        ) {
            try repository.save(
                stale,
                expectedRevision: 0
            )
        }
        #expect(try repository.load() == accepted)
    }

    @Test
    func symbolicLinkAndOversizedFilesFailClosed()
        throws
    {
        let symlinkFixture =
            try IntelligenceRepositoryFixture()
        defer { symlinkFixture.remove() }
        try FileManager.default.createDirectory(
            at: symlinkFixture.configurationURL
                .deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let target = symlinkFixture.root
            .appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: symlinkFixture.configurationURL,
            withDestinationURL: target
        )
        let symlinkRepository =
            try LocalIntelligenceConfigurationRepository(
                fileURL:
                    symlinkFixture.configurationURL
            )
        #expect(throws: (any Error).self) {
            _ = try symlinkRepository.load()
        }

        let oversizedFixture =
            try IntelligenceRepositoryFixture()
        defer { oversizedFixture.remove() }
        try FileManager.default.createDirectory(
            at: oversizedFixture.configurationURL
                .deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(
            repeating: 0x41,
            count:
                LocalIntelligenceConfigurationRepository
                .maximumFileBytes + 1
        ).write(to: oversizedFixture.configurationURL)
        let oversizedRepository =
            try LocalIntelligenceConfigurationRepository(
                fileURL:
                    oversizedFixture.configurationURL
            )
        #expect(throws: (any Error).self) {
            _ = try oversizedRepository.load()
        }
    }
}

private struct IntelligenceRepositoryFixture {
    let root: URL
    let configurationURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "blueminutes-intelligence-\(UUID().uuidString.lowercased())",
                isDirectory: true
            )
        configurationURL = root
            .appendingPathComponent(
                "private/configuration-v1.json",
                isDirectory: false
            )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
