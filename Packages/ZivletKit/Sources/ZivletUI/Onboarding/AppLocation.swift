import Darwin
import Foundation

/// Where Zivlet is running from (03b §8.2 page 7). From a disk image or a translocated copy it cannot start at
/// login or update itself, so onboarding offers to move it.
public nonisolated enum AppLocation {
    public static let applications = URL(filePath: "/Applications", directoryHint: .isDirectory)

    public static func needsMove(bundlePath: String) -> Bool {
        bundlePath.hasPrefix("/Volumes/") || bundlePath.contains("/AppTranslocation/")
    }

    /// Why a move failed, in Zivlet's words.
    public enum MoveFailure: Error, Equatable {
        case alreadyThere, copyFailed, notOpened

        public var message: String {
            switch self {
            case .alreadyThere: "Zivlet is already in Applications. Quit this copy and open that one."
            case .copyFailed: "Zivlet couldn't copy itself to Applications. Drag it there from the disk image instead."
            case .notOpened:
                "Zivlet is in Applications now, but the new copy didn't open. Quit this one and open Zivlet from Applications."
            }
        }
    }

    /// `copy` off the caller's actor: a few hundred MB from a disk image must not stall the onboarding window.
    @concurrent public static func copyInBackground(
        bundle: URL, into applications: URL = AppLocation.applications
    ) async throws(MoveFailure) -> URL {
        try copy(bundle: bundle, into: applications)
    }

    /// Copies the bundle into `applications` under a hidden temporary name, then renames it into place, so a copy
    /// that fails part-way leaves nothing behind. Never replaces an existing copy. Returns the new bundle's URL.
    public static func copy(
        bundle: URL, into applications: URL = AppLocation.applications, fileManager: FileManager = .default
    ) throws(MoveFailure) -> URL {
        let destination = applications.appending(path: bundle.lastPathComponent, directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: destination.path) else { throw .alreadyThere }
        let partial = applications.appending(
            path: ".\(bundle.lastPathComponent).partial-\(UUID().uuidString)", directoryHint: .isDirectory)
        do {
            try fileManager.copyItem(at: bundle, to: partial)
            try fileManager.moveItem(at: partial, to: destination)
        } catch {
            try? fileManager.removeItem(at: partial)
            throw fileManager.fileExists(atPath: destination.path) ? .alreadyThere : .copyFailed
        }
        return destination
    }

    /// The running copy quits only when the copy in Applications started as a process of its own. LaunchServices
    /// can instead hand back this process (same bundle identifier) or nothing.
    public static func shouldQuit(launched: pid_t?, current: pid_t) -> Bool {
        guard let launched else { return false }
        return launched != current
    }
}
