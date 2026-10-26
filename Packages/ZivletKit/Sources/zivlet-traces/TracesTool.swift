import Foundation
import ZivletNotchCore
import ZivletTrigger

/// `zivlet-traces report <folder>` scores the provisional proximity rule on a folder of drag traces;
/// `zivlet-traces tune <folder>` lists the standard grid, best first (NB5, OS-M5b-1). Invalid files are listed with
/// their reasons and left out. Text goes to standard output through `FileHandle`; nothing is written to disk.
enum TracesTool {
    static let usage = "usage: zivlet-traces report|tune <folder>\n"
    static let usageStatus: Int32 = 64

    static func run(arguments: [String], write: (String) -> Void) -> Int32 {
        guard arguments.count == 2, let command = Command(rawValue: arguments[0]) else {
            write(usage)
            return usageStatus
        }
        let loaded: DragTraceFolder.Loaded
        do {
            loaded = try DragTraceFolder.load(from: URL(filePath: arguments[1], directoryHint: .isDirectory))
        } catch {
            write("zivlet-traces: cannot read the folder (it does not exist or is not readable)\n")
            return 1
        }
        write(summary(loaded))
        let traces = loaded.traces.map(\.trace)
        switch command {
        case .report:
            let config = NotchProximity.Config.provisional
            let score = TraceEvaluator.score(traces, zones: { zones(for: $0, margin: config.margin) }, config: config)
            write("provisional: \(ProximityTuning.Row(config: config, score: score).line)\n")
        case .tune:
            for row in ProximityTuning.grid(traces: traces, zones: zones(for:margin:)) { write(row.line + "\n") }
        }
        return 0
    }

    static func write(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }

    /// The island's tray zone for a trace's display (`IslandLayout.trayZone`), as the app builds it. A display the
    /// island refuses has no zone, so its traces cannot open the tray; the trace checks already refuse such values.
    static func zones(for display: TraceDisplay, margin: Double) -> [NotchProximity.Zone] {
        guard
            let geometry = try? DisplayGeometry(
                id: display.id, frame: display.frame, visibleFrame: display.visibleFrame,
                safeAreaTop: display.safeAreaTop, auxiliaryTopLeft: display.auxiliaryTopLeft,
                auxiliaryTopRight: display.auxiliaryTopRight, isBuiltIn: false)
        else { return [] }
        return [NotchProximity.Zone(display: display.id, rect: IslandLayout.trayZone(on: geometry, margin: margin))]
    }

    private static func summary(_ loaded: DragTraceFolder.Loaded) -> String {
        let traces = loaded.traces.map(\.trace)
        let notch = traces.filter { $0.label == .notch }.count
        let header = "\(traces.count) traces (\(notch) notch, \(traces.count - notch) normal)\n"
        return header + loaded.invalid.map { "left out \($0.name): \($0.reason)\n" }.joined()
    }

    private enum Command: String {
        case report, tune
    }
}
