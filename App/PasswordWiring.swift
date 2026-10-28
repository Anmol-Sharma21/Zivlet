import AppKit
import ZivletUI

/// The password sheet in the app (P2-101, plan 20c B6, D-M7-15): one prompter that shows the sheet as the tool window's
/// content through the app's coordinator, with Suggest from the system's generator. Jobs that need a password ask
/// it (Lock · Unlock and locked inputs, stream E); the batch that receives the secrets wipes them when it ends.
@MainActor
final class PasswordWiring {
    let prompter: PasswordPrompter

    init(toolWindows: ToolWindowWiring) {
        prompter = PasswordPrompter(presenter: toolWindows.coordinator) { model in
            PasswordSheetState(model: model, suggester: SystemPasswordSuggester())
        }
    }
}
