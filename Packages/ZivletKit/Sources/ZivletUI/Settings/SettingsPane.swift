import SwiftUI

/// The Phase 1 panes (03b §8.1). Formats, Tools and Keyboard & Automation arrive with P3-32.
public enum SettingsPane: String, CaseIterable, Sendable {
    case general, updates, advanced

    static let width: CGFloat = 520

    public var title: String {
        switch self {
        case .general: "General"
        case .updates: "Updates"
        case .advanced: "Advanced"
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .updates: "arrow.triangle.2.circlepath"
        case .advanced: "wrench.and.screwdriver"
        }
    }

    var height: CGFloat {
        switch self {
        case .general: 640
        case .updates: 260
        case .advanced: 300
        }
    }

    #if DEBUG
        public static let demoFlag = "-ZivletDemoSettings"

        /// DEBUG: `-ZivletDemoSettings general|updates|advanced` opens that pane at launch (screenshots); nil when the
        /// flag is absent or names no pane.
        public static func demo(arguments: [String]) -> SettingsPane? {
            guard let index = arguments.firstIndex(of: demoFlag), index + 1 < arguments.count else { return nil }
            return SettingsPane(rawValue: arguments[index + 1])
        }
    #endif

    func view(model: SettingsModel) -> AnyView {
        let content: AnyView =
            switch self {
            case .general: AnyView(GeneralPane(model: model))
            case .updates: AnyView(UpdatesPane(model: model))
            case .advanced: AnyView(AdvancedPane(model: model))
            }
        return AnyView(content.formStyle(.grouped).frame(width: Self.width, height: height))
    }
}
