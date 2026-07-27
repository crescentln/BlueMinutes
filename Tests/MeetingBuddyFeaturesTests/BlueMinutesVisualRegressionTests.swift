import AppKit
import ImageIO
import SwiftUI
import Testing
@testable import MeetingBuddyFeatures

@Suite(.serialized)
struct BlueMinutesVisualRegressionTests {
    @Test @MainActor
    func nativeCaptureIsOpaqueProfiledDeterministicRGB()
        throws
    {
        let descriptor =
            BlueMinutesVisualCaptureDescriptor(
                id:
                    "capture-contract-light",
                surface:
                    "capture-contract",
                state: "ready",
                viewport:
                    BlueMinutesVisualViewport(
                        width: 640,
                        height: 420
                    ),
                appearance: .light,
                accessibility:
                    .standard,
                locale: "en_US_POSIX",
                timeZone: "UTC",
                accent: "systemBlue",
                textSize: "large",
                inspectorPresented: false
            )
        let first =
            try BlueMinutesRuntimeCapture
                .capture(
                    descriptor: descriptor,
                    content:
                        AnyView(
                            captureContractView
                        )
                )
        let second =
            try BlueMinutesRuntimeCapture
                .capture(
                    descriptor: descriptor,
                    content:
                        AnyView(
                            captureContractView
                        )
                )
        let contract =
            try BlueMinutesRuntimeCapture
                .validatePNG(
                    first,
                    expectedViewport:
                        descriptor.viewport
                )
        let pngBytes =
            [UInt8](first)
        let profileRange =
            try firstChunkRange(
                named: "iCCP",
                in: pngBytes
            )
        let profileDataStart =
            profileRange.lowerBound + 8
        let profileDataEnd =
            profileRange.upperBound - 4
        guard let profileNameEnd =
            pngBytes[
                profileDataStart..<profileDataEnd
            ]
            .firstIndex(of: 0),
              profileNameEnd + 3
                < profileDataEnd
        else {
            Issue.record(
                "The PNG iCCP payload is truncated."
            )
            return
        }
        let compressionMethod =
            pngBytes[
                profileNameEnd + 1
            ]
        let zlibStart =
            profileNameEnd + 2
        let zlibHeader =
            (
                UInt16(
                    pngBytes[zlibStart]
                ) << 8
            )
                | UInt16(
                    pngBytes[zlibStart + 1]
                )
        let comparison =
            try BlueMinutesRuntimeCapture
                .compare(
                    expected: first,
                    actual: second
                )
        let imageSource =
            CGImageSourceCreateWithData(
                first as CFData,
                nil
            )
        let imageProperties =
            imageSource.flatMap {
                CGImageSourceCopyPropertiesAtIndex(
                    $0,
                    0,
                    nil
                )
            } as? [CFString: Any]

        #expect(contract.width == 640)
        #expect(contract.height == 420)
        #expect(contract.bitDepth == 8)
        #expect(contract.colorType == 2)
        #expect(
            contract.chunkNames.contains(
                "iCCP"
            )
        )
        #expect(compressionMethod == 0)
        #expect(
            pngBytes[zlibStart] & 0x0f
                == 8
        )
        #expect(
            pngBytes[zlibStart] >> 4
                <= 7
        )
        #expect(zlibHeader % 31 == 0)
        #expect(
            pngBytes[zlibStart + 1]
                & 0x20
                == 0
        )
        #expect(
            imageProperties?[
                kCGImagePropertyProfileName
            ] as? String
                == "sRGB IEC61966-2.1"
        )
        #expect(
            comparison.maximumChannelDelta
                == 0
        )
        #expect(
            comparison.changedPixelRatio
                == 0
        )
        #expect(
            comparison.luminanceSSIM
                == 1
        )
        #expect(
            BlueMinutesRuntimeCapture
                .sha256(first)
                == BlueMinutesRuntimeCapture
                .sha256(second)
        )
    }

    @Test @MainActor
    func compositedCaptureRetainsTheLastFrameAfterBoundedValidation()
        async throws
    {
        guard #available(macOS 26.0, *)
        else { return }
        let descriptor =
            BlueMinutesVisualCaptureDescriptor(
                id:
                    "composited-validation-probe",
                surface:
                    "capture-contract",
                state: "ready",
                viewport:
                    BlueMinutesVisualViewport(
                        width: 320,
                        height: 240
                    ),
                appearance: .light,
                accessibility:
                    .standard,
                locale: "en_US_POSIX",
                timeZone: "UTC",
                accent: "systemBlue",
                textSize: "large",
                inspectorPresented: false
            )
        var validationCount = 0

        do {
            _ = try await
                BlueMinutesRuntimeCapture
                .captureComposited(
                    descriptor:
                        descriptor,
                    content:
                        AnyView(
                            Text(
                                "Synthetic composited validation probe"
                            )
                            .frame(
                                maxWidth:
                                    .infinity,
                                maxHeight:
                                    .infinity
                            )
                        ),
                    validating: {
                        _ in
                        validationCount += 1
                        throw
                            BlueMinutesVisualHarnessError
                            .testPNGMalformed
                    }
                )
            Issue.record(
                "Bounded validation unexpectedly succeeded."
            )
        } catch let failure
            as BlueMinutesCompositedCaptureValidationFailure
        {
            #expect(validationCount == 3)
            _ = try BlueMinutesRuntimeCapture
                .validatePNG(
                    failure.capturedData,
                    expectedViewport:
                        descriptor.viewport
                )
            #expect(
                failure.underlyingError
                    is BlueMinutesVisualHarnessError
            )
        }
    }

    @Test
    func representativeMatrixHasExactCoverage()
    {
        let cases =
            BlueMinutesVisualFixtureCase.all
        let ids =
            cases.map(\.id)

        #expect(
            ids.count == Set(ids).count
        )
        #expect(cases.count == 50)
        #expect(
            Set(
                cases.map {
                    $0.descriptor
                        .appearance
                }
            )
                == [.light, .dark]
        )
        #expect(
            Set(
                cases
                    .filter {
                        $0.surface == .shell
                    }
                    .map {
                        $0.descriptor
                            .viewport
                    }
            )
                == [
                    BlueMinutesVisualViewport(
                        width: 860,
                        height: 600
                    ),
                    BlueMinutesVisualViewport(
                        width: 1_080,
                        height: 720
                    ),
                    BlueMinutesVisualViewport(
                        width: 1_440,
                        height: 1_024
                    ),
                    BlueMinutesVisualViewport(
                        width: 1_728,
                        height: 1_024
                    )
                ]
        )
        let states =
            Set(
                cases.map {
                    "\($0.descriptor.surface):\($0.descriptor.state)"
                }
            )
        let requiredStates:
            Set<String> = [
                "onboarding:empty",
                "local-media:ready",
                "local-media:working",
                "recording:ready",
                "recording:loading",
                "recording:active",
                "un-web-tv:blocked",
                "un-web-tv:candidate",
                "transcript:selected",
                "transcript:incomplete",
                "analysis:selected",
                "analysis:stale",
                "briefing:selected",
                "briefing:export-blocked",
                "history:empty",
                "history:results",
                "storage:healthy",
                "storage:destructive-disabled",
                "storage:failure",
                "settings:general",
                "settings:appearance"
            ]
        #expect(
            requiredStates
                .isSubset(of: states)
        )
        #expect(
            cases.contains {
                $0.descriptor
                    .inspectorPresented
            }
        )
        #expect(
            cases.contains {
                !$0.descriptor
                    .inspectorPresented
            }
        )
        #expect(
            cases.contains {
                $0.descriptor
                    .accessibility
                    .increaseContrast
            }
        )
        #expect(
            cases.contains {
                $0.descriptor
                    .accessibility
                    .largerText
            }
        )
        #expect(
            Set(
                BlueMinutesVisualFixtureCase
                    .manualSystemCases
                    .map(\.id)
            )
                == [
                    "transcript-incomplete-reduce-transparency",
                    "analysis-stale-differentiate-without-color",
                    "recording-active-reduce-motion"
                ]
        )
    }

    @Test @MainActor
    func recordingLoadingFixtureCapturesTheInFlightCapabilityState()
        async throws
    {
        let fixture =
            try await
            makeFeatureRecordingLoadingVisualFixture()
        #expect(
            fixture.store.workspace
                != nil
        )
        #expect(
            fixture.store.recordingSetup
                == nil
        )
        #expect(
            fixture.store.isWorking
        )
        await fixture.setupGate
            .release()
        await fixture.openTask.value
        #expect(
            fixture.store.recordingSetup
                != nil
        )
        #expect(
            !fixture.store.isWorking
        )
    }

    @Test @MainActor
    func committedManifestAndPNGContractsAreClosed()
        throws
    {
        let resourceRoot =
            try visualResourceRoot()
        let manifestData =
            try Data(
                contentsOf:
                    resourceRoot
                    .appendingPathComponent(
                        "manifest.json"
                    )
            )
        let manifestText =
            try #require(
                String(
                    data: manifestData,
                    encoding: .utf8
                )
            )
        #expect(
            !manifestText.contains(
                "/Users/"
            )
        )
        #expect(
            !manifestText
                .localizedCaseInsensitiveContains(
                    "credential"
                )
        )
        let manifest =
            try JSONDecoder()
            .decode(
                BlueMinutesVisualManifest.self,
                from: manifestData
            )
        try validateManifest(manifest)
        let firstGolden =
            try #require(
                manifest.goldens.first
            )
        let capture =
            firstGolden.capture
        let driftedCapture =
            BlueMinutesVisualCaptureDescriptor(
                id: capture.id,
                surface: capture.surface,
                state:
                    capture.state
                        + "-metadata-drift",
                viewport:
                    capture.viewport,
                appearance:
                    capture.appearance,
                accessibility:
                    capture.accessibility,
                locale: capture.locale,
                timeZone:
                    capture.timeZone,
                accent: capture.accent,
                textSize:
                    capture.textSize,
                inspectorPresented:
                    capture
                    .inspectorPresented
            )
        var driftedGoldens =
            manifest.goldens
        driftedGoldens[0] =
            BlueMinutesVisualGolden(
                capture: driftedCapture,
                fileName:
                    firstGolden.fileName,
                pngSHA256:
                    firstGolden.pngSHA256,
                pixelSHA256:
                    firstGolden.pixelSHA256,
                profileSHA256:
                    firstGolden.profileSHA256,
                threshold:
                    firstGolden.threshold
            )
        let driftedManifest =
            BlueMinutesVisualManifest(
                version:
                    manifest.version,
                baselineSourceRevision:
                    manifest
                    .baselineSourceRevision,
                environment:
                    manifest.environment,
                goldens:
                    driftedGoldens,
                manualSystemCases:
                    manifest
                    .manualSystemCases
            )
        #expect(
            throws:
                BlueMinutesVisualHarnessError
                .self
        ) {
            try validateManifest(
                driftedManifest
            )
        }
        let goldenRoot =
            resourceRoot
            .appendingPathComponent(
                "Goldens",
                isDirectory: true
            )
        let names =
            try FileManager.default
            .contentsOfDirectory(
                atPath: goldenRoot.path
            )
            .sorted()
        #expect(
            names
                == manifest.goldens
                .map(\.fileName)
                .sorted()
        )
        let pngHashByID =
            Dictionary(
                uniqueKeysWithValues:
                    manifest.goldens.map {
                        (
                            $0.capture.id,
                            $0.pngSHA256
                        )
                    }
            )
        for appearance in [
            "light",
            "dark"
        ] {
            #expect(
                pngHashByID[
                    "briefing-selected-\(appearance)"
                ]
                    != pngHashByID[
                        "briefing-export-blocked-\(appearance)"
                    ]
            )
        }
        for golden in manifest.goldens {
            let data =
                try Data(
                    contentsOf:
                        goldenRoot
                        .appendingPathComponent(
                            golden.fileName
                        )
                )
            let contract =
                try BlueMinutesRuntimeCapture
                .validatePNG(
                    data,
                    expectedViewport:
                        golden.capture
                        .viewport
                )
            #expect(
                BlueMinutesRuntimeCapture
                    .sha256(data)
                    == golden.pngSHA256
            )
            #expect(
                contract.profileSHA256
                    == golden
                    .profileSHA256
            )
        }
    }

    @Test @MainActor
    func PNGContractRejectsDimensionAndCRCDrift()
        throws
    {
        let descriptor =
            BlueMinutesVisualFixtureCase
            .all[0].descriptor
        let data =
            try BlueMinutesRuntimeCapture
            .capture(
                descriptor: descriptor,
                content:
                    AnyView(
                        Text(
                            "Synthetic format probe"
                        )
                        .frame(
                            maxWidth:
                                .infinity,
                            maxHeight:
                                .infinity
                        )
                    )
            )
        #expect(
            throws:
                BlueMinutesRuntimeCaptureError
                    .self
        ) {
            try BlueMinutesRuntimeCapture
                .validatePNG(
                    data,
                    expectedViewport:
                        BlueMinutesVisualViewport(
                            width:
                                descriptor
                                .viewport
                                .width + 1,
                            height:
                                descriptor
                                .viewport
                                .height
                        )
                )
        }
        var corrupted =
            [UInt8](data)
        let payloadIndex =
            try firstIDATPayloadIndex(
                corrupted
            )
        corrupted[payloadIndex] ^= 0x01
        #expect(
            throws:
                BlueMinutesRuntimeCaptureError
                    .self
        ) {
            try BlueMinutesRuntimeCapture
                .validatePNG(
                    Data(corrupted),
                    expectedViewport:
                        descriptor.viewport
                )
        }

        let original =
            [UInt8](data)
        let profileRange =
            try firstChunkRange(
                named: "iCCP",
                in: original
            )
        let imageDataRange =
            try firstChunkRange(
                named: "IDAT",
                in: original
            )
        #expect(
            profileRange.upperBound
                == imageDataRange.lowerBound
        )
        var reordered =
            [UInt8]()
        reordered.append(
            contentsOf:
                original[
                    0..<profileRange.lowerBound
                ]
        )
        reordered.append(
            contentsOf:
                original[
                    imageDataRange
                ]
        )
        reordered.append(
            contentsOf:
                original[
                    profileRange
                ]
        )
        reordered.append(
            contentsOf:
                original[
                    imageDataRange
                    .upperBound..<original.count
                ]
        )
        #expect(
            throws:
                BlueMinutesRuntimeCaptureError
                    .self
        ) {
            try BlueMinutesRuntimeCapture
                .validatePNG(
                    Data(reordered),
                    expectedViewport:
                        descriptor.viewport
                )
        }
    }

    @Test @MainActor
    func contractMismatchWritesFourBoundedDiagnosticArtifacts()
        throws
    {
        let fixture =
            BlueMinutesVisualFixtureCase
            .all[0]
        let actual =
            try BlueMinutesRuntimeCapture
            .capture(
                descriptor:
                    fixture.descriptor,
                content:
                    AnyView(
                        Text(
                            "Synthetic contract failure"
                        )
                        .frame(
                            maxWidth:
                                .infinity,
                            maxHeight:
                                .infinity
                        )
                    )
            )
        let output =
            FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        defer {
            try? FileManager.default
                .removeItem(
                    at: output
                )
        }

        try writeFailureArtifacts(
            fixture: fixture,
            expected:
                Data(
                    "not-a-png"
                    .utf8
                ),
            actual: actual,
            comparison: nil,
            threshold:
                BlueMinutesVisualThreshold(
                    maximumChannelDelta:
                        0,
                    maximumChangedPixelRatio:
                        0,
                    minimumLuminanceSSIM:
                        1
                ),
            kind:
                .contractMismatch,
            artifactRootOverride:
                output
        )

        let root =
            output.appendingPathComponent(
                fixture.id,
                isDirectory: true
            )
        #expect(
            try Set(
                FileManager.default
                .contentsOfDirectory(
                    atPath:
                        root.path
                )
            )
                == [
                    "actual.png",
                    "comparison.json",
                    "diff.png",
                    "expected.png"
                ]
        )
        let evidence =
            try JSONDecoder()
            .decode(
                BlueMinutesVisualFailureEvidence
                    .self,
                from:
                    Data(
                        contentsOf:
                            root
                            .appendingPathComponent(
                                "comparison.json"
                            )
                    )
            )
        #expect(
            evidence.kind
                == .contractMismatch
        )
        #expect(
            evidence.comparison == nil
        )
        #expect(
            evidence
                .differenceArtifactKind
                == "contract-failure-placeholder"
        )
        _ =
            try BlueMinutesRuntimeCapture
            .validatePNG(
                Data(
                    contentsOf:
                        root
                        .appendingPathComponent(
                            "diff.png"
                        )
                ),
                expectedViewport:
                    fixture.descriptor
                    .viewport
            )
    }

    @Test @MainActor
    func systemOwnedAccessibilityMismatchFailsClosed()
        throws
    {
        let workspace =
            NSWorkspace.shared
        let descriptor =
            BlueMinutesVisualCaptureDescriptor(
                id:
                    "accessibility-environment-mismatch",
                surface:
                    "capture-contract",
                state: "blocked",
                viewport:
                    BlueMinutesVisualViewport(
                        width: 320,
                        height: 200
                    ),
                appearance: .light,
                accessibility:
                    BlueMinutesVisualAccessibility(
                        increaseContrast: false,
                        reduceTransparency:
                            workspace
                            .accessibilityDisplayShouldReduceTransparency,
                        differentiateWithoutColor:
                            workspace
                            .accessibilityDisplayShouldDifferentiateWithoutColor,
                        reduceMotion:
                            !workspace
                            .accessibilityDisplayShouldReduceMotion,
                        largerText: false
                    ),
                locale: "en_US_POSIX",
                timeZone: "UTC",
                accent: "systemBlue",
                textSize: "large",
                inspectorPresented: false
            )
        #expect(
            throws:
                BlueMinutesRuntimeCaptureError
                    .self
        ) {
            try BlueMinutesRuntimeCapture
                .capture(
                    descriptor: descriptor,
                    content:
                        AnyView(
                            Text(
                                "Must not render"
                            )
                        )
                )
        }
    }

    @Test
    func candidateRefusesSymlinkedGoldenDirectory()
        throws
    {
        let fileManager =
            FileManager.default
        let temporaryRoot =
            fileManager
            .temporaryDirectory
            .appendingPathComponent(
                UUID().uuidString,
                isDirectory: true
            )
        try fileManager.createDirectory(
            at: temporaryRoot,
            withIntermediateDirectories:
                false
        )
        defer {
            try? fileManager.removeItem(
                at: temporaryRoot
            )
        }
        let sourceParent =
            URL(
                fileURLWithPath: #filePath
            )
            .deletingLastPathComponent()
        let linkedParent =
            temporaryRoot
            .appendingPathComponent(
                "linked-tests",
                isDirectory: true
            )
        try fileManager.createSymbolicLink(
            at: linkedParent,
            withDestinationURL:
                sourceParent
        )

        #expect(
            throws:
                BlueMinutesVisualHarnessError
                .self
        ) {
            try assertNotGoldenDirectory(
                linkedParent
                    .appendingPathComponent(
                        "VisualRegression",
                        isDirectory: true
                    )
            )
        }
    }

    @Test(
        .enabled(
            if:
                ProcessInfo.processInfo
                .environment[
                    "MEETINGBUDDY_VISUAL_MODE"
                ] != nil
        )
    )
    @MainActor
    func runPinnedNativeVisualHarness()
        async throws
    {
        let mode =
            try BlueMinutesVisualHarnessMode
                .current()
        try validatePinnedExecutionEnvironment(
            mode: mode
        )
        switch mode {
        case .candidate:
            try await writeCandidate()
        case .calibration:
            try await writeCalibration()
        case .regression:
            try await compareGoldens()
        }
    }

    @MainActor
    private var captureContractView:
        some View
    {
        VStack(
            alignment: .leading,
            spacing: 18
        ) {
            EditorialSectionHeader(
                "Synthetic Capture Contract",
                detail:
                    "Offline, deterministic, and free of meeting content."
            )
            WorkflowStateView(
                title:
                    "Exact local proof ready",
                detail:
                    "The native runtime capture is normalized to an opaque 8-bit sRGB PNG.",
                systemImage:
                    "checkmark.seal",
                tone: .ready
            )
            HStack {
                Button("Review Evidence") {}
                Button(
                    "Delete Synthetic Item…",
                    role: .destructive
                ) {}
            }
            Spacer()
        }
        .padding(28)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .background(
            BlueMinutesColors.canvas
        )
    }

    @MainActor
    private func writeCandidate()
        async throws
    {
        let outputRoot =
            try artifactRoot()
                .appendingPathComponent(
                    "VisualRegression",
                    isDirectory: true
                )
        try assertNotGoldenDirectory(
            outputRoot
        )
        let goldenRoot =
            outputRoot.appendingPathComponent(
                "Goldens",
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: goldenRoot,
                withIntermediateDirectories:
                    true
            )

        var goldens:
            [BlueMinutesVisualGolden] = []
        for fixture in
            BlueMinutesVisualFixtureCase.all
        {
            let data =
                try await capture(
                    fixture
                )
            let contract =
                try BlueMinutesRuntimeCapture
                .validatePNG(
                    data,
                    expectedViewport:
                        fixture.descriptor
                        .viewport
                )
            let fileName =
                "\(fixture.id).png"
            try data.write(
                to:
                    goldenRoot
                    .appendingPathComponent(
                        fileName
                    ),
                options: .atomic
            )
            goldens.append(
                BlueMinutesVisualGolden(
                    capture:
                        fixture.descriptor,
                    fileName: fileName,
                    pngSHA256:
                        BlueMinutesRuntimeCapture
                        .sha256(data),
                    pixelSHA256:
                        try BlueMinutesRuntimeCapture
                        .pixelSHA256(data),
                    profileSHA256:
                        contract
                        .profileSHA256,
                    threshold:
                        BlueMinutesVisualThreshold(
                            maximumChannelDelta:
                                0,
                            maximumChangedPixelRatio:
                                0,
                            minimumLuminanceSSIM:
                                1
                        )
                )
            )
        }
        let manifest =
            BlueMinutesVisualManifest(
                version: 1,
                baselineSourceRevision:
                    try sourceRevision(),
                environment:
                    canonicalEnvironment,
                goldens:
                    goldens.sorted {
                        $0.capture.id
                            < $1.capture.id
                    },
                manualSystemCases:
                    BlueMinutesVisualFixtureCase
                    .manualSystemCases
            )
        try encodedJSON(manifest)
            .write(
                to:
                    outputRoot
                    .appendingPathComponent(
                        "manifest.json"
                    ),
                options: .atomic
            )
    }

    @MainActor
    private func writeCalibration()
        async throws
    {
        guard
            let processIndexText =
                ProcessInfo.processInfo
                .environment[
                    "MEETINGBUDDY_VISUAL_PROCESS_INDEX"
                ],
            let processIndex =
                Int(processIndexText),
            (1...3).contains(
                processIndex
            )
        else {
            throw
                BlueMinutesVisualHarnessError
                .executionEnvironmentMismatch
        }
        var evidence:
            [BlueMinutesVisualCalibrationEvidence] =
            []
        for fixture in
            BlueMinutesVisualFixtureCase.all
        {
            var captures: [Data] = []
            for _ in 0..<5 {
                captures.append(
                    try await capture(
                        fixture
                    )
                )
            }
            var maximumDelta: UInt8 = 0
            var maximumChangedRatio = 0.0
            var minimumSSIM = 1.0
            let hashes =
                Set(
                    captures.map {
                        BlueMinutesRuntimeCapture
                            .sha256($0)
                    }
                )
            if hashes.count > 1 {
                for first in captures.indices {
                    for second in
                        captures.indices
                        where second > first
                    {
                        let comparison =
                            try BlueMinutesRuntimeCapture
                            .compare(
                                expected:
                                    captures[first],
                                actual:
                                    captures[second]
                            )
                        maximumDelta = max(
                            maximumDelta,
                            comparison
                            .maximumChannelDelta
                        )
                        maximumChangedRatio =
                            max(
                                maximumChangedRatio,
                                comparison
                                .changedPixelRatio
                            )
                        minimumSSIM = min(
                            minimumSSIM,
                            comparison
                            .luminanceSSIM
                        )
                    }
                }
            }
            evidence.append(
                BlueMinutesVisualCalibrationEvidence(
                    id: fixture.id,
                    captureCount: 5,
                    pairCount: 10,
                    capturePNGHashes:
                        captures.map {
                            BlueMinutesRuntimeCapture
                            .sha256($0)
                        },
                    maximumChannelDelta:
                        maximumDelta,
                    maximumChangedPixelRatio:
                        maximumChangedRatio,
                    minimumLuminanceSSIM:
                        minimumSSIM
                )
            )
        }
        let outputRoot =
            try artifactRoot()
        try FileManager.default
            .createDirectory(
                at: outputRoot,
                withIntermediateDirectories:
                    true
            )
        let manifestData =
            try Data(
                contentsOf:
                    try visualResourceRoot()
                    .appendingPathComponent(
                        "manifest.json"
                    )
            )
        let catalogData =
            try encodedJSON(
                BlueMinutesVisualFixtureCase
                .all
                .map(\.descriptor)
                .sorted {
                    $0.id < $1.id
                }
            )
        let processEnvironment =
            ProcessInfo.processInfo
            .environment
        let runEvidence =
            BlueMinutesVisualCalibrationRunEvidence(
                version: 1,
                processIndex:
                    processIndex,
                environment:
                    canonicalEnvironment,
                sourceRevision:
                    try sourceRevision(),
                manifestSHA256:
                    BlueMinutesRuntimeCapture
                    .sha256(
                        manifestData
                    ),
                fixtureCatalogSHA256:
                    BlueMinutesRuntimeCapture
                    .sha256(
                        catalogData
                    ),
                githubRunID:
                    processEnvironment[
                        "GITHUB_RUN_ID"
                    ],
                githubRunAttempt:
                    processEnvironment[
                        "GITHUB_RUN_ATTEMPT"
                    ],
                cases: evidence
            )
        try encodedJSON(runEvidence)
            .write(
                to:
                    outputRoot
                    .appendingPathComponent(
                        "calibration-\(processIndex).json"
                    ),
                options: .atomic
            )
    }

    @MainActor
    private func compareGoldens()
        async throws
    {
        let resourceRoot =
            try visualResourceRoot()
        let manifestData =
            try Data(
                contentsOf:
                    resourceRoot
                    .appendingPathComponent(
                        "manifest.json"
                    )
            )
        let manifest =
            try JSONDecoder()
            .decode(
                BlueMinutesVisualManifest.self,
                from: manifestData
            )
        try validateManifest(manifest)
        let goldenByID =
            Dictionary(
                uniqueKeysWithValues:
                    manifest.goldens.map {
                        ($0.capture.id, $0)
                    }
            )
        for fixture in
            BlueMinutesVisualFixtureCase.all
        {
            guard let golden =
                goldenByID[fixture.id]
            else {
                throw BlueMinutesVisualHarnessError
                    .missingGolden(
                        fixture.id
                    )
            }
            let expected =
                try Data(
                    contentsOf:
                        resourceRoot
                        .appendingPathComponent(
                            "Goldens",
                            isDirectory:
                                true
                        )
                        .appendingPathComponent(
                            golden.fileName
                        )
                )
            let actual =
                try await capture(
                    fixture
                )
            do {
                let expectedContract =
                    try BlueMinutesRuntimeCapture
                    .validatePNG(
                        expected,
                        expectedViewport:
                            fixture.descriptor
                            .viewport
                    )
                let actualContract =
                    try BlueMinutesRuntimeCapture
                    .validatePNG(
                        actual,
                        expectedViewport:
                            fixture.descriptor
                            .viewport
                    )
                guard
                    BlueMinutesRuntimeCapture
                    .sha256(expected)
                        == golden
                        .pngSHA256,
                    try BlueMinutesRuntimeCapture
                    .pixelSHA256(expected)
                        == golden
                        .pixelSHA256,
                    expectedContract
                    .profileSHA256
                        == golden
                        .profileSHA256,
                    actualContract
                    .profileSHA256
                        == golden
                        .profileSHA256
                else {
                    throw
                        BlueMinutesVisualHarnessError
                        .goldenContractMismatch(
                            fixture.id
                        )
                }
            } catch {
                try writeFailureArtifacts(
                    fixture: fixture,
                    expected: expected,
                    actual: actual,
                    comparison:
                        try? BlueMinutesRuntimeCapture
                        .compare(
                            expected:
                                expected,
                            actual:
                                actual
                        ),
                    threshold:
                        golden.threshold,
                    kind:
                        .contractMismatch
                )
                throw BlueMinutesVisualHarnessError
                    .goldenContractMismatch(
                        fixture.id
                    )
            }
            let comparison =
                try BlueMinutesRuntimeCapture
                .compare(
                    expected: expected,
                    actual: actual
                )
            let passed =
                comparison
                .maximumChannelDelta
                <= golden.threshold
                    .maximumChannelDelta
                && comparison
                    .changedPixelRatio
                    <= golden.threshold
                    .maximumChangedPixelRatio
                && comparison
                    .luminanceSSIM
                    >= golden.threshold
                    .minimumLuminanceSSIM
            guard passed
            else {
                try writeFailureArtifacts(
                    fixture: fixture,
                    expected: expected,
                    actual: actual,
                    comparison:
                        comparison,
                    threshold:
                        golden.threshold,
                    kind:
                        .pixelMismatch
                )
                throw BlueMinutesVisualHarnessError
                    .pixelMismatch(
                        fixture.id
                    )
            }
        }
    }

    @MainActor
    private func capture(
        _ fixture:
            BlueMinutesVisualFixtureCase
    ) async throws -> Data {
        let content =
            try await
            BlueMinutesProductionVisualFixtureFactory
            .content(for: fixture)
        do {
            let data =
                try await BlueMinutesRuntimeCapture
                .captureComposited(
                    descriptor:
                        fixture.descriptor,
                    content:
                        content.view,
                    validating: {
                        data in
                        try validateCompositedStructure(
                            data,
                            fixture: fixture
                        )
                    }
                )
            await content.teardown()
            return data
        } catch let failure
            as BlueMinutesCompositedCaptureValidationFailure
        {
            try? writeCompositedCaptureDiagnostic(
                failure.capturedData,
                fixture: fixture
            )
            await content.teardown()
            throw failure.underlyingError
        } catch {
            await content.teardown()
            throw error
        }
    }

    private func writeCompositedCaptureDiagnostic(
        _ data: Data,
        fixture:
            BlueMinutesVisualFixtureCase
    ) throws {
        let diagnosticRoot =
            try artifactRoot()
            .appendingPathComponent(
                "VisualRegression",
                isDirectory: true
            )
            .appendingPathComponent(
                "Diagnostics",
                isDirectory: true
            )
        try FileManager.default
            .createDirectory(
                at: diagnosticRoot,
                withIntermediateDirectories:
                    true
            )
        try data.write(
            to:
                diagnosticRoot
                .appendingPathComponent(
                    "\(fixture.id)-last-capture.png"
                ),
            options: .atomic
        )
    }

    @MainActor
    private func validateCompositedStructure(
        _ data: Data,
        fixture:
            BlueMinutesVisualFixtureCase
    ) throws {
        guard try BlueMinutesRuntimeCapture
            .compositorEdgesAreNormalized(
                data
            )
        else {
            throw BlueMinutesVisualHarnessError
                .compositorEdgesNotNormalized(
                    fixture.id
                )
        }

        let viewport =
            fixture.descriptor.viewport
        var regions:
            [BlueMinutesVisualPixelRegion]
        switch fixture.surface {
        case .shell, .onboarding:
            regions = [
                BlueMinutesVisualPixelRegion(
                    x: 10,
                    y: 20,
                    width: 270,
                    height:
                        viewport.height - 40
                )
            ]
        case .analysis, .transcript:
            if fixture.descriptor
                .inspectorPresented
            {
                regions = [
                    BlueMinutesVisualPixelRegion(
                        x:
                            viewport.width - 360,
                        y: 20,
                        width: 330,
                        height:
                            viewport.height - 40
                    )
                ]
            } else {
                regions = []
            }
        default:
            regions = []
        }
        regions.append(
            contentsOf:
                BlueMinutesVisualNativeActionContract
                .matching(
                    fixtureID:
                        fixture.id
                )
                .map(\.region)
        )

        for region in regions {
            let distinctColorCount =
                try BlueMinutesRuntimeCapture
                .distinctRGBColorCount(
                    data,
                    inTopLeft: region
                )
            guard distinctColorCount >= 32
            else {
                throw BlueMinutesVisualHarnessError
                    .layeredContentMissing(
                        id: fixture.id,
                        region: region,
                        observedDistinctColors:
                            distinctColorCount,
                        requiredDistinctColors:
                            32
                    )
            }
        }
    }

    private func validateManifest(
        _ manifest:
            BlueMinutesVisualManifest
    ) throws {
        let manifestIDs =
            manifest.goldens
            .map {
                $0.capture.id
            }
            .sorted()
        let expectedIDs =
            BlueMinutesVisualFixtureCase
            .all.map(\.id)
            .sorted()
        let manifestCaptures =
            manifest.goldens
            .map(\.capture)
            .sorted {
                $0.id < $1.id
            }
        let expectedCaptures =
            BlueMinutesVisualFixtureCase
            .all
            .map(\.descriptor)
            .sorted {
                $0.id < $1.id
            }
        let goldensAreExact =
              manifest.goldens.allSatisfy {
                  $0.fileName
                      == "\($0.capture.id).png"
                      && !$0.capture.id
                      .contains("/")
                      && !$0.capture.id
                      .contains("\\")
                      &&
                  $0.capture.textSize
                    == (
                        $0.capture
                            .accessibility
                            .largerText
                        ? "accessibility2"
                        : "large"
                    )
                    && $0.capture.locale
                        == "en_US_POSIX"
                    && $0.capture.timeZone
                        == "UTC"
                    && $0.capture.accent
                        == "systemBlue"
                    && $0.threshold
                        .maximumChannelDelta
                        == 0
                    && $0.threshold
                        .maximumChangedPixelRatio
                        == 0
                    && $0.threshold
                        .minimumLuminanceSSIM
                        == 1
            }
        guard manifest.version == 1,
              manifest
              .baselineSourceRevision
              .utf8.count == 40,
              manifest
              .baselineSourceRevision
              .utf8.allSatisfy({
                  ($0 >= 48 && $0 <= 57)
                      || ($0 >= 97 && $0 <= 102)
              }),
              manifest.environment
                == canonicalEnvironment,
              manifestIDs == expectedIDs,
              manifestCaptures
                == expectedCaptures,
              manifest.manualSystemCases
                == BlueMinutesVisualFixtureCase
                .manualSystemCases,
              goldensAreExact
        else {
            throw BlueMinutesVisualHarnessError
                .invalidManifest
        }
    }

    @MainActor
    private func writeFailureArtifacts(
        fixture:
            BlueMinutesVisualFixtureCase,
        expected: Data,
        actual: Data,
        comparison:
            BlueMinutesVisualComparison?,
        threshold:
            BlueMinutesVisualThreshold,
        kind:
            BlueMinutesVisualFailureKind,
        artifactRootOverride:
            URL? = nil
    ) throws {
        let root =
            try (
                artifactRootOverride
                    ?? artifactRoot()
            )
                .appendingPathComponent(
                    fixture.id,
                    isDirectory: true
                )
        try FileManager.default
            .createDirectory(
                at: root,
                withIntermediateDirectories:
                    true
            )
        try expected.write(
            to:
                root.appendingPathComponent(
                    "expected.png"
                ),
            options: .atomic
        )
        try actual.write(
            to:
                root.appendingPathComponent(
                    "actual.png"
                ),
            options: .atomic
        )
        let difference: Data
        let differenceKind: String
        do {
            difference =
                try BlueMinutesRuntimeCapture
                .differenceImage(
                    expected: expected,
                    actual: actual
                )
            differenceKind =
                "pixel-difference"
        } catch {
            difference =
                try BlueMinutesRuntimeCapture
                .contractFailureDifferenceImage(
                    viewport:
                        fixture
                        .descriptor
                        .viewport
                )
            differenceKind =
                "contract-failure-placeholder"
        }
        try difference.write(
                to:
                    root
                    .appendingPathComponent(
                        "diff.png"
                    ),
                options: .atomic
            )
        try encodedJSON(
            BlueMinutesVisualFailureEvidence(
                id: fixture.id,
                kind: kind,
                comparison: comparison,
                threshold: threshold,
                expectedPNGHash:
                    BlueMinutesRuntimeCapture
                    .sha256(expected),
                actualPNGHash:
                    BlueMinutesRuntimeCapture
                    .sha256(actual),
                differenceArtifactKind:
                    differenceKind
            )
        )
        .write(
            to:
                root.appendingPathComponent(
                    "comparison.json"
                ),
            options: .atomic
        )
    }

    private func encodedJSON<T: Encodable>(
        _ value: T
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        return try encoder.encode(value)
    }

    private func artifactRoot()
        throws -> URL
    {
        guard let path =
            ProcessInfo.processInfo
            .environment[
                "MEETINGBUDDY_VISUAL_ARTIFACT_DIR"
            ],
              !path.isEmpty
        else {
            throw BlueMinutesVisualHarnessError
                .artifactDirectoryMissing
        }
        return URL(
            fileURLWithPath: path,
            isDirectory: true
        )
        .standardizedFileURL
    }

    private func sourceRevision()
        throws -> String
    {
        guard let revision =
            ProcessInfo.processInfo
            .environment[
                "MEETINGBUDDY_VISUAL_SOURCE_REVISION"
            ],
              revision.utf8.count == 40,
              revision.utf8.allSatisfy({
                  ($0 >= 48 && $0 <= 57)
                      || ($0 >= 97 && $0 <= 102)
              })
        else {
            throw
                BlueMinutesVisualHarnessError
                .executionEnvironmentMismatch
        }
        return revision
    }

    private func validatePinnedExecutionEnvironment(
        mode:
            BlueMinutesVisualHarnessMode
    ) throws {
        let environment =
            ProcessInfo.processInfo
            .environment
        guard
            environment[
                "MEETINGBUDDY_VISUAL_ENVIRONMENT_ATTESTATION"
            ]
                == "macos-26-arm64/20260720.0258.1;26.4/25E246;Xcode-26.6/17F113;Swift-6.3.3;SDK-26.5/25F70"
        else {
            throw
                BlueMinutesVisualHarnessError
                .executionEnvironmentMismatch
        }
        _ = try sourceRevision()
        let processIndex =
            environment[
                "MEETINGBUDDY_VISUAL_PROCESS_INDEX"
            ]
        switch mode {
        case .calibration:
            guard
                processIndex == "1"
                    || processIndex == "2"
                    || processIndex == "3"
            else {
                throw
                    BlueMinutesVisualHarnessError
                    .executionEnvironmentMismatch
            }
        case .candidate, .regression:
            guard processIndex == nil
            else {
                throw
                    BlueMinutesVisualHarnessError
                    .executionEnvironmentMismatch
            }
        }
    }

    private func visualResourceRoot()
        throws -> URL
    {
        guard let root =
            Bundle.module.resourceURL?
            .appendingPathComponent(
                "VisualRegression",
                isDirectory: true
            )
        else {
            throw BlueMinutesVisualHarnessError
                .resourcesUnavailable
        }
        return root
    }

    private func assertNotGoldenDirectory(
        _ output: URL
    ) throws {
        let source =
            URL(
                fileURLWithPath: #filePath
            )
            .deletingLastPathComponent()
            .appendingPathComponent(
                "VisualRegression",
                isDirectory: true
            )
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resolvedOutput =
            output.standardizedFileURL
            .resolvingSymlinksInPath()
        let outputPath =
            resolvedOutput.path
        let sourcePath =
            source.path
        guard outputPath != sourcePath,
              !outputPath.hasPrefix(
                  sourcePath + "/"
              ),
              !sourcePath.hasPrefix(
                  outputPath + "/"
              )
        else {
            throw BlueMinutesVisualHarnessError
                .candidateTargetsGoldens
        }
    }

    private var canonicalEnvironment:
        BlueMinutesVisualEnvironment
    {
        BlueMinutesVisualEnvironment(
            platformFamily: "macos-26",
            operatingSystemVersion:
                "26.4",
            operatingSystemBuild:
                "25E246",
            xcodeVersion: "26.6",
            xcodeBuild: "17F113",
            swiftVersion: "6.3.3",
            swiftCompilerBuild:
                "swiftlang-6.3.3.1.3",
            clangBuild:
                "clang-2100.1.1.101",
            targetTriple:
                "arm64-apple-macosx26.0",
            macOSSDKVersion: "26.5",
            macOSSDKBuild: "25F70",
            runnerImage:
                "macos-26-arm64",
            runnerImageVersion:
                "20260720.0258.1",
            architecture: "arm64",
            locale: "en_US_POSIX",
            timeZone: "UTC",
            pointToPixelScale: 1,
            expandedViewport:
                BlueMinutesVisualViewport(
                    width: 1_728,
                    height: 1_024
                ),
            fixtureSeed:
                "blueminutes-editorial-dossier-v1",
            fixtureVersion: 1,
            comparisonAlgorithmVersion:
                1
        )
    }

    private func firstIDATPayloadIndex(
        _ bytes: [UInt8]
    ) throws -> Int {
        var offset = 8
        while offset + 12 <= bytes.count {
            let length =
                Int(
                    UInt32(
                        bytes[offset]
                    ) << 24
                        | UInt32(
                            bytes[
                                offset + 1
                            ]
                        ) << 16
                        | UInt32(
                            bytes[
                                offset + 2
                            ]
                        ) << 8
                        | UInt32(
                            bytes[
                                offset + 3
                            ]
                        )
                )
            let typeStart = offset + 4
            let dataStart = typeStart + 4
            let chunkEnd =
                dataStart + length + 4
            guard chunkEnd <= bytes.count,
                  let name = String(
                      bytes:
                          bytes[
                              typeStart..<(typeStart + 4)
                          ],
                      encoding: .ascii
                  )
            else {
                throw BlueMinutesVisualHarnessError
                    .testPNGMalformed
            }
            if name == "IDAT",
               length > 0
            {
                return dataStart
            }
            offset = chunkEnd
        }
        throw BlueMinutesVisualHarnessError
            .testPNGMalformed
    }

    private func firstChunkRange(
        named expectedName: String,
        in bytes: [UInt8]
    ) throws -> Range<Int> {
        var offset = 8
        while offset + 12 <= bytes.count {
            let length =
                Int(
                    UInt32(
                        bytes[offset]
                    ) << 24
                        | UInt32(
                            bytes[
                                offset + 1
                            ]
                        ) << 16
                        | UInt32(
                            bytes[
                                offset + 2
                            ]
                        ) << 8
                        | UInt32(
                            bytes[
                                offset + 3
                            ]
                        )
                )
            let typeStart = offset + 4
            let chunkEnd =
                typeStart + 4 + length + 4
            guard chunkEnd <= bytes.count,
                  let name = String(
                      bytes:
                          bytes[
                              typeStart..<(typeStart + 4)
                          ],
                      encoding: .ascii
                  )
            else {
                throw BlueMinutesVisualHarnessError
                    .testPNGMalformed
            }
            if name == expectedName {
                return offset..<chunkEnd
            }
            offset = chunkEnd
        }
        throw BlueMinutesVisualHarnessError
            .testPNGMalformed
    }
}

