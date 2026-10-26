import ZivletActions

/// The actions the box's bulk commands run (P2-142): the existing actions of the wheel, reused, never copied. Every
/// one is a port, so the controller is tested with fakes.
public struct BoxActions {
    public let sharePicker: any SharePicking

    public init(sharePicker: any SharePicking = SystemSharePicker()) {
        self.sharePicker = sharePicker
    }
}
