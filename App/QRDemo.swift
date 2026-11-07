#if DEBUG
    import AppKit
    import ZivletActions
    import ZivletUI
    import os

    /// DEBUG `-ZivletQRDemo <folder>` (plan 20b A10, 20g F3, exit row V9): READ QR through the drop path on the
    /// visible files of `<folder>`, which the script made, listed before anything is written there. What the run
    /// showed goes to `<folder>/qr.json`: each row's payload, file, caption and whether Open is offered, and the notes;
    /// or the toast or card when no window opened. The results window is logged as `QR demo: window <n> frame x y w h`;
    /// `done` marks the end. Copy goes to the demo's private pasteboard; nothing is opened.
    @MainActor
    enum QRDemo {
        private static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "app")

        static func observe(_ codes: CodeWiring, folder: URL) {
            codes.outcomeObserver = { outcome in
                DemoFolder.write(report(outcome), named: "qr", in: folder, logger: logger)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(800))
                    if let window = ShotFrame.visible(ToolWindow.self) {
                        ShotFrame.log("QR demo", window, logger: logger)
                    }
                    DemoFolder.finish(folder)
                }
            }
        }

        private static func report(_ outcome: CodeToolModel.Outcome) -> [String: Any] {
            switch outcome {
            case .window(let model):
                let rows = model.rows.map { row -> [String: Any] in
                    [
                        "payload": row.payload, "file": row.fileName, "caption": row.caption ?? "",
                        "open": row.link != nil,
                    ]
                }
                return ["kind": "window", "title": model.window.title, "rows": rows, "notes": model.notes]
            case .hud(let result):
                return [
                    "kind": CopyTextDemo.kind(result), "toast": result.toast ?? result.card?.title ?? "", "rows": [],
                ]
            }
        }
    }
#endif
