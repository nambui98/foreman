import IOKit.pwr_mgt

/// Keeps the Mac from idle-sleeping while an agent is working (the display may still sleep).
/// The assertion is released as soon as no agent works, when disabled, and when Foreman quits.
@MainActor
final class KeepAwake {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    func update(active: Bool) {
        guard active != isActive else { return }
        if active {
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertPreventUserIdleSystemSleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Foreman: an AI coding agent is working" as CFString, &assertionID)
            isActive = status == kIOReturnSuccess
        } else {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            isActive = false
        }
    }
}
