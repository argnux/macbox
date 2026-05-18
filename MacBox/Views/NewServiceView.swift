import SwiftUI

struct NewServiceView: View {
    var hardware: HardwareInterface
    var onCreate: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.sectionSpacing) {
            SheetHeader(title: "New Service", subtitle: hardware.name)

            AppPanel {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Service Name")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("Service Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let errorMessage {
                StatusBadge(errorMessage, systemImage: "exclamationmark.triangle.fill", color: .red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func create() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Service name is required"
            return
        }

        isSaving = true
        if let error = await onCreate(trimmedName) {
            errorMessage = error
            isSaving = false
        } else {
            isSaving = false
            dismiss()
        }
    }
}
