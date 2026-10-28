import Darwin
import Foundation
import OSLog

/// Looks for a test password's bytes where P2-102 says it must never be (plan 20c B7): this process's log, a defaults
/// suite, a folder's names and files, a child's command line and environment, and texts. Every probe is a plain byte
/// search; each is shown to catch a planted leak before a policy test trusts it.
///
/// The log probe reads what the unified log keeps readable for this process: values logged `.public` and the message
/// text. Values logged `.private` read back as `<private>` here, so `Scripts/check-secrets.sh` refuses logging a secret
/// at any privacy level.
public enum LeakProbe {
    /// `needle` occurs in `haystack` (an empty needle never does).
    public static func contains(_ needle: [UInt8], in haystack: some Sequence<UInt8>) -> Bool {
        guard !needle.isEmpty else { return false }
        let bytes = Array(haystack)
        guard bytes.count >= needle.count else { return false }
        return (0...(bytes.count - needle.count)).contains { start in
            bytes[start..<(start + needle.count)].elementsEqual(needle)
        }
    }

    /// `needle` occurs in the UTF-8 of any of `texts`.
    public static func contains(_ needle: [UInt8], in texts: [String]) -> Bool {
        texts.contains { contains(needle, in: Array($0.utf8)) }
    }

    /// Every log line of this process since `start`, any subsystem, as `subsystem [category] message`.
    public static func logLines(since start: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try store.getEntries(at: store.position(date: start))
        return entries.compactMap { entry in
            guard let log = entry as? OSLogEntryLog else { return entry.composedMessage }
            return "\(log.subsystem) [\(log.category)] \(log.composedMessage)"
        }
    }

    /// Everything a defaults suite holds, as an XML property list (strings as UTF-8, data as base64 and raw).
    public static func bytes(of defaults: UserDefaults) throws -> Data {
        let values = defaults.dictionaryRepresentation()
        let xml = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
        let raw = values.values.compactMap { $0 as? Data }.reduce(Data(), +)
        return xml + raw
    }

    /// The paths under `folder` whose name or contents hold `needle`.
    public static func leaks(_ needle: [UInt8], under folder: URL) -> [String] {
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
        let urls = (walker?.allObjects as? [URL]) ?? []
        return urls.filter { url in
            if contains(needle, in: Array(url.lastPathComponent.utf8)) { return true }
            let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
            return isFile && contains(needle, in: (try? Data(contentsOf: url)) ?? Data())
        }.map(\.path)
    }

    /// `needle` occurs in a child's arguments or environment as Zivlet asked for them (the spawn request). The kernel
    /// does not show another process's environment on this macOS, even a child's (`ps -E` lists none), so a child's
    /// environment is checked where it is made.
    public static func contains(_ needle: [UInt8], arguments: [String], environment: [String: String]) -> Bool {
        contains(needle, in: arguments + environment.map { "\($0.key)=\($0.value)" })
    }

    /// A process's command line as the kernel keeps it (`KERN_PROCARGS2`); nil when unreadable.
    public static func commandLine(of pid: Int32) -> Data? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return Data(buffer.prefix(size))
    }
}
