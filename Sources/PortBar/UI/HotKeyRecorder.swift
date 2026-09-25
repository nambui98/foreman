import AppKit
import SwiftUI

/// Shows the shortcut; click, then press the new combination (Esc cancels).
struct HotKeyRecorder: View {
    @Binding var combo: HotKeyCombo
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(isRecording ? "Nhấn tổ hợp phím…" : combo.display) {
            isRecording ? stop() : start()
        }
        .monospaced()
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {  // Esc
                stop()
            } else if let recorded = HotKeyCombo(event: event), recorded.isValid {
                combo = recorded
                stop()
            }
            return nil  // swallow keys while recording
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }
}
