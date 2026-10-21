import SwiftUI
import ZivletCore

/// The onboarding window's content (03b §8.2): one page at a time, page dots, and Back / Continue / Finish.
public struct OnboardingView: View {
    static let size = CGSize(width: 720, height: 480)

    let model: OnboardingModel

    public init(model: OnboardingModel) { self.model = model }

    public var body: some View {
        VStack(spacing: 0) {
            page.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(40)
            Divider()
            footer.padding(.horizontal, 24).padding(.vertical, 16)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    @ViewBuilder private var page: some View {
        switch model.flow.page {
        case .welcome: WelcomePage(model: model)
        case .practiceConvert: PracticePage(model: model, modes: [.convert])
        case .practiceToolsActions: PracticePage(model: model, modes: [.tools, .actions])
        case .keyboard: KeyboardPage()
        case .privacy: PrivacyPage()
        case .loginAndUpdates: LoginAndUpdatesPage(model: model)
        case .location: LocationPage(model: model)
        }
    }

    private var footer: some View {
        HStack {
            if !model.flow.isFirst { Button("Back", action: model.back) }
            Spacer()
            PageDots(current: model.flow.page)
            Spacer()
            if model.flow.isLast {
                Button("Finish", action: model.finish).keyboardShortcut(.defaultAction)
            } else {
                Button("Continue", action: model.next).keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// One dot per page; the current one filled.
struct PageDots: View {
    let current: OnboardingPage

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingPage.allCases, id: \.self) { page in
                Circle().fill(page == current ? Color.primary : Color.secondary.opacity(0.35)).frame(
                    width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(current.rawValue + 1) of \(OnboardingPage.allCases.count)")
    }
}

/// A page's title and lead sentence.
struct PageHeader: View {
    let title: String
    let lead: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.largeTitle.weight(.semibold))
            Text(lead).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A modifier key drawn as a key cap.
struct KeyCap: View {
    let symbol: String

    var body: some View {
        Text(symbol).font(.title2.weight(.medium)).frame(minWidth: 40, minHeight: 40)
            .background(.quaternary, in: .rect(cornerRadius: 8))
    }
}
