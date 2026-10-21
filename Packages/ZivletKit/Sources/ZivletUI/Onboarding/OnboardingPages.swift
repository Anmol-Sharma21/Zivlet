import SwiftUI
import ZivletCore
import ZivletSettings

struct WelcomePage: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(
                title: "Welcome to Zivlet",
                lead: "Drag files, tap a key, and drop them on what you want them to become.")
            Label {
                Text("Zivlet lives in the menu bar. Look for this symbol near the clock to pause it or open Settings.")
            } icon: {
                Image(systemName: "circle.hexagongrid").font(.title2)
            }
            Text("The next two pages let you try it with a sample file. Nothing is converted while you practise.")
                .foregroundStyle(.secondary)
        }
    }
}

struct KeyboardPage: View {
    var body: some View {
        PageHeader(
            title: "Keyboard",
            lead:
                "Zivlet works by dragging for now. A Services menu entry and a global shortcut for the files selected in Finder arrive in a later version."
        )
    }
}

/// The folders macOS protects, and what happens the first time Zivlet saves there.
struct PrivacyPage: View {
    static let rows: [(String, String)] = [
        ("Desktop and Documents", "macOS asks once, the first time Zivlet saves a result next to a file there."),
        ("Downloads", "macOS asks once, the first time Zivlet saves a result there."),
        ("USB drives and memory cards", "macOS asks once per drive."),
        ("Network folders", "macOS asks once per server."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            PageHeader(
                title: "Your files stay yours",
                lead: "Zivlet converts on this Mac. It never uploads your files and it has no account.")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(Self.rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).fontWeight(.medium)
                        Text(row.1).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Choosing Don't Allow only stops Zivlet saving in that folder; you can change it in System Settings.")
                .foregroundStyle(.secondary)
        }
    }
}

struct LoginAndUpdatesPage: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeader(title: "Always ready", lead: "Zivlet only watches for drags, so it costs nothing while idle.")
            Toggle("Open Zivlet at login", isOn: $model.wantsLoginItem)
            Toggle(
                "Check for updates automatically",
                isOn: Binding(
                    get: { model.settings.updates.automaticChecks },
                    set: { model.set(\.updates.automaticChecks, $0) }))
        }
        .toggleStyle(.switch)
    }
}

struct LocationPage: View {
    let model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.commands.moveToApplications == nil {
                PageHeader(title: "You're all set", lead: "Drag any file and tap a key to begin.")
            } else {
                PageHeader(
                    title: "Move Zivlet to Applications",
                    lead:
                        "Zivlet is running from a disk image or a temporary place. In Applications it can start at login and update itself."
                )
                HStack(spacing: 10) {
                    Button("Move to Applications", action: model.moveToApplications).disabled(model.isMoving)
                    if model.isMoving {
                        ProgressView().controlSize(.small)
                        Text("Copying…").foregroundStyle(.secondary)
                    }
                }
                if let error = model.moveError { Text(error).foregroundStyle(.red) }
            }
        }
    }
}
