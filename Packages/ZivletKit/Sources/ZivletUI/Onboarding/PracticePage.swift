import AppKit
import SwiftUI
import ZivletCore

/// Pages 2 and 3: the real trigger and wheel, tried on a sample file (03b §8.2).
struct PracticePage: View {
    let model: OnboardingModel
    let modes: [WheelMode]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(title: Self.title(modes), lead: Self.lead(modes))
            HStack(alignment: .top, spacing: 28) {
                SampleTile(url: model.sampleURL, reveal: model.commands.revealSample)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(modes, id: \.self) { mode in
                        HStack(spacing: 12) {
                            KeyCap(symbol: model.keyCap(for: mode))
                            Text(Self.step(mode))
                        }
                    }
                    if let message = model.practiceMessage {
                        Text(message).font(.headline).padding(.top, 6)
                    }
                }
            }
        }
    }

    static func title(_ modes: [WheelMode]) -> String {
        modes == [.convert] ? "Try converting" : "Tools and actions"
    }

    static func lead(_ modes: [WheelMode]) -> String {
        modes == [.convert]
            ? "Start dragging the sample, tap the key once without letting go, then drop on a slice."
            : "The same gesture with another key opens the other wheels."
    }

    static func step(_ mode: WheelMode) -> String {
        switch mode {
        case .convert: "Convert: turn the file into another format."
        case .tools: "Tools: resize, compress and more."
        case .actions: "Actions: copy, move, AirDrop or open in Terminal."
        }
    }
}

/// The practice file as a thumbnail that can be dragged, with a way to find it in Finder.
struct SampleTile: View {
    let url: URL?
    let reveal: (URL) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 192)
                    .clipShape(.rect(cornerRadius: 10))
                    .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                    .accessibilityLabel("Practice file. Drag it to try the wheel.")
                Button("Show in Finder") { reveal(url) }.buttonStyle(.link)
            } else {
                Text("Use any file from Finder.").foregroundStyle(.secondary).frame(width: 192)
            }
        }
    }
}
