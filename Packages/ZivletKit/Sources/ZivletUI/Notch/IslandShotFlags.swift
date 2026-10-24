import ZivletNotchCore

// Debug builds and the CPU measurement build (D-ND3), whose pill row needs `-ZivletIslandPill`; never shipped.
#if DEBUG || ZIVLET_ISLAND_PREVIEW
    /// Screenshot-only flags (plan 14 D-ND4), so every finish and the pill can be captured without touching the
    /// owner's accessibility settings or display: `-ZivletIslandFinish glass|solid|contrast` forces the finish's
    /// settings, `-ZivletIslandPill YES` treats every display as having no notch, and `-ZivletIslandBackdrop
    /// white|black` puts a plain panel under the island for contrast readings, and `-ZivletIslandReduceMotion YES`
    /// makes the island move as under Reduce Motion.
    public struct IslandShotFlags: Sendable, Equatable {
        public enum Backdrop: String, Sendable, Equatable {
            case white, black
        }

        public enum Invalid: Error, Equatable {
            case missingValue(String)
            case unknown(String, String)
        }

        static let finishFlag = "-ZivletIslandFinish"
        static let pillFlag = "-ZivletIslandPill"
        static let backdropFlag = "-ZivletIslandBackdrop"
        static let reduceMotionFlag = "-ZivletIslandReduceMotion"

        /// The settings the finish is resolved with instead of the system's; nil follows the system.
        public let finish: IslandFinish.Settings?
        public let pill: Bool
        public let backdrop: Backdrop?
        public let reduceMotion: Bool

        public init(
            finish: IslandFinish.Settings? = nil, pill: Bool = false, backdrop: Backdrop? = nil,
            reduceMotion: Bool = false
        ) {
            self.finish = finish
            self.pill = pill
            self.backdrop = backdrop
            self.reduceMotion = reduceMotion
        }

        public static func parse(arguments: [String]) throws(Invalid) -> IslandShotFlags {
            let finish = try value(finishFlag, in: arguments).map { value throws(Invalid) in try settings(value) }
            let pill = try value(pillFlag, in: arguments) == "YES"
            let backdrop = try value(backdropFlag, in: arguments).map { value throws(Invalid) in
                guard let backdrop = Backdrop(rawValue: value) else { throw .unknown(backdropFlag, value) }
                return backdrop
            }
            let reduceMotion = try value(reduceMotionFlag, in: arguments) == "YES"
            return IslandShotFlags(finish: finish, pill: pill, backdrop: backdrop, reduceMotion: reduceMotion)
        }

        private static func settings(_ value: String) throws(Invalid) -> IslandFinish.Settings {
            switch value {
            case "glass": .standard
            case "solid": IslandFinish.Settings(reduceTransparency: true, increaseContrast: false)
            case "contrast": IslandFinish.Settings(reduceTransparency: false, increaseContrast: true)
            default: throw .unknown(finishFlag, value)
            }
        }

        private static func value(_ flag: String, in arguments: [String]) throws(Invalid) -> String? {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            guard arguments.indices.contains(index + 1) else { throw .missingValue(flag) }
            return arguments[index + 1]
        }
    }
#endif
