import Foundation
import ZivletCore

// Debug builds only: Release must not ship a way to run an action without a drop.
#if DEBUG
    public enum DemoActionError: Error, Equatable, Sendable {
        case missingValue(String)
        case notAbsolute(String)
        case unknownAction(String)
        /// AirDrop, Move and Float need someone at the Mac (a sheet, a panel, a shelf).
        case needsAPerson(String)
    }

    /// DEBUG launch arguments that run an action without a drag:
    /// `-ZivletDemoAction /abs/path <copyTo|copyFilePath|openInTerminal> [-ZivletDemoOption YES]`.
    public struct DemoAction: Sendable, Equatable {
        public static let actionFlag = "-ZivletDemoAction"
        public static let optionFlag = "-ZivletDemoOption"
        static let unattended: Set<ActionID> = [.copyTo, .copyFilePath, .openInTerminal]

        public let url: URL
        public let action: ActionID
        public let optionHeld: Bool

        /// Nil when the action flag is absent.
        public static func parse(arguments: [String]) throws(DemoActionError) -> DemoAction? {
            guard let index = arguments.firstIndex(of: actionFlag) else { return nil }
            guard arguments.indices.contains(index + 2) else { throw .missingValue(actionFlag) }
            let path = arguments[index + 1]
            guard path.hasPrefix("/") else { throw .notAbsolute(path) }
            let name = arguments[index + 2]
            guard let action = ActionID(rawValue: name) else { throw .unknownAction(name) }
            guard unattended.contains(action) else { throw .needsAPerson(name) }
            let held =
                arguments.firstIndex(of: optionFlag).flatMap {
                    arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
                } == "YES"
            return DemoAction(url: URL(fileURLWithPath: path), action: action, optionHeld: held)
        }
    }
#endif
