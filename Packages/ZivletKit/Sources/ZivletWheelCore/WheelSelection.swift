import Foundation
import ZivletCore

/// What a drop on a slice asks for. M2 logs it; M3 turns it into a job request.
public struct WheelSelection: Sendable, Equatable, Codable {
    public let mode: WheelMode
    public let target: SliceTarget
    public let urls: [URL]

    public init(mode: WheelMode, target: SliceTarget, urls: [URL]) {
        self.mode = mode
        self.target = target
        self.urls = urls
    }

    /// One line for logs and the dev HUD, for example "Convert → JPG · 2 items". Contains no paths.
    public func summary(registry: FormatRegistry = .standard, tools: ToolCatalog = .standard) -> String {
        let count = urls.count == 1 ? "1 item" : "\(urls.count) items"
        return "\(Self.title(mode)) → \(label(registry: registry, tools: tools)) · \(count)"
    }

    private func label(registry: FormatRegistry, tools: ToolCatalog) -> String {
        switch target {
        case .convert(let format): registry.format(format).wheelLabel
        case .tool(let tool): tools.spec(tool).wheelLabel
        case .action(let action): action.wheelLabel
        }
    }

    private static func title(_ mode: WheelMode) -> String {
        switch mode {
        case .convert: "Convert"
        case .tools: "Tools"
        case .actions: "Actions"
        }
    }
}
