import AppKit
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

enum BlueMinutesVisualAppearance:
    String,
    Codable,
    Hashable,
    Sendable
{
    case light
    case dark
}

struct BlueMinutesVisualAccessibility:
    Codable,
    Equatable,
    Sendable
{
    let increaseContrast: Bool
    let reduceTransparency: Bool
    let differentiateWithoutColor: Bool
    let reduceMotion: Bool
    let largerText: Bool

    static let standard =
        BlueMinutesVisualAccessibility(
            increaseContrast: false,
            reduceTransparency: false,
            differentiateWithoutColor: false,
            reduceMotion: false,
            largerText: false
        )
}

struct BlueMinutesVisualViewport:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    let width: Int
    let height: Int
}

struct BlueMinutesVisualCaptureDescriptor:
    Codable,
    Equatable,
    Sendable
{
    let id: String
    let surface: String
    let state: String
    let viewport: BlueMinutesVisualViewport
    let appearance: BlueMinutesVisualAppearance
    let accessibility:
        BlueMinutesVisualAccessibility
    let locale: String
    let timeZone: String
    let accent: String
    let textSize: String
    let inspectorPresented: Bool
}

struct BlueMinutesVisualThreshold:
    Codable,
    Equatable,
    Sendable
{
    let maximumChannelDelta: UInt8
    let maximumChangedPixelRatio: Double
    let minimumLuminanceSSIM: Double
}

struct BlueMinutesVisualGolden:
    Codable,
    Equatable,
    Sendable
{
    let capture:
        BlueMinutesVisualCaptureDescriptor
    let fileName: String
    let pngSHA256: String
    let pixelSHA256: String
    let profileSHA256: String
    let threshold:
        BlueMinutesVisualThreshold
}

struct BlueMinutesVisualEnvironment:
    Codable,
    Equatable,
    Sendable
{
    let platformFamily: String
    let operatingSystemVersion: String
    let operatingSystemBuild: String
    let xcodeVersion: String
    let xcodeBuild: String
    let swiftVersion: String
    let swiftCompilerBuild: String
    let clangBuild: String
    let targetTriple: String
    let macOSSDKVersion: String
    let macOSSDKBuild: String
    let runnerImage: String
    let runnerImageVersion: String
    let architecture: String
    let locale: String
    let timeZone: String
    let pointToPixelScale: Int
    let expandedViewport:
        BlueMinutesVisualViewport
    let fixtureSeed: String
    let fixtureVersion: Int
    let comparisonAlgorithmVersion: Int
}

struct BlueMinutesVisualManifest:
    Codable,
    Equatable,
    Sendable
{
    let version: Int
    let baselineSourceRevision: String
    let environment:
        BlueMinutesVisualEnvironment
    let goldens:
        [BlueMinutesVisualGolden]
    let manualSystemCases:
        [BlueMinutesVisualCaptureDescriptor]
}

struct BlueMinutesPNGContract:
    Equatable,
    Sendable
{
    let width: Int
    let height: Int
    let bitDepth: UInt8
    let colorType: UInt8
    let chunkNames: [String]
    let profileSHA256: String
}

struct BlueMinutesVisualComparison:
    Codable,
    Equatable,
    Sendable
{
    let maximumChannelDelta: UInt8
    let changedPixelRatio: Double
    let luminanceSSIM: Double
}

enum BlueMinutesRuntimeCaptureError:
    Error,
    Equatable
{
    case invalidViewport
    case invalidTimeZone(String)
    case bitmapAllocationFailed
    case imageCreationFailed
    case pngEncodingFailed
    case malformedPNG(String)
    case pngContractViolation(String)
    case imageDecodeFailed
    case imageDimensionsDiffer
    case accessibilityEnvironmentMismatch(
        String
    )
}

@MainActor
enum BlueMinutesRuntimeCapture {
    private static let pngSignature:
        [UInt8] = [
            0x89, 0x50, 0x4e, 0x47,
            0x0d, 0x0a, 0x1a, 0x0a
        ]