private enum BlueMinutesVisualHarnessMode:
    String
{
    case candidate
    case calibration
    case regression

    static func current()
        throws -> Self
    {
        guard let raw =
            ProcessInfo.processInfo
            .environment[
                "MEETINGBUDDY_VISUAL_MODE"
            ],
              let mode = Self(
                  rawValue: raw
              )
        else {
            throw BlueMinutesVisualHarnessError
                .invalidMode
        }
        return mode
    }
}

private struct BlueMinutesVisualCalibrationEvidence:
    Codable
{
    let id: String
    let captureCount: Int
    let pairCount: Int
    let capturePNGHashes: [String]
    let maximumChannelDelta: UInt8
    let maximumChangedPixelRatio:
        Double
    let minimumLuminanceSSIM:
        Double
}

private struct BlueMinutesVisualCalibrationRunEvidence:
    Codable
{
    let version: Int
    let processIndex: Int
    let environment:
        BlueMinutesVisualEnvironment
    let sourceRevision: String
    let manifestSHA256: String
    let fixtureCatalogSHA256: String
    let githubRunID: String?
    let githubRunAttempt: String?
    let cases:
        [BlueMinutesVisualCalibrationEvidence]
}

private struct BlueMinutesVisualFailureEvidence:
    Codable
{
    let id: String
    let kind:
        BlueMinutesVisualFailureKind
    let comparison:
        BlueMinutesVisualComparison?
    let threshold:
        BlueMinutesVisualThreshold
    let expectedPNGHash: String
    let actualPNGHash: String
    let differenceArtifactKind: String
}

private enum BlueMinutesVisualFailureKind:
    String,
    Codable
{
    case pixelMismatch =
        "pixel-mismatch"
    case contractMismatch =
        "contract-mismatch"
}

private enum BlueMinutesVisualHarnessError:
    Error
{
    case invalidMode
    case invalidManifest
    case executionEnvironmentMismatch
    case artifactDirectoryMissing
    case resourcesUnavailable
    case candidateTargetsGoldens
    case missingGolden(String)
    case pixelMismatch(String)
    case goldenContractMismatch(String)
    case compositorEdgesNotNormalized(
        String
    )
    case layeredContentMissing(
        id: String,
        region:
            BlueMinutesVisualPixelRegion,
        observedDistinctColors: Int,
        requiredDistinctColors: Int
    )
    case testPNGMalformed
}
