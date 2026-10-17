import AppKit

@MainActor
final class CaptureFeedback {
    private var successSound: NSSound?
    private var failureSound: NSSound?
    func play(success: Bool) {
        if success {
            if successSound == nil {
                successSound = NSSound(named: .init("Glass"))
                successSound?.volume = 0.35
            }
            successSound?.play()
        } else {
            if failureSound == nil { failureSound = NSSound(named: .init("Funk")) }
            failureSound?.play()
        }
    }
}
