import SwiftUI

struct InterfaceEditorView: View {
    var interface: LogicInterface
    var onSave: (InterfaceUpdatePayload) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var method: IPMethod
    @State private var ip: String
    @State private var mask: String
    @State private var gateway: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(interface: LogicInterface, onSave: @escaping (InterfaceUpdatePayload) async -> String?) {
        self.interface = interface
        self.onSave = onSave
        _name = State(initialValue: interface.name)
        _method = State(initialValue: interface.method == .dhcp ? .dhcp : .manual)
        _ip = State(initialValue: interface.ip)
        _mask = State(initialValue: interface.mask)
        _gateway = State(initialValue: interface.gateway)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Service")
                .font(.title3.weight(.semibold))

            Form {
                TextField("Name", text: $name)

                Picker("Method", selection: $method) {
                    ForEach(IPMethod.editableCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                TextField("IP Address", text: $ip)
                    .disabled(method == .dhcp)

                TextField("Subnet Mask", text: $mask)
                    .disabled(method == .dhcp)

                TextField("Gateway", text: $gateway)
                    .disabled(method == .dhcp)
            }

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

                Button("Save") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() async {
        errorMessage = nil

        let finalMask: String
        if method == .manual {
            guard IPAddressValidator.isValidIPv4(ip) else {
                errorMessage = "Invalid IP Address format"
                return
            }

            if !gateway.isEmpty, !IPAddressValidator.isValidIPv4(gateway) {
                errorMessage = "Invalid Gateway format"
                return
            }

            guard let normalizedMask = IPAddressValidator.normalizedMask(from: mask) else {
                errorMessage = "Invalid Subnet Mask format"
                return
            }
            finalMask = normalizedMask
        } else {
            finalMask = mask
        }

        isSaving = true
        let payload = InterfaceUpdatePayload(
            oldName: interface.id,
            newName: name,
            method: method,
            ip: ip,
            mask: finalMask,
            gateway: gateway
        )

        if let error = await onSave(payload) {
            errorMessage = error
            isSaving = false
        } else {
            isSaving = false
            dismiss()
        }
    }
}
