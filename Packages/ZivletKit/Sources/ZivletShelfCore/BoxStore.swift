import Foundation
import os

/// What loading `boxes.json` found (P2-141).
public enum BoxLoad: Sendable, Equatable {
    /// No file yet.
    case empty
    /// The valid boxes and items; `dropped` counts the invalid or over-cap ones left out.
    case loaded(ShelfLibrary, dropped: Int)
    /// The file could not be read; it was moved aside to `boxes.damaged.json` and the library starts empty.
    case damaged
    /// A later Zivlet wrote the file. It is left untouched, the library starts empty and saving is refused.
    case newer(schema: Int)
}

public enum BoxStoreError: Error, Equatable, Sendable {
    case wouldOverwriteNewer
    case writeFailed

    public var userMessage: String {
        switch self {
        case .wouldOverwriteNewer: "A newer Zivlet saved these boxes, so changes made here aren't kept."
        case .writeFailed: "Zivlet couldn't save your boxes."
        }
    }
}

/// The boxes on disk (P2-141): one private (0600) JSON file with a schema number, written atomically into a
/// private (0700) folder. Stateless: every save checks the file again, so a newer file is never overwritten.
public struct BoxStore: Sendable {
    public static let schema = 1
    static let damagedName = "boxes.damaged.json"
    static let fileMode = 0o600
    static let folderMode = 0o700
    private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")

    public let file: URL

    public init(file: URL) { self.file = file }

    /// `~/Library/Application Support/Zivlet/boxes.json`.
    public static func standard() -> BoxStore {
        BoxStore(file: URL.applicationSupportDirectory.appending(path: "Zivlet/boxes.json"))
    }

    public func load() -> BoxLoad {
        guard FileManager.default.fileExists(atPath: file.path) else { return .empty }
        guard let data = try? Data(contentsOf: file),
            let header = try? JSONDecoder().decode(StoredHeader.self, from: data)
        else { return moveAside() }
        if header.schema > Self.schema {
            Self.logger.error("Boxes file has newer schema \(header.schema, privacy: .public); left untouched")
            return .newer(schema: header.schema)
        }
        guard header.schema == Self.schema, let stored = try? JSONDecoder().decode(LenientLibrary.self, from: data)
        else { return moveAside() }
        let (library, dropped) = stored.library()
        if dropped > 0 { Self.logger.error("Boxes file: \(dropped, privacy: .public) entries dropped") }
        return .loaded(library, dropped: dropped)
    }

    public func save(_ library: ShelfLibrary) throws(BoxStoreError) {
        if let data = try? Data(contentsOf: file),
            let header = try? JSONDecoder().decode(StoredHeader.self, from: data),
            header.schema > Self.schema
        {
            throw .wouldOverwriteNewer
        }
        do {
            let data = try JSONEncoder().encode(
                StoredLibrary(schema: Self.schema, boxes: library.boxes, current: library.currentID))
            try write(data)
        } catch {
            Self.logger.error("Boxes file not saved")
            throw .writeFailed
        }
    }

    /// A temporary 0600 file in the same folder, then `rename(2)`, which replaces the old file atomically.
    private func write(_ data: Data) throws {
        let folder = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: Self.folderMode])
        let temporary = folder.appending(path: ".boxes-\(UUID().uuidString).tmp")
        guard
            FileManager.default.createFile(
                atPath: temporary.path, contents: data, attributes: [.posixPermissions: Self.fileMode])
        else { throw CocoaError(.fileWriteUnknown) }
        guard rename(temporary.path, file.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
    }

    private func moveAside() -> BoxLoad {
        let aside = file.deletingLastPathComponent().appending(path: Self.damagedName)
        if rename(file.path, aside.path) == 0 {
            Self.logger.error("Boxes file was unreadable; moved aside and starting empty")
        } else {
            Self.logger.error("Boxes file was unreadable and could not be moved aside; starting empty")
        }
        return .damaged
    }
}
