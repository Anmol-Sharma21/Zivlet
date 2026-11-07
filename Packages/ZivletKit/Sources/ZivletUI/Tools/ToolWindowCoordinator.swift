import AppKit
import SwiftUI
import ZivletActions
import ZivletCore

/// The window the coordinator drives; `ToolWindow` in the app, a fake in tests.
public protocol ToolWindowing: AnyObject {
    var onApply: () -> Void { get set }
    var onCancel: () -> Void { get set }
    /// Called once the window has closed, whatever closed it.
    var onClose: () -> Void { get set }
    var isVisible: Bool { get }
    func load(_ model: ToolWindowModel, content: AnyView)
    func update(_ model: ToolWindowModel)
    func show(at wheelCenter: CGPoint?)
    func bringForward()
    func close()
}

extension ToolWindow: ToolWindowing {
    /// Back in front and key, where it is; still without activating Zivlet.
    public func bringForward() { makeKeyAndOrderFront(nil) }
}

/// One window tool's part of the window (Lock · Unlock in stream E; later every editor tool): its state, its
/// content, and what Apply does. It tells the window about a new state through `modelChanged`.
public protocol WindowToolContent: AnyObject {
    var model: ToolWindowModel { get }
    var view: AnyView { get }
    var modelChanged: (ToolWindowModel) -> Void { get set }
    /// Admits the tool's job and returns true, or returns false to keep the window open.
    func apply() -> Bool
    /// The window closed without a job: drop whatever the tool held.
    func cancel()
}

/// Window tools from the wheel (P2-30, plan 20b A5): a tool that needs input before its job opens the one tool window
/// at the wheel's centre with that tool's content. Apply admits the job (the content does, like any drop) and closes
/// the window; Cancel closes it with no job. One tool window at a time: another window tool while it is open brings
/// the open one forward, with no stack. A single-file tool reached with several files (a stale selection) says so in
/// the HUD rather than doing nothing (PRD §5.7). A tool with no content is left to the caller.
public final class ToolWindowCoordinator {
    static let oneFileOnly = "This tool works on one file at a time"
    /// Another tool's window is open, so a new one cannot open yet.
    public static let windowBusy = "Finish the open window first"

    private let makeWindow: () -> any ToolWindowing
    private let contents: (ToolID, [URL]) -> (any WindowToolContent)?
    private let refuse: (ActionResult, CGPoint?) -> Void
    private let catalog: ToolCatalog
    private var window: (any ToolWindowing)?
    private var current: (any WindowToolContent)?
    /// Content that waits for the open window to close (Read QR's results), with where it opens.
    private var pending: (content: any WindowToolContent, point: CGPoint?)?

    public init(
        makeWindow: @escaping () -> any ToolWindowing,
        contents: @escaping (ToolID, [URL]) -> (any WindowToolContent)?,
        refuse: @escaping (ActionResult, CGPoint?) -> Void, catalog: ToolCatalog = .standard
    ) {
        self.makeWindow = makeWindow
        self.contents = contents
        self.refuse = refuse
        self.catalog = catalog
    }

    /// A tool window is open now.
    public var isOpen: Bool { current != nil && window?.isVisible == true }

    /// Opens `tool`'s window for `urls` near `point`; false when the tool has no window (the caller handles it).
    @discardableResult
    public func open(_ tool: ToolID, urls: [URL], near point: CGPoint?) -> Bool {
        if isOpen, let window {
            window.bringForward()
            return true
        }
        guard let content = contents(tool, urls) else { return false }
        if catalog.spec(tool).cardinality == .single, urls.count > 1 {
            refuse(.failed(ActionCard(title: Self.oneFileOnly)), point)
            return true
        }
        show(content, near: point)
        return true
    }

    /// Shows content that is ready, such as Read QR's results (D-M7-13). An open window is taken over only when
    /// `replacing` says its content may be (earlier results); another tool's window is brought forward and left as it
    /// is, and false is returned. With `whenFree`, the content then opens as soon as that window closes (a later one
    /// takes the place of one still waiting).
    @discardableResult
    public func present(
        _ content: any WindowToolContent, near point: CGPoint?,
        replacing: (any WindowToolContent) -> Bool = { _ in false }
    ) -> Bool {
        present(content, near: point, replacing: replacing, whenFree: false)
    }

    @discardableResult
    public func present(
        _ content: any WindowToolContent, near point: CGPoint?,
        replacing: (any WindowToolContent) -> Bool = { _ in false }, whenFree: Bool
    ) -> Bool {
        if isOpen, let current, let window {
            guard replacing(current) else {
                if whenFree { pending = (content, point) }
                window.bringForward()
                return false
            }
            current.cancel()
        }
        show(content, near: point)
        return true
    }

    private func show(_ content: any WindowToolContent, near point: CGPoint?) {
        let window = window ?? makeWindow()
        self.window = window
        current = content
        content.modelChanged = { [weak window] model in window?.update(model) }
        window.onApply = { [weak self] in self?.applied() }
        window.onCancel = { [weak self] in self?.cancelled() }
        window.onClose = { [weak self] in self?.closed() }
        window.load(content.model, content: content.view)
        window.show(at: point)
    }

    private func applied() {
        guard let content = current, content.apply() else { return }
        current = nil
        window?.close()
    }

    private func cancelled() {
        current?.cancel()
        current = nil
    }

    /// The window closed: content that waited for it opens now.
    private func closed() {
        guard current == nil, let waiting = pending else { return }
        pending = nil
        show(waiting.content, near: waiting.point)
    }
}
