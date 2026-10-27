import Foundation
import ZivletActions
import ZivletRuntime

/// Writes Copy Text's `.txt` files off the main thread, as the Drop Box's trash does (G-M5b-8): one per input, going
/// on past a file that fails, so the card names both what was saved and what was not. Cancellation is checked between
/// files; the ones not tried are listed as stopped.
nonisolated enum TextSaving {
    static let stopped = "stopped"

    @concurrent static func save(_ files: [TextFile], fallbackFolder: URL, copied: Bool) async -> TextDelivery {
        let writer = TextFileWriter(fallbackFolder: fallbackFolder)
        var saved: [URL] = []
        var notSaved: [NotSavedFile] = []
        for file in files {
            let name = file.source.lastPathComponent
            guard !Task.isCancelled else {
                notSaved.append(NotSavedFile(name: name, reason: stopped))
                continue
            }
            do {
                saved.append(try writer.write(file.text, beside: file.source))
            } catch {
                notSaved.append(NotSavedFile(name: name, reason: JobErrorCopy.copy(for: error).message))
            }
        }
        return TextDelivery(copied: copied, saved: saved, notSaved: notSaved)
    }
}

/// The app's side of saving, so `ToolWiring` stays on the main actor while the files are written elsewhere.
public enum TextSaver {
    public static func save(_ files: [TextFile], fallbackFolder: URL, copied: Bool) async -> TextDelivery {
        await TextSaving.save(files, fallbackFolder: fallbackFolder, copied: copied)
    }
}
