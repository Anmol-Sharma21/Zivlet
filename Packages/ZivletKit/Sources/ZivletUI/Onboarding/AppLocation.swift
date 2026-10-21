import Foundation

/// Where Zivlet is running from (03b §8.2 page 7). From a disk image or a translocated copy it cannot start at
/// login or update itself, so onboarding offers to move it.
public enum AppLocation {
    public static let applications = URL(filePath: "/Applications", directoryHint: .isDirectory)

    public static func needsMove(bundlePath: String) -> Bool {
        bundlePath.hasPrefix("/Volumes/") || bundlePath.contains("/AppTranslocation/")
    }

    /// Why a move failed, in Zivlet's words.
    public enum MoveFailure: Error, Equatable {
        case alreadyThere, copyFailed

        public var message: String {
            switch self {
            case .alreadyThere: "Zivlet is already in Applications. Quit this copy and open that one."
            case .copyFailed: "Zivlet couldn't copy itself to Applications. Drag it there from the disk image instead."
            }
        }
    }

    /// Copies the bundle into `applications`; never replaces an existing copy. Returns the new bundle's URL.
    public static func copy(
        bundle: URL, into applications: URL = AppLocation.applications, fileManager: FileManager = .default
    ) throws(MoveFailure) -> URL {
        let destination = applications.appending(path: bundle.lastPathComponent, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else { throw .alreadyThere }
        do {
            try fileManager.copyItem(at: bundle, to: destination)
        } catch {
            throw .copyFailed
        }
        return destination
    }
}
