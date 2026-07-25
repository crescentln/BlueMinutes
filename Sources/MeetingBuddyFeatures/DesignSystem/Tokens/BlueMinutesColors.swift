import AppKit
import SwiftUI

@MainActor
enum BlueMinutesColors {
    static var canvas: Color {
        Color(nsColor: canvasNSColor)
    }

    static var recording: Color {
        Color(nsColor: recordingNSColor)
    }

    static var recordingSurface: Color {
        recording.opacity(0.12)
    }

    static var error: Color {
        Color(nsColor: errorNSColor)
    }

    static var canvasNSColor: NSColor {
        .textBackgroundColor
    }

    static var recordingNSColor: NSColor {
        .systemRed
    }

    static var errorNSColor: NSColor {
        .systemRed
    }
}