    static func capture(
        descriptor:
            BlueMinutesVisualCaptureDescriptor,
        content: AnyView
    ) throws -> Data {
        let viewport = descriptor.viewport
        guard viewport.width > 0,
              viewport.height > 0
        else {
            throw BlueMinutesRuntimeCaptureError
                .invalidViewport
        }
        try validateAccessibilityEnvironment(
            descriptor.accessibility
        )
        guard let timeZone =
            TimeZone(
                identifier:
                    descriptor.timeZone
            )
        else {
            throw BlueMinutesRuntimeCaptureError
                .invalidTimeZone(
                    descriptor.timeZone
                )
        }

        let application =
            NSApplication.shared
        if !application.isRunning {
            application.finishLaunching()
        }

        let size = CGSize(
            width: viewport.width,
            height: viewport.height
        )
        let root = BlueMinutesVisualCaptureRoot(
            appearance:
                descriptor.appearance,
            accessibility:
                descriptor.accessibility,
            locale:
                descriptor.locale,
            timeZone:
                timeZone,
            content: content
        )
        let hostingView =
            NSHostingView(rootView: root)
        hostingView.frame = CGRect(
            origin: .zero,
            size: size
        )
        hostingView.wantsLayer = true

        let window = NSWindow(
            contentRect: CGRect(
                origin: .zero,
                size: size
            ),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.isOpaque = true
        window.backgroundColor =
            descriptor.appearance == .dark
                ? .black
                : .white
        window.appearance =
            visualAppearance(
                appearance:
                    descriptor.appearance,
                increaseContrast:
                    descriptor
                    .accessibility
                    .increaseContrast
            )
        window.contentView = hostingView
        window.makeKeyAndOrderFront(nil)
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()
        RunLoop.main.run(
            until:
                Date(
                    timeIntervalSinceNow:
                        0.05
                )
        )
        window.displayIfNeeded()
        hostingView.layoutSubtreeIfNeeded()

        defer {
            window.contentView = nil
            window.close()
        }

        guard let source =
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide:
                    viewport.width,
                pixelsHigh:
                    viewport.height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName:
                    .deviceRGB,
                bitmapFormat: [],
                bytesPerRow:
                    viewport.width * 4,
                bitsPerPixel: 32
            )
        else {
            throw BlueMinutesRuntimeCaptureError
                .bitmapAllocationFailed
        }
        source.size = size
        hostingView.cacheDisplay(
            in: hostingView.bounds,
            to: source
        )
        guard let sourceImage =
            source.cgImage
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageCreationFailed
        }

