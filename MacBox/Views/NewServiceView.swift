import SwiftUI

struct NewServiceView: View {
    var hardware: HardwareInterface
    var onCreate: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Service")
                .font(.title3.weight(.semibold))

            Text(hardware.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Service Name", text: $name)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .controlSize(.large)

                Button("Create") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(width: 380)
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
