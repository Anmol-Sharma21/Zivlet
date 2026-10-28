import Observation
import SwiftUI
import ZivletNotch
import ZivletNotchCore

/// What the tool window draws: its model, the tool's content and the finish. The window owns it; closing the window
/// empties it, so nothing a tool showed (a password field's text included) outlives the window.
@Observable
public final class ToolWindowState {
    public internal(set) var model: ToolWindowModel?
    public internal(set) var content: AnyView?
    public internal(set) var finish: IslandFinish = .glass(band: 0)
    @ObservationIgnored var apply: () -> Void = {}
    @ObservationIgnored var cancel: () -> Void = {}

    init() {}
}

/// The tool window's chrome (P2-30, plan 20b A2; OWN-UI-1, 19b, 19c): the Drop Box's finish (glass under the black
/// scrim, radius 24, dark always; solid grey under Reduce Transparency, plus a white outline under Increase Contrast),
/// a header with the tool's symbol, its name and the file line, the tool's own content, the reason Apply is off, and
/// Cancel and Apply. No title bar and no dividers; two text styles in white and white at 0.8.
struct ToolWindowView: View {
    static let width: CGFloat = 340
    static let radius: CGFloat = 24
    static let reasonSymbol = "info.circle"

    let state: ToolWindowState

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Self.radius, style: .continuous) }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.m) {
            if let model = state.model {
                ToolWindowHeader(model: model)
                state.content
                ToolWindowFooter(model: model, apply: state.apply, cancel: state.cancel)
            }
        }
        .padding(IslandContentLook.Spacing.l)
        .frame(width: Self.width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(ToolWindowSurface(finish: state.finish, shape: shape))
        .clipShape(shape)
        .environment(\.colorScheme, .dark)
    }

    /// Apply's VoiceOver label: its own label, and when it is off, why ("Lock, unavailable: Passwords don't match").
    static func applyLabel(_ apply: ApplyState) -> String {
        guard let reason = apply.reason else { return apply.label }
        return "\(apply.label), unavailable: \(reason)"
    }
}

/// The finish in the window's shape, with the Increase Contrast outline inside its edge.
struct ToolWindowSurface: View {
    let finish: IslandFinish
    let shape: RoundedRectangle

    var body: some View {
        ZStack {
            SurfaceFill(finish: finish, shape: shape)
            if finish.outlined {
                shape.strokeBorder(Color.white.opacity(IslandLook.Outline.opacity), lineWidth: IslandLook.Outline.width)
            }
        }
    }
}

/// The tool's symbol, its name and the file line.
struct ToolWindowHeader: View {
    let model: ToolWindowModel

    var body: some View {
        HStack(spacing: IslandContentLook.Spacing.s) {
            Image(systemName: model.symbol)
                .font(IslandContentLook.Symbol.toast)
                .foregroundStyle(IslandInk.primary)
                .frame(width: IslandContentLook.Symbol.buttonSide, height: IslandContentLook.Symbol.buttonSide)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IslandContentLook.Spacing.xs) {
                Text(model.title)
                    .font(IslandContentLook.TypeStyle.primary)
                    .foregroundStyle(IslandInk.primary)
                    .accessibilityAddTraits(.isHeader)
                if !model.fileLine.isEmpty {
                    Text(model.fileLine)
                        .font(IslandContentLook.TypeStyle.secondary)
                        .foregroundStyle(IslandInk.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}

/// The reason Apply is off (or the working spinner), then Cancel (Esc) and Apply (Return).
struct ToolWindowFooter: View {
    let model: ToolWindowModel
    let apply: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IslandContentLook.Spacing.s) {
            if model.isBusy {
                ProgressView().controlSize(.small)
            } else if let reason = model.apply.reason {
                Label(reason, systemImage: ToolWindowView.reasonSymbol)
                    .font(IslandContentLook.TypeStyle.secondary)
                    .foregroundStyle(IslandInk.secondary)
                    .accessibilityHidden(true)  // Apply's own label carries it
            }
            HStack(spacing: IslandContentLook.Spacing.s) {
                Spacer(minLength: 0)
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                // No accent fill (the island's ink has none, 19b D-NL11): white on glass holds its contrast where
                // white on the system blue would not; the weight marks it as the default button.
                Button(action: apply) { Text(model.apply.label).fontWeight(.semibold) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glass)
                    .disabled(!model.canApply)
                    .accessibilityLabel(ToolWindowView.applyLabel(model.apply))
            }
        }
    }
}
