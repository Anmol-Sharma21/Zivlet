import SwiftUI
import ZivletNotch
import ZivletShelfCore

/// The bottom row (19c D-BL5, §4.1): five icon buttons; while busy, the progress bar, the percent and Cancel; while
/// confirming, one question line with two buttons.
struct BoxActionBar: View {
    let model: BoxViewModel
    let press: (BoxPress) -> Void

    var body: some View {
        Group {
            switch model.presentation.overlay {
            case .busy(_, let fraction): BoxBusyLine(fraction: fraction, press: press)
            case .confirm(let kind): BoxConfirmLine(kind: kind, press: press)
            case .dropTarget, nil: buttons
            }
        }
        .frame(height: BoxLook.Panel.barHeight)
    }

    private var buttons: some View {
        HStack(spacing: IslandContentLook.Spacing.xs) {
            ForEach(BoxPress.bar, id: \.self.menuID) { BoxIconButton(press: $0, action: press) }
            Spacer(minLength: 0)
        }
    }
}

/// Busy: a bar with the percent right of it, then Cancel.
struct BoxBusyLine: View {
    let fraction: Double
    let press: (BoxPress) -> Void

    var body: some View {
        HStack(spacing: IslandContentLook.Spacing.s) {
            ProgressBarShape(fraction: fraction)
                .frame(height: IslandContentLook.Bar.height)
            Text(BoxCopy.percent(fraction))
                .font(IslandContentLook.TypeStyle.secondary)
                .foregroundStyle(IslandInk.secondary)
                .fixedSize()
            BoxIconButton(press: .cancelBusy, action: press)
        }
    }
}

/// The island's bar: white over its 0.3 track, no border.
struct ProgressBarShape: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(IslandInk.track)
                Capsule().fill(IslandInk.primary).frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .accessibilityElement()
        .accessibilityValue(BoxCopy.percent(fraction))
    }
}

/// Confirm (19c D-BL9): "Move 3 to Trash?" with the action's own symbol and Cancel; no alert.
struct BoxConfirmLine: View {
    let kind: ConfirmKind
    let press: (BoxPress) -> Void

    private var symbol: String {
        switch kind {
        case .trash, .emptyStorage: BoxSymbols.trash
        case .clear: BoxSymbols.clear
        }
    }

    private var title: String {
        switch kind {
        case .trash: BoxCopy.title(.trash)
        case .clear: BoxCopy.title(.clear)
        case .emptyStorage: BoxCopy.title(.emptyStorage)
        }
    }

    var body: some View {
        HStack(spacing: IslandContentLook.Spacing.xs) {
            Text(BoxCopy.confirm(kind))
                .font(IslandContentLook.TypeStyle.primary)
                .foregroundStyle(IslandInk.primary)
                .lineLimit(1)
            Spacer(minLength: IslandContentLook.Spacing.s)
            BoxIconButton(press: .confirm(true), symbol: symbol, title: title, action: press)
            BoxIconButton(press: .confirm(false), action: press)
        }
    }
}
