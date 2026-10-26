import Foundation
import os

/// What loading `boxes.json` found (P2-141).
public enum BoxLoad: Sendable, Equatable {
    /// No file yet.
    case empty
    /// The valid boxes and items; `dropped` counts the invalid or over-cap ones left out.
    case loaded(ShelfLibrary, dropped: Int)
    /// The file could not be decoded; it was moved aside to `boxes.damaged.json` (or "boxes.damaged 2.json" …, so an
    /// earlier one is never replaced) and the library starts empty.
    case damaged
    /// The file is there but could not be read (permissions, an I/O error). It is left untouched, the library
    /// starts empty and saving is refused, so a passing error never costs the person their boxes.
    case unreadable
    /// A later Zivlet wrote the file. It is left untouched, the library starts empty and saving is refused.
    case newer(schema: Int)

    /// What to tell the person after this load; nil when nothing was lost or set aside.
    public var notice: String? {
        switch self {
        case .empty: nil
        case .loaded(_, let dropped):
            dropped == 0 ? nil : "Some items couldn't be restored. A copy of the old boxes file was kept."
        case .damaged: "Your boxes file couldn't be read, so it was set aside and the Drop Box starts empty."
        case .unreadable: "Zivlet couldn't open your boxes file. It was left as it is, and changes aren't kept."
        case .newer: BoxStoreError.wouldOverwriteNewer.userMessage
        }
    }

    /// Whether saving may replace the file after this load.
    public var canSave: Bool {
        switch self {
        case .empty, .loaded, .damaged: true
        case .unreadable, .newer: false
        }
    }
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
/// private (0700) folder. Every save checks the file again, so a newer file is never overwritten; the check reads
/// the file only when it is not the one this store last wrote or read (inode, size and modification date differ).
public struct BoxStore: Sendable {
    public static let schema = 1
    static let damagedName = "boxes.damaged.json"
    static let repairName = "boxes.before-repair.json"
    static let fileMode = 0o600
    static let folderMode = 0o700
    private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "actions")

    public let file: URL
    private let memo = FileMemo()

    public init(file: URL) { self.file = file }

    /// `~/Library/Application Support/Zivlet/boxes.json`.
    public static func standard() -> BoxStore {
        BoxStore(file: URL.applicationSupportDirectory.appending(path: "Zivlet/boxes.json"))
    }

    public func load() -> BoxLoad {
        guard FileManager.default.fileExists(atPath: file.path) else { return .empty }
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            let code = (error as NSError).code
            Self.logger.error("Boxes file could not be read (code \(code, privacy: .public)); left untouched")
            return .unreadable
        }
        let header: StoredHeader
        do {
            header = try JSONDecoder().decode(StoredHeader.self, from: data)
        } catch {
            return moveAside(because: error)
        }
        if header.schema > Self.schema {
            Self.logger.error("Boxes file has newer schema \(header.schema, privacy: .public); left untouched")
            return .newer(schema: header.schema)
        }
        guard header.schema == Self.schema else { return moveAside(because: nil) }
        let stored: LenientLibrary
        do {
            stored = try JSONDecoder().decode(LenientLibrary.self, from: data)
        } catch {
            return moveAside(because: error)
        }
        let (library, dropped) = stored.library()
        if dropped > 0 {
            Self.logger.error("Boxes file: \(dropped, privacy: .public) entries dropped")
            keepBeforeRepair(data)
        }
        memo.remember(FileStamp(of: file))
        return .loaded(library, dropped: dropped)
    }

    public func save(_ library: ShelfLibrary) throws(BoxStoreError) {
        try refuseNewer()
        do {
            let data = try JSONEncoder().encode(
                StoredLibrary(schema: Self.schema, boxes: library.boxes, current: library.currentID))
            try write(data)
            memo.remember(FileStamp(of: file))
        } catch {
            Self.logger.error("Boxes file not saved (code \((error as NSError).code, privacy: .public))")
            throw .writeFailed
        }
    }

    /// Throws when the file on disk has a newer schema; a file this store last wrote or read is not read again.
    private func refuseNewer() throws(BoxStoreError) {
        guard let stamp = FileStamp(of: file), !memo.matches(stamp) else { return }
        if let data = try? Data(contentsOf: file),
            let header = try? JSONDecoder().decode(StoredHeader.self, from: data),
            header.schema > Self.schema
        {
            throw .wouldOverwriteNewer
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

    /// Renames the file to the first free "boxes.damaged.json", "boxes.damaged 2.json" …; an earlier one stays.
    private func moveAside(because error: (any Error)?) -> BoxLoad {
        Self.logger.error("Boxes file could not be decoded: \(Self.describe(error), privacy: .public)")
        let aside = Self.free(Self.damagedName, in: file.deletingLastPathComponent())
        if let aside, rename(file.path, aside.path) == 0 {
            Self.logger.error("Boxes file moved aside; starting empty")
        } else {
            Self.logger.error("Boxes file could not be moved aside; starting empty")
        }
        return .damaged
    }

    /// The file as it was before invalid entries were left out, kept once beside it (0600).
    private func keepBeforeRepair(_ data: Data) {
        guard let copy = Self.free(Self.repairName, in: file.deletingLastPathComponent()),
            FileManager.default.createFile(
                atPath: copy.path, contents: data, attributes: [.posixPermissions: Self.fileMode])
        else { return Self.logger.error("Boxes file: the copy before repair could not be kept") }
    }

    /// `name`, or "name 2.json" … up to 99: the first that does not exist.
    static func free(_ name: String, in folder: URL) -> URL? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        return (1...99).lazy.map { number in
            folder.appending(path: number == 1 ? name : "\(base) \(number).\(ext)")
        }.first { !FileManager.default.fileExists(atPath: $0.path) }
    }

    /// The kind of decoding error and where, never the values: safe for a public log line.
    static func describe(_ error: (any Error)?) -> String {
        guard let error = error as? DecodingError else { return error == nil ? "unknown schema" : "not JSON" }
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context),
            .dataCorrupted(let context):
            let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }
            return "invalid at \(path.joined(separator: "."))"
        @unknown default: return "invalid"
        }
    }
}

/// What tells one version of a file from another without reading it.
struct FileStamp: Equatable, Sendable {
    let inode: Int
    let size: Int
    let modified: Date

    init?(of file: URL) {
        guard let values = try? FileManager.default.attributesOfItem(atPath: file.path),
            let inode = values[.systemFileNumber] as? Int, let size = values[.size] as? Int,
            let modified = values[.modificationDate] as? Date
        else { return nil }
        self.inode = inode
        self.size = size
        self.modified = modified
    }
}

/// The stamp of the file a store last wrote or read, shared by the store's copies.
final class FileMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var stamp: FileStamp?

    func remember(_ stamp: FileStamp?) { lock.withLock { self.stamp = stamp } }
    func matches(_ stamp: FileStamp) -> Bool { lock.withLock { self.stamp == stamp } }
}
