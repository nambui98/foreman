import SwiftUI

/// Confirmation for the "Dọn" button: one checkbox per flagged process. Orphans start checked,
/// idle servers unchecked (they may be kept on purpose).
struct CleanupOverlay: View {
    let candidates: [PortRow]
    let confirm: ([PortRow]) -> Void
    let dismiss: () -> Void
    @State private var selected: Set<Int32>

    init(candidates: [PortRow], confirm: @escaping ([PortRow]) -> Void, dismiss: @escaping () -> Void) {
        self.candidates = candidates
        self.confirm = confirm
        self.dismiss = dismiss
        _selected = State(initialValue: Set(candidates.filter { $0.flags.contains(where: \.isOrphan) }.map(\.pid)))
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(.rect)
                .onTapGesture(perform: dismiss)
            VStack(alignment: .leading, spacing: 12) {
                Text("Dọn tiến trình bị bỏ lại").font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(candidates) { row in
                            Toggle(isOn: binding(for: row.pid)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(row.name) (\(String(row.pid))) · \(row.ports.map(String.init).joined(separator: ", "))")
                                        .font(.callout)
                                    Text(row.flags.map(\.reason).sorted().joined(separator: ", "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
                .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Huỷ", action: dismiss)
                        .keyboardShortcut(.cancelAction)
                        .frame(maxWidth: .infinity)
                    Button(role: .destructive) {
                        let targets = candidates.filter { selected.contains($0.pid) }
                        dismiss()
                        confirm(targets)
                    } label: {
                        Text("Dừng \(selected.count)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(selected.isEmpty)
                    .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }
            .padding(16)
            .frame(width: 340)
            .background(.regularMaterial, in: .rect(cornerRadius: 12))
            .shadow(radius: 12)
        }
    }

    private func binding(for pid: Int32) -> Binding<Bool> {
        Binding {
            selected.contains(pid)
        } set: { isOn in
            if isOn { selected.insert(pid) } else { selected.remove(pid) }
        }
    }
}
