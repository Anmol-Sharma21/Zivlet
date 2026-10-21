import Foundation
import Observation
import ServiceManagement
import os

/// The login item calls Zivlet makes (14 §3.4), behind a protocol so the toggle's behaviour is testable.
public protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// The app itself as a login item (03b §8.4).
public final class MainAppLoginItem: LoginItemService {
    private let service = SMAppService.mainApp

    public init() {}

    public var status: SMAppService.Status { service.status }
    public func register() throws { try service.register() }
    public func unregister() throws { try service.unregister() }
    public func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// The "Open Zivlet at login" row: shows the live status, asks for approval when macOS wants it, and reports a
/// refusal in Zivlet's words while the toggle falls back to the real status.
@Observable
public final class LoginItemModel {
    static let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "settings")
    static let refusal = "Zivlet couldn't change its login item."
    static let approval = "Allow Zivlet in System Settings › General › Login Items."

    public private(set) var status: SMAppService.Status
    public private(set) var errorText: String?
    @ObservationIgnored private let service: any LoginItemService

    public init(service: any LoginItemService = MainAppLoginItem()) {
        self.service = service
        status = service.status
    }

    /// On while registered, including while macOS waits for the person's approval.
    public var isOn: Bool { status == .enabled || status == .requiresApproval }

    public var approvalMessage: String? { status == .requiresApproval ? Self.approval : nil }

    public func setOn(_ on: Bool) {
        guard on != isOn else { return }
        do {
            if on { try service.register() } else { try service.unregister() }
            errorText = nil
        } catch {
            let code = (error as NSError).code
            Self.logger.error("Login item not changed: error \(code, privacy: .public)")
            errorText = Self.refusal
        }
        status = service.status
    }

    public func openSystemSettings() { service.openSystemSettings() }
}
