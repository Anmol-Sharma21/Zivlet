import Foundation
import ZivletCore

// Debug builds only: Release must not ship a way to start a conversion without a drop.
#if DEBUG
    public enum DemoConversionError: Error, Equatable, Sendable {
        case missingValue(String)
        case notAbsolute(String)
        case unknownFormat(String)
        case badDelay(String)
    }

    /// DEBUG launch arguments that run the drop path without a drag (index D-M3-14):
    /// `-ZivletDemoConvert /abs/path/file.ext <format> [-ZivletDemoCancelAfter <milliseconds>]`.
    public struct DemoConversion: Sendable, Equatable {
        public static let convertFlag = "-ZivletDemoConvert"
        public static let cancelFlag = "-ZivletDemoCancelAfter"

        public let url: URL
        public let target: FormatID
        public let cancelAfter: Duration?

        /// Nil when the convert flag is absent.
        public static func parse(
            arguments: [String], registry: FormatRegistry = .standard
        ) throws(DemoConversionError) -> DemoConversion? {
            guard let index = arguments.firstIndex(of: convertFlag) else { return nil }
            guard arguments.indices.contains(index + 2) else { throw .missingValue(convertFlag) }
            let path = arguments[index + 1]
            guard path.hasPrefix("/") else { throw .notAbsolute(path) }
            let name = arguments[index + 2].lowercased()
            guard let target = FormatID(rawValue: name) ?? registry.formatID(fileName: "x.\(name)") else {
                throw .unknownFormat(name)
            }
            return DemoConversion(
                url: URL(fileURLWithPath: path), target: target, cancelAfter: try delay(in: arguments))
        }

        private static func delay(in arguments: [String]) throws(DemoConversionError) -> Duration? {
            guard let index = arguments.firstIndex(of: cancelFlag) else { return nil }
            guard arguments.indices.contains(index + 1) else { throw .missingValue(cancelFlag) }
            guard let milliseconds = Int(arguments[index + 1]), milliseconds >= 0 else {
                throw .badDelay(arguments[index + 1])
            }
            return .milliseconds(milliseconds)
        }
    }
#endif
