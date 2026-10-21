import ServiceManagement
import SwiftUI
import Testing

@testable import ZivletUI

/// A login item service that records calls and answers with a scripted status or error.
final class FakeLoginService: LoginItemService {
    struct Refused: Error {}

    var status: SMAppService.Status
    var registerError: (any Error)?
    private(set) var registers = 0
    private(set) var unregisters = 0
    private(set) var settingsOpened = 0

    init(status: SMAppService.Status = .notRegistered, registerError: (any Error)? = nil) {
        self.status = status
        self.registerError = registerError
    }

    func register() throws {
        registers += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() throws {
        unregisters += 1
        status = .notRegistered
    }

    func openSystemSettings() { settingsOpened += 1 }
}

@Suite("Launch at login through SMAppService (D5)")
@MainActor
struct LoginItemTests {
    @Test func turningItOnRegistersOnce() {
        let service = FakeLoginService()
        let model = LoginItemModel(service: service)
        #expect(!model.isOn)
        model.setOn(true)
        model.setOn(true)
        #expect(service.registers == 1 && model.isOn && model.errorText == nil)
    }

    @Test func turningItOffUnregisters() {
        let service = FakeLoginService(status: .enabled)
        let model = LoginItemModel(service: service)
        model.setOn(false)
        #expect(service.unregisters == 1 && !model.isOn)
    }

    @Test func approvalNeededShowsWhereToAllowIt() {
        let service = FakeLoginService(status: .requiresApproval)
        let model = LoginItemModel(service: service)
        #expect(model.isOn)
        #expect(model.approvalMessage == "Allow Zivlet in System Settings › General › Login Items.")
        model.openSystemSettings()
        #expect(service.settingsOpened == 1)
        #expect(LoginItemModel(service: FakeLoginService()).approvalMessage == nil)
    }

    @Test func aRefusalShowsZivletsWordsAndTheToggleReverts() {
        let service = FakeLoginService(registerError: FakeLoginService.Refused())
        let model = LoginItemModel(service: service)
        model.setOn(true)
        #expect(!model.isOn && model.errorText == "Zivlet couldn't change its login item.")
        service.registerError = nil
        model.setOn(true)
        #expect(model.isOn && model.errorText == nil)
    }

    @Test func theGeneralPaneRendersWithTheLoginRow() throws {
        let model = SettingsModel.preview
        model.loginItem = LoginItemModel(service: FakeLoginService(status: .requiresApproval))
        let image = try #require(ImageRenderer(content: SettingsPane.general.view(model: model)).nsImage)
        #expect(image.size.width >= 480)
    }
}
