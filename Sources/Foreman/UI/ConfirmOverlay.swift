import SwiftUI

/// A destructive action waiting for the user's OK.
struct Confirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let action: @MainActor () async -> Void
}

/// In-panel confirmation card. System dialogs (`confirmationDialog`/`alert`) attach to the
/// MenuBarExtra window, which never becomes active, so their buttons ignore clicks; a plain
/// overlay inside the panel always receives them.
struct ConfirmOverlay: View {
    let confirmation: Confirmation
    let dismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(.rect)
                .onTapGesture(perform: dismiss)
            VStack(alignment: .leading, spacing: 12) {
                Text(confirmation.title).font(.headline)
                ScrollView {
                    Text(confirmation.message).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                        .frame(maxWidth: .infinity)
                    Button(role: .destructive) {
                        let action = confirmation.action
                        dismiss()
                        Task { await action() }
                    } label: {
                        Text("Stop").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .padding(16)
            .frame(width: 320)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .shadow(radius: 12)
        }
    }
}