        let normalized = try normalizedImage(
            sourceImage,
            width: viewport.width,
            height: viewport.height,
            appearance:
                descriptor.appearance
        )
        return try encodePNG(normalized)
    }

    static func validatePNG(
        _ data: Data,
        expectedViewport:
            BlueMinutesVisualViewport
    ) throws -> BlueMinutesPNGContract {
        let bytes = [UInt8](data)
        guard bytes.count >= 33,
              Array(bytes.prefix(8))
                == pngSignature
        else {
            throw BlueMinutesRuntimeCaptureError
                .malformedPNG(
                    "The PNG signature is invalid."
                )
        }

        var offset = 8
        var width: Int?
        var height: Int?
        var bitDepth: UInt8?
        var colorType: UInt8?
        var chunkNames: [String] = []
        var profilePayload: Data?
        var foundEnd = false

        while offset + 12 <= bytes.count {
            let length =
                Int(readUInt32(bytes, at: offset))
            let typeStart = offset + 4
            let dataStart = typeStart + 4
            let dataEnd = dataStart + length
            let chunkEnd = dataEnd + 4
            guard dataEnd >= dataStart,
                  chunkEnd <= bytes.count,
                  let name = String(
                    bytes:
                        bytes[typeStart..<(typeStart + 4)],
                    encoding: .ascii
                  )
            else {
                throw BlueMinutesRuntimeCaptureError
                    .malformedPNG(
                        "A PNG chunk is truncated."
                    )
            }
            chunkNames.append(name)
            let payload =
                Array(bytes[dataStart..<dataEnd])
            let expectedChecksum =
                readUInt32(
                    bytes,
                    at: dataEnd
                )
            let checksumInput =
                Data(
                    bytes[
                        typeStart..<dataEnd
                    ]
                )
            guard crc32(checksumInput)
                    == expectedChecksum
            else {
                throw BlueMinutesRuntimeCaptureError
                    .malformedPNG(
                        "A PNG chunk has an invalid CRC."
                    )
            }
            if name == "IHDR" {
                guard payload.count == 13
                else {
                    throw BlueMinutesRuntimeCaptureError
                        .malformedPNG(
                            "IHDR has an invalid length."
                        )
                }
                width = Int(
                    readUInt32(payload, at: 0)
                )
                height = Int(
                    readUInt32(payload, at: 4)
                )
                bitDepth = payload[8]
                colorType = payload[9]
            } else if name == "iCCP" {
                profilePayload =
                    Data(payload)
            }
            offset = chunkEnd
            if name == "IEND" {
                foundEnd = true
                break
            }
        }

        guard let width,
              let height,
              let bitDepth,
              let colorType
        else {
            throw BlueMinutesRuntimeCaptureError
                .malformedPNG(
                    "IHDR is missing."
                )
        }
        let imageDataChunks =
            chunkNames
            .dropFirst(2)
            .dropLast()
        guard foundEnd,
              offset == bytes.count,
              chunkNames.count >= 4,
              chunkNames.first == "IHDR",
              chunkNames.dropFirst().first
                == "iCCP",
              chunkNames.last == "IEND",
              chunkNames.filter({
                  $0 == "IHDR"
              }).count == 1,
              chunkNames.filter({
                  $0 == "iCCP"
              }).count == 1,
              !imageDataChunks.isEmpty,
              imageDataChunks.allSatisfy({
                  $0 == "IDAT"
              }),
              chunkNames.filter({
                  $0 == "IEND"
              }).count == 1
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG chunk structure is not the closed visual-proof allowlist."
                )
        }
        guard width
                == expectedViewport.width,
              height
                == expectedViewport.height
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG dimensions do not match the declared viewport."
                )
        }
        guard bitDepth == 8,
              colorType == 2
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG must be opaque 8-bit RGB color type 2."
                )
        }
        let forbidden:
            Set<String> = [
                "tIME",
                "tEXt",
                "zTXt",
                "iTXt",
                "eXIf"
            ]
        let presentForbidden =
            forbidden.intersection(
                chunkNames
            )
            .sorted()
        guard presentForbidden.isEmpty
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG contains forbidden metadata: \(presentForbidden.joined(separator: ", "))."
                )
        }
        guard let profilePayload
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG has no embedded iCCP sRGB profile."
                )
        }
        let profileData =
            try decodedICCProfile(
                profilePayload
            )
        let expectedProfile =
            try canonicalICCProfile()
        guard profileData == expectedProfile
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG iCCP payload is not the canonical sRGB profile."
                )
        }

        return BlueMinutesPNGContract(
            width: width,
            height: height,
            bitDepth: bitDepth,
            colorType: colorType,
            chunkNames: chunkNames,
            profileSHA256:
                sha256(profileData)
        )
    }

    static func compare(
        expected: Data,
        actual: Data
    ) throws -> BlueMinutesVisualComparison {
        let expectedPixels =
            try decodedPixels(expected)
        let actualPixels =
            try decodedPixels(actual)
        guard expectedPixels.width
                == actualPixels.width,
              expectedPixels.height
                == actualPixels.height
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageDimensionsDiffer
        }

        var maximumDelta: UInt8 = 0
        var changedPixelCount = 0
        let pixelCount =
            expectedPixels.width
                * expectedPixels.height
        var expectedLuminance:
            [Double] = []
        var actualLuminance:
            [Double] = []
        expectedLuminance.reserveCapacity(
            pixelCount
        )
        actualLuminance.reserveCapacity(
            pixelCount
        )

        for pixel in 0..<pixelCount {
            let base = pixel * 4
            var changed = false
            for channel in 0..<3 {
                let difference =
                    abs(
                        Int(
                            expectedPixels
                                .bytes[
                                    base
                                        + channel
                                ]
                        )
                            - Int(
                                actualPixels
                                    .bytes[
                                        base
                                            + channel
                                    ]
                            )
                    )
                maximumDelta = max(
                    maximumDelta,
                    UInt8(difference)
                )
                changed = changed
                    || difference > 0
            }
            if changed {
                changedPixelCount += 1
            }
            expectedLuminance.append(
                luminance(
                    expectedPixels.bytes,
                    at: base
                )
            )
            actualLuminance.append(
                luminance(
                    actualPixels.bytes,
                    at: base
                )
            )
        }

        return BlueMinutesVisualComparison(
            maximumChannelDelta:
                maximumDelta,
            changedPixelRatio:
                pixelCount == 0
                    ? 0
                    : Double(
                        changedPixelCount
                    )
                        / Double(
                            pixelCount
                        ),
            luminanceSSIM:
                globalSSIM(
                    expectedLuminance,
                    actualLuminance
                )
        )
    }

    static func sha256(
        _ data: Data
    ) -> String {
        SHA256.hash(data: data)
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
    }

    static func pixelSHA256(
        _ data: Data
    ) throws -> String {
        let pixels =
            try decodedPixels(data)
        return sha256(
            Data(pixels.bytes)
        )
    }

    static func differenceImage(
        expected: Data,
        actual: Data
    ) throws -> Data {
        let expectedPixels =
            try decodedPixels(expected)
        let actualPixels =
            try decodedPixels(actual)
        guard expectedPixels.width
                == actualPixels.width,
              expectedPixels.height
                == actualPixels.height
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageDimensionsDiffer
        }
        let width = expectedPixels.width
        let height = expectedPixels.height
        var bytes = [UInt8](
            repeating: 255,
            count: width * height * 4
        )
        for pixel in 0..<(width * height) {
            let base = pixel * 4
            for channel in 0..<3 {
                let difference =
                    abs(
                        Int(
                            expectedPixels
                                .bytes[
                                    base + channel
                                ]
                        )
                            - Int(
                                actualPixels
                                    .bytes[
                                        base + channel
                                    ]
                            )
                    )
                bytes[base + channel] =
                    UInt8(
                        min(
                            255,
                            difference * 4
                        )
                    )
            }
        }
        guard let colorSpace =
            CGColorSpace(
                name:
                    CGColorSpace.sRGB
            ),
              let context =
              CGContext(
                  data: &bytes,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow:
                      width * 4,
                  space: colorSpace,
                  bitmapInfo:
                      CGBitmapInfo
                      .byteOrder32Big
                      .rawValue
                      | CGImageAlphaInfo
                      .noneSkipLast
                      .rawValue
              ),
              let image =
              context.makeImage()
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageCreationFailed
        }
        return try encodePNG(image)
    }

    static func contractFailureDifferenceImage(
        viewport:
            BlueMinutesVisualViewport
    ) throws -> Data {
        guard viewport.width > 0,
              viewport.height > 0
        else {
            throw BlueMinutesRuntimeCaptureError
                .invalidViewport
        }
        let width = viewport.width
        let height = viewport.height
        var bytes = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        for y in 0..<height {
            for x in 0..<width {
                let base =
                    (y * width + x) * 4
                let highlighted =
                    ((x / 16) + (y / 16))
                    .isMultiple(of: 2)
                bytes[base] =
                    highlighted
                    ? 255
                    : 32
                bytes[base + 1] = 0
                bytes[base + 2] =
                    highlighted
                    ? 255
                    : 32
                bytes[base + 3] = 255
            }
        }
        guard let colorSpace =
            CGColorSpace(
                name:
                    CGColorSpace.sRGB
            ),
              let context =
              CGContext(
                  data: &bytes,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow:
                      width * 4,
                  space: colorSpace,
                  bitmapInfo:
                      CGBitmapInfo
                      .byteOrder32Big
                      .rawValue
                      | CGImageAlphaInfo
                      .noneSkipLast
                      .rawValue
              ),
              let image =
              context.makeImage()
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageCreationFailed
        }
        return try encodePNG(image)
    }

    private static func normalizedImage(
        _ source: CGImage,
        width: Int,
        height: Int,
        appearance:
            BlueMinutesVisualAppearance
    ) throws -> CGImage {
        let bytesPerRow = width * 4
        var bytes = [UInt8](
            repeating: 0,
            count: bytesPerRow * height
        )
        guard let colorSpace =
            CGColorSpace(
                name:
                    CGColorSpace.sRGB
            )
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageCreationFailed
        }
        let bitmapInfo =
            CGBitmapInfo.byteOrder32Big
                .rawValue
                | CGImageAlphaInfo
                .noneSkipLast.rawValue
        guard let context =
            CGContext(
                data: &bytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageCreationFailed
        }
        context.setFillColor(
            appearance == .dark
                ? NSColor.black.cgColor
                : NSColor.white.cgColor
        )
        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )
        context.interpolationQuality =
            .none
        context.draw(
            source,
            in: CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )
        guard let image =
            context.makeImage()
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageCreationFailed
        }
        return image
    }

    private static func encodePNG(
        _ image: CGImage
    ) throws -> Data {
        let output = NSMutableData()
        guard let destination =
            CGImageDestinationCreateWithData(
                output,
                UTType.png.identifier
                    as CFString,
                1,
                nil
            )
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngEncodingFailed
        }
        let properties:
            [CFString: Any] = [
                kCGImagePropertyProfileName:
                    "sRGB IEC61966-2.1",
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyPNGsRGBIntent:
                        0
                ]
            ]
        CGImageDestinationAddImage(
            destination,
            image,
            properties as CFDictionary
        )
        guard CGImageDestinationFinalize(
            destination
        )
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngEncodingFailed
        }
        return try removingForbiddenMetadata(
            output as Data
        )
    }

    private static func removingForbiddenMetadata(
        _ data: Data
    ) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
              Array(bytes.prefix(8))
                == pngSignature
        else {
            throw BlueMinutesRuntimeCaptureError
                .malformedPNG(
                    "The encoded PNG signature is invalid."
                )
        }
        let forbidden:
            Set<String> = [
                "tIME",
                "tEXt",
                "zTXt",
                "iTXt",
                "eXIf",
                "sRGB",
                "iCCP"
            ]
        var output =
            Data(pngSignature)
        var offset = 8
        var foundEnd = false
        var insertedProfile = false
        while offset + 12 <= bytes.count {
            let length =
                Int(readUInt32(bytes, at: offset))
            let typeStart = offset + 4
            let chunkEnd =
                typeStart + 4 + length + 4
            guard chunkEnd >= typeStart,
                  chunkEnd <= bytes.count,
                  let name = String(
                    bytes:
                        bytes[
                            typeStart..<(typeStart + 4)
                        ],
                    encoding: .ascii
                  )
            else {
                throw BlueMinutesRuntimeCaptureError
                    .malformedPNG(
                        "The encoded PNG contains a truncated chunk."
                    )
            }
            if !forbidden.contains(name) {
                output.append(
                    contentsOf:
                        bytes[offset..<chunkEnd]
                )
            }
            if name == "IHDR" {
                output.append(
                    try canonicalICCProfileChunk()
                )
                insertedProfile = true
            }
            offset = chunkEnd
            if name == "IEND" {
                foundEnd = true
                break
            }
        }
        guard foundEnd,
              insertedProfile
        else {
            throw BlueMinutesRuntimeCaptureError
                .malformedPNG(
                    "The encoded PNG has no complete IHDR/IEND structure."
                )
        }
        return output
    }

    private static func canonicalICCProfileChunk()
        throws -> Data
    {
        let profile =
            try canonicalICCProfile()
        let compressed =
            try zlibData(
                compressing: profile
            )
        var payload =
            Data(
                "sRGB IEC61966-2.1"
                    .utf8
            )
        payload.append(0)
        payload.append(0)
        payload.append(compressed)
        return pngChunk(
            name: "iCCP",
            payload: payload
        )
    }

    private static func canonicalICCProfile()
        throws -> Data
    {
        guard let colorSpace =
            CGColorSpace(
                name:
                    CGColorSpace.sRGB
            ),
              let profile =
              colorSpace.copyICCData()
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageCreationFailed
        }
        return profile as Data
    }

    private static func decodedICCProfile(
        _ payload: Data
    ) throws -> Data {
        let bytes = [UInt8](payload)
        guard let nameEnd =
            bytes.firstIndex(of: 0),
              nameEnd > 0,
              nameEnd <= 79,
              nameEnd + 2 <= bytes.count,
              bytes[nameEnd + 1] == 0,
              String(
                  bytes:
                      bytes[0..<nameEnd],
                  encoding: .isoLatin1
              )
                == "sRGB IEC61966-2.1"
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG iCCP payload is malformed."
                )
        }
        let compressed =
            Data(
                bytes[
                    (nameEnd + 2)..<bytes.count
                ]
            )
        return try zlibDecompressed(
            compressed
        )
    }

    private static func zlibData(
        compressing data: Data
    ) throws -> Data {
        let rawDeflate =
            try (
                data as NSData
            )
            .compressed(
                using: .zlib
            ) as Data
        var result = Data([
            0x78,
            0x9c
        ])
        result.append(rawDeflate)
        appendUInt32(
            adler32(data),
            to: &result
        )
        return result
    }

    private static func zlibDecompressed(
        _ data: Data
    ) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 6,
              bytes[0] & 0x0f == 8,
              bytes[0] >> 4 <= 7,
              (
                  (
                      UInt16(bytes[0]) << 8
                  )
                      | UInt16(bytes[1])
              ) % 31 == 0,
              bytes[1] & 0x20 == 0
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG iCCP profile has an invalid zlib header."
                )
        }
        let checksumOffset =
            bytes.count - 4
        let rawDeflate =
            Data(
                bytes[2..<checksumOffset]
            )
        let decompressed: Data
        do {
            decompressed =
                try (
                    rawDeflate as NSData
                )
                .decompressed(
                    using: .zlib
                ) as Data
        } catch {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG iCCP profile cannot be decompressed."
                )
        }
        guard adler32(decompressed)
                == readUInt32(
                    bytes,
                    at: checksumOffset
                )
        else {
            throw BlueMinutesRuntimeCaptureError
                .pngContractViolation(
                    "The PNG iCCP profile has an invalid Adler-32 checksum."
                )
        }
        return decompressed
    }

    private static func pngChunk(
        name: String,
        payload: Data
    ) -> Data {
        let type = Data(name.utf8)
        var chunk = Data()
        appendUInt32(
            UInt32(payload.count),
            to: &chunk
        )
        chunk.append(type)
        chunk.append(payload)
        var checksumInput = Data()
        checksumInput.append(type)
        checksumInput.append(payload)
        appendUInt32(
            crc32(checksumInput),
            to: &chunk
        )
        return chunk
    }

    private static func appendUInt32(
        _ value: UInt32,
        to data: inout Data
    ) {
        data.append(
            UInt8(
                (value >> 24) & 0xff
            )
        )
        data.append(
            UInt8(
                (value >> 16) & 0xff
            )
        )
        data.append(
            UInt8(
                (value >> 8) & 0xff
            )
        )
        data.append(
            UInt8(value & 0xff)
        )
    }

    private static func crc32(
        _ data: Data
    ) -> UInt32 {
        var checksum =
            UInt32.max
        for byte in data {
            checksum ^= UInt32(byte)
            for _ in 0..<8 {
                if checksum & 1 == 1 {
                    checksum =
                        (checksum >> 1)
                            ^ 0xedb8_8320
                } else {
                    checksum >>= 1
                }
            }
        }
        return checksum ^ UInt32.max
    }

    private static func adler32(
        _ data: Data
    ) -> UInt32 {
        let modulus: UInt32 = 65_521
        var first: UInt32 = 1
        var second: UInt32 = 0
        for byte in data {
            first =
                (
                    first
                        + UInt32(byte)
                ) % modulus
            second =
                (
                    second
                        + first
                ) % modulus
        }
        return (
            second << 16
        ) | first
    }

    private static func decodedPixels(
        _ data: Data
    ) throws -> (
        width: Int,
        height: Int,
        bytes: [UInt8]
    ) {
        guard let source =
            CGImageSourceCreateWithData(
                data as CFData,
                nil
            ),
              let image =
              CGImageSourceCreateImageAtIndex(
                  source,
                  0,
                  nil
              )
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageDecodeFailed
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        guard let colorSpace =
            CGColorSpace(
                name:
                    CGColorSpace.sRGB
            ),
              let context =
              CGContext(
                  data: &bytes,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow:
                      width * 4,
                  space: colorSpace,
                  bitmapInfo:
                      CGBitmapInfo
                      .byteOrder32Big
                      .rawValue
                      | CGImageAlphaInfo
                      .noneSkipLast
                      .rawValue
              )
        else {
            throw BlueMinutesRuntimeCaptureError
                .imageDecodeFailed
        }
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: width,
                height: height
            )
        )
        return (
            width,
            height,
            bytes
        )
    }

    private static func luminance(
        _ bytes: [UInt8],
        at base: Int
    ) -> Double {
        0.2126
            * Double(bytes[base])
            + 0.7152
            * Double(bytes[base + 1])
            + 0.0722
            * Double(bytes[base + 2])
    }

    private static func globalSSIM(
        _ first: [Double],
        _ second: [Double]
    ) -> Double {
        guard !first.isEmpty,
              first.count == second.count
        else { return 1 }
        let count = Double(first.count)
        let firstMean =
            first.reduce(0, +) / count
        let secondMean =
            second.reduce(0, +) / count
        var firstVariance = 0.0
        var secondVariance = 0.0
        var covariance = 0.0
        for index in first.indices {
            let firstDelta =
                first[index] - firstMean
            let secondDelta =
                second[index] - secondMean
            firstVariance +=
                firstDelta * firstDelta
            secondVariance +=
                secondDelta * secondDelta
            covariance +=
                firstDelta * secondDelta
        }
        let denominator =
            max(count - 1, 1)
        firstVariance /= denominator
        secondVariance /= denominator
        covariance /= denominator
        let c1: Double =
            pow(0.01 * 255.0, 2.0)
        let c2: Double =
            pow(0.03 * 255.0, 2.0)
        return (
            (2 * firstMean * secondMean + c1)
                * (2 * covariance + c2)
        ) / (
            (firstMean * firstMean
                + secondMean * secondMean
                + c1)
                * (firstVariance
                    + secondVariance
                    + c2)
        )
    }

    private static func readUInt32(
        _ bytes: [UInt8],
        at offset: Int
    ) -> UInt32 {
        UInt32(bytes[offset]) << 24
            | UInt32(bytes[offset + 1])
                << 16
            | UInt32(bytes[offset + 2])
                << 8
            | UInt32(bytes[offset + 3])
    }
}

