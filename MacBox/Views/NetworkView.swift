import SwiftUI

struct NetworkView: View {
    @ObservedObject var store: NetworkStore

    @State private var editingInterface: LogicInterface?
    @State private var addTarget: HardwareInterface?
    @State private var alert: NetworkAlert?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if store.interfaces.isEmpty, store.isRefreshing {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.interfaces.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "network.slash")
                        .font(.largeTitle)
                    Text("No network interfaces found")
                        .font(.headline)
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(store.interfaces) { hardware in
                            HardwareInterfacePanel(
                                hardware: hardware,
                                onAdd: { addTarget = hardware },
                                onEdit: { editingInterface = $0 },
                                onDelete: { alert = .delete($0) }
                            )
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .padding(20)
        .sheet(item: $editingInterface) { logicInterface in
            InterfaceEditorView(interface: logicInterface) { payload in
                await store.updateInterface(payload)
            }
        }
        .sheet(item: $addTarget) { hardware in
            NewServiceView(hardware: hardware) { name in
                await store.createInterface(hardwarePortName: hardware.name, newServiceName: name)
            }
        }
        .alert(item: $alert) { alert in
            switch alert {
            case .message(let text):
                return Alert(title: Text("MacBox"), message: Text(text), dismissButton: .default(Text("OK")))
            case .delete(let logicInterface):
                return Alert(
                    title: Text("Delete Service"),
                    message: Text("Delete \"\(logicInterface.name)\" permanently?"),
                    primaryButton: .destructive(Text("Delete")) {
                        Task {
                            if let error = await store.deleteInterface(serviceName: logicInterface.name) {
                                self.alert = .message(error)
                            }
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Network Interfaces")
                    .font(.title2.weight(.semibold))
                Text("\(store.interfaces.count) hardware ports")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .frame(minHeight: 34)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(store.isRefreshing)
        }
    }
}

private enum NetworkAlert: Identifiable {
    case message(String)
    case delete(LogicInterface)

    var id: String {
        switch self {
        case .message(let text): "message-\(text)"
        case .delete(let logicInterface): "delete-\(logicInterface.id)"
        }
    }
}

private struct HardwareInterfacePanel: View {
    var hardware: HardwareInterface
    var onAdd: () -> Void
    var onEdit: (LogicInterface) -> Void
    var onDelete: (LogicInterface) -> Void

    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Services")
                        .font(.headline)
                    Spacer()
                    Button(action: onAdd) {
                        Label("New Service", systemImage: "plus")
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }

                if hardware.logicInterfaces.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "network.slash")
                            .font(.title2)
                        Text("No Services")
                            .font(.callout)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    LogicInterfaceGrid(
                        logicInterfaces: hardware.logicInterfaces,
                        onEdit: onEdit,
                        onDelete: onDelete
                    )
                }
            }
            .padding(.top, 12)
        } label: {
            HStack(spacing: 14) {
                StatusDot(isActive: hardware.isActive)
                    .help(hardware.isActive ? "Active (Link Up)" : "Inactive (Link Down)")

                VStack(alignment: .leading, spacing: 3) {
                    Text(hardware.name)
                        .font(.headline)
                    Text(hardware.device)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(hardware.mac.isEmpty ? "Unknown MAC" : hardware.mac)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .padding(16)
        .background(panelBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor).opacity(0.72), lineWidth: 1.25)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 4, y: 1)
    }

    private var panelBackground: some ShapeStyle {
        Color(nsColor: .controlBackgroundColor)
    }
}

private struct LogicInterfaceGrid: View {
    var logicInterfaces: [LogicInterface]
    var onEdit: (LogicInterface) -> Void
    var onDelete: (LogicInterface) -> Void

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 11) {
            GridRow {
                HeaderCell("Name")
                HeaderCell("Method")
                HeaderCell("IP Address")
                HeaderCell("Mask / CIDR")
                HeaderCell("Gateway")
                HeaderCell("Actions")
            }

            Divider()
                .gridCellColumns(6)

            ForEach(logicInterfaces) { logicInterface in
                GridRow {
                    Text(logicInterface.name)
                        .font(.system(.body, design: .default))
                        .lineLimit(1)
                    MethodBadge(method: logicInterface.method)
                    MonospaceCell(logicInterface.ip)
                    MonospaceCell(displayMask(logicInterface.mask))
                    MonospaceCell(logicInterface.gateway)
                    HStack(spacing: 8) {
                        Button {
                            onEdit(logicInterface)
                        } label: {
                            Image(systemName: "pencil")
                                .frame(width: 26, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .contentShape(Rectangle())
                        .help("Edit")

                        Button(role: .destructive) {
                            onDelete(logicInterface)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 26, height: 24)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .contentShape(Rectangle())
                        .help("Delete")
                    }
                }

                Divider()
                    .gridCellColumns(6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayMask(_ mask: String) -> String {
        guard let cidr = IPAddressValidator.maskToCIDR(mask) else { return mask }
        return "\(mask) (\(cidr))"
    }
}

private struct HeaderCell: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct MonospaceCell: View {
    var value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        Text(value.isEmpty ? "-" : value)
            .font(.system(.body, design: .monospaced))
            .lineLimit(1)
            .textSelection(.enabled)
    }
}

private struct MethodBadge: View {
    var method: IPMethod

    var body: some View {
        Text(method.rawValue)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(foregroundColor)
    }

    private var backgroundColor: Color {
        switch method {
        case .dhcp: .blue.opacity(0.16)
        case .manual: .orange.opacity(0.18)
        case .unknown, .autoOther: .gray.opacity(0.16)
        }
    }

    private var foregroundColor: Color {
        switch method {
        case .dhcp: .blue
        case .manual: .orange
        case .unknown, .autoOther: .secondary
        }
    }
}

private struct StatusDot: View {
    var isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray.opacity(0.65))
            .frame(width: 11, height: 11)
            .shadow(color: isActive ? .green.opacity(0.45) : .clear, radius: 4)
    }
}
