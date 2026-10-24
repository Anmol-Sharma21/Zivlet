import SwiftUI
import ZivletCore
import ZivletRuntime

/// The island's working card (19b §5, F2): two rows. Row 1: the target's family symbol, "holiday.mov → MP4" (the name
/// gives way) and the percent. Row 2: a 3 pt white bar on a white 0.3 track (or the bytes written while the length is
/// unknown), the short time left and Cancel. No accent colour; the spoken value stays the board's.
struct NotchWorkingCard: View {
    /// The card's buttons: Cancel only.
    static let presses: [NotchHUD.Press] = [.cancel]

    let snapshot: BatchSnapshot
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NotchLook.Spacing.xs) {
            HStack(spacing: NotchLook.Spacing.s) {
                NotchFamilySymbol(family: Self.family(snapshot))
                Text(Self.title(for: snapshot)).font(NotchLook.TypeStyle.primary).foregroundStyle(NotchInk.primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: NotchLook.Spacing.s)
                if let percent = Self.percent(snapshot) { secondary(percent) }
            }
            HStack(spacing: NotchLook.Spacing.s) {
                progress
                ForEach(Self.details(snapshot), id: \.self) { secondary($0) }
                NotchIconButton(press: .cancel, action: cancel)
            }
        }
    }

    @ViewBuilder private var progress: some View {
        if let fraction = Self.fraction(snapshot) {
            NotchBar(progress: VisibleProgress(fraction, steps: NotchHUDBoard.barSteps))
        } else {
            Spacer(minLength: 0)
        }
    }

    private func secondary(_ text: String) -> some View {
        Text(text).font(NotchLook.TypeStyle.secondary).foregroundStyle(NotchInk.secondary).lineLimit(1)
            .fixedSize()
    }

    /// "holiday.mov → MP4".
    static func title(for snapshot: BatchSnapshot) -> String { NotchHUDCopy.workingTitle(snapshot) }

    static func family(_ snapshot: BatchSnapshot, registry: FormatRegistry = .standard) -> FormatFamily {
        registry.format(snapshot.target).family
    }

    static func fraction(_ snapshot: BatchSnapshot) -> Double? {
        snapshot.isIndeterminate ? nil : snapshot.fraction
    }

    static func percent(_ snapshot: BatchSnapshot) -> String? { NotchHUDCopy.percent(snapshot) }

    /// Right of the bar: "2 of 5" for a batch, "12.4 MB written" while the length is unknown, the short time left.
    static func details(_ snapshot: BatchSnapshot) -> [String] {
        let progress = snapshot.currentProgress
        var parts: [String] = []
        if let current = snapshot.current, snapshot.items.count > 1 {
            parts.append("\(current.index + 1) of \(snapshot.items.count)")
        }
        if snapshot.isIndeterminate, let bytes = progress?.bytesWritten {
            parts.append("\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) written")
        }
        if let eta = progress?.eta { parts.append(HUDCopy.shortTimeLeft(eta)) }
        return parts
    }
}

/// The working card's bar: a 3 pt capsule, white on white 0.3, one visible step at a time (19b §3.3, §6.2).
struct NotchBar: View {
    let progress: VisibleProgress

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(NotchInk.trackOpacity))
                Capsule().fill(NotchInk.primary).frame(width: proxy.size.width * progress.fraction)
            }
        }
        .frame(height: NotchLook.Bar.height)
        .frame(maxWidth: .infinity)
    }
}
