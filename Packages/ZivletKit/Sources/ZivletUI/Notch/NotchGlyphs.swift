import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The source file's icon in the tab, or an action's icon.
struct NotchIcon: View {
    let icon: TabContent.Icon

    var body: some View {
        switch icon {
        case .file(let name):
            Image(nsImage: Self.image(for: name)).resizable().interpolation(.high)
                .frame(width: NotchInk.glyphSide + 2, height: NotchInk.glyphSide + 2)
        case .action:
            NotchSymbol(name: NotchSymbol.action)
        }
    }

    /// The system icon for the name's type; a name without a known extension gets the generic document icon. One
    /// image per type: the tab redraws with every visible progress step, and a new image each time would make
    /// SwiftUI draw the icon again as well.
    static func image(for name: String) -> NSImage {
        let type = UTType(filenameExtension: (name as NSString).pathExtension) ?? .data
        if let known = icons[type] { return known }
        let icon = NSWorkspace.shared.icon(for: type)
        icons[type] = icon
        return icon
    }

    /// Icons already asked for, per type; main-actor state, a few entries at most.
    private static var icons: [UTType: NSImage] = [:]
}

/// The progress ring (design/19 §5.5): fill white, track white at 0.4, so it meets the 3:1 of WCAG 1.4.11.
struct NotchRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(NotchInk.track, lineWidth: NotchInk.ringLineWidth)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(NotchInk.primary, style: StrokeStyle(lineWidth: NotchInk.ringLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: NotchInk.glyphSide, height: NotchInk.glyphSide)
    }
}

/// The stepped glyph of a job of unknown length (D-N7): a quarter arc that moves one of eight steps at a time, so
/// it redraws at most four times a second instead of spinning.
struct NotchSteps: View {
    static let positions = 8
    let step: Int

    var body: some View {
        ZStack {
            Circle().stroke(NotchInk.track, lineWidth: NotchInk.ringLineWidth)
            Circle().trim(from: 0, to: 0.25)
                .stroke(NotchInk.primary, style: StrokeStyle(lineWidth: NotchInk.ringLineWidth, lineCap: .round))
                .rotationEffect(.degrees(Double(step % Self.positions) * 360 / Double(Self.positions) - 90))
        }
        .frame(width: NotchInk.glyphSide, height: NotchInk.glyphSide)
    }
}

/// The right end of the tab: the error glyph when anything failed (a shape, not colour alone), else the ring, the
/// stepped glyph or a check mark.
struct NotchStatusGlyph: View {
    let tab: TabContent

    var body: some View {
        if tab.failed {
            NotchSymbol(name: NotchSymbol.failed)
        } else {
            switch tab.ring {
            case .fraction(let value): NotchRing(fraction: value)
            case .step(let step): NotchSteps(step: step)
            case .done: NotchSymbol(name: NotchSymbol.saved)
            }
        }
    }
}

/// One of the island's SF Symbols at glyph size, white.
struct NotchSymbol: View {
    static let saved = "checkmark.circle.fill"
    static let failed = "exclamationmark.triangle.fill"
    static let action = "doc.on.doc"

    let name: String

    var body: some View {
        Image(systemName: name).font(.system(size: NotchInk.glyphSide - 1, weight: .semibold))
            .foregroundStyle(NotchInk.primary)
            .frame(width: NotchInk.glyphSide + 2, height: NotchInk.glyphSide + 2)
    }

    static func name(for glyph: ToastGlyph) -> String {
        switch glyph {
        case .saved: saved
        case .failed: failed
        case .action: action
        }
    }
}
