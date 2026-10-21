import AppKit
import AudioToolbox
import ZivletWheelCore
import os

/// Haptic and sound feedback for wheel events (03a §2.7). A protocol so the store is testable.
public protocol WheelFeedback: AnyObject {
    func highlightChanged()
    func modeSwitched()
    func rejected()
    func dropAccepted()
}

/// The user's Sound and Haptics switches (03a §2.7: separate, both on by default).
public struct FeedbackSettings: Sendable, Equatable {
    public static let standard = FeedbackSettings(sound: true, haptics: true)

    public let sound: Bool
    public let haptics: Bool

    public init(sound: Bool, haptics: Bool) {
        self.sound = sound
        self.haptics = haptics
    }
}

/// Trackpad haptics plus the synthesized tick on highlight changes (14 §2.4), each behind its own setting.
public final class SystemWheelFeedback: WheelFeedback {
    private let performer: any NSHapticFeedbackPerformer
    private let tick: TickSound
    private var settings: FeedbackSettings

    public init(
        performer: any NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer,
        tick: TickSound = TickSound(), settings: FeedbackSettings = .standard
    ) {
        self.performer = performer
        self.tick = tick
        self.settings = settings
    }

    /// New switches apply from the next event.
    public func apply(_ settings: FeedbackSettings) { self.settings = settings }

    public func highlightChanged() {
        haptic(.alignment)
        if settings.sound { tick.play() }
    }

    public func modeSwitched() { haptic(.levelChange) }
    public func rejected() { haptic(.generic) }
    public func dropAccepted() { haptic(.generic) }

    /// `.now`: the highlight is already a frame behind the pointer (14 §2.4).
    private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard settings.haptics else { return }
        performer.perform(pattern, performanceTime: .now)
    }
}

/// Plays the tick through System Sound Services: low latency, overlapping, off the main thread. At most one tick per
/// 35 ms (`FeedbackGate`); silent when the system's user-interface sounds are off (spike P-W4 confirms the key).
public final class TickSound {
    public static let uiSoundsKey = "com.apple.sound.uiaudio.enabled"

    let isLoaded: Bool
    private let isEnabled: Bool
    private let now: () -> Duration
    private let player: () -> Void
    private var gate = FeedbackGate()

    public convenience init(isEnabled: Bool = TickSound.systemUISoundsEnabled()) {
        let sound = Self.loadTone()
        self.init(isEnabled: isEnabled, isLoaded: sound != nil) {
            if let sound { AudioServicesPlaySystemSound(sound) }
        }
    }

    init(
        isEnabled: Bool, isLoaded: Bool = true, now: @escaping () -> Duration = TickSound.uptime,
        play: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.isLoaded = isLoaded
        self.now = now
        player = play
    }

    public func play() {
        guard isEnabled else { return }
        let t = now()
        let (admitted, next) = gate.admit(requestedAt: t, now: t)
        gate = next
        if admitted { player() }
    }

    public static func systemUISoundsEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: uiSoundsKey) as? Bool ?? true
    }

    nonisolated static func uptime() -> Duration { .seconds(ProcessInfo.processInfo.systemUptime) }

    /// Writes the synthesized tone once to the temporary directory and registers it as a system sound.
    private static func loadTone() -> SystemSoundID? {
        let logger = Logger(subsystem: "app.zivlet.Zivlet", category: "wheel")
        let url = FileManager.default.temporaryDirectory.appending(path: "app.zivlet.tick-v1.wav")
        do {
            try ToneSynth.wav().write(to: url, options: .atomic)
        } catch {
            logger.error("Tick tone not written: \(error.localizedDescription, privacy: .private)")
            return nil
        }
        var sound: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &sound)
        guard status == kAudioServicesNoError else {
            logger.error("Tick tone not registered: OSStatus \(status, privacy: .public)")
            return nil
        }
        return sound
    }
}