@MainActor
private extension BlueMinutesRuntimeCapture {
    static func validateAccessibilityEnvironment(
        _ accessibility:
            BlueMinutesVisualAccessibility
    ) throws {
        let workspace =
            NSWorkspace.shared
        let mismatches:
            [String] = [
                mismatch(
                    name:
                        "reduceTransparency",
                    expected:
                        accessibility
                        .reduceTransparency,
                    actual:
                        workspace
                        .accessibilityDisplayShouldReduceTransparency
                ),
                mismatch(
                    name:
                        "differentiateWithoutColor",
                    expected:
                        accessibility
                        .differentiateWithoutColor,
                    actual:
                        workspace
                        .accessibilityDisplayShouldDifferentiateWithoutColor
                ),
                mismatch(
                    name: "reduceMotion",
                    expected:
                        accessibility
                        .reduceMotion,
                    actual:
                        workspace
                        .accessibilityDisplayShouldReduceMotion
                )
            ]
            .compactMap { $0 }
        guard mismatches.isEmpty
        else {
            throw BlueMinutesRuntimeCaptureError
                .accessibilityEnvironmentMismatch(
                    mismatches.joined(
                        separator: ", "
                    )
                )
        }
    }

    static func mismatch(
        name: String,
        expected: Bool,
        actual: Bool
    ) -> String? {
        guard expected != actual
        else { return nil }
        return "\(name) expected \(expected) but observed \(actual)"
    }

    static func visualAppearance(
        appearance:
            BlueMinutesVisualAppearance,
        increaseContrast: Bool
    ) -> NSAppearance? {
        let name:
            NSAppearance.Name
        switch (
            appearance,
            increaseContrast
        ) {
        case (.light, false):
            name = .aqua
        case (.dark, false):
            name = .darkAqua
        case (.light, true):
            name =
                .accessibilityHighContrastAqua
        case (.dark, true):
            name =
                .accessibilityHighContrastDarkAqua
        }
        return NSAppearance(named: name)
    }
}

private struct BlueMinutesVisualCaptureRoot:
    View
{
    let appearance:
        BlueMinutesVisualAppearance
    let accessibility:
        BlueMinutesVisualAccessibility
    let locale: String
    let timeZone: TimeZone
    let content: AnyView

    var body: some View {
        content
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
            .environment(
                \.colorScheme,
                appearance == .dark
                    ? .dark
                    : .light
            )
            .dynamicTypeSize(
                accessibility.largerText
                    ? .accessibility2
                    : .large
            )
            .tint(.blue)
            .environment(
                \.locale,
                Locale(
                    identifier: locale
                )
            )
            .environment(
                \.timeZone,
                timeZone
            )
            .transaction {
                $0.animation = nil
            }
    }
}
