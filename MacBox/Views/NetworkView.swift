import SwiftUI

struct NetworkView: View {
    @ObservedObject var store: NetworkStore

    @State private var editingInterface: LogicInterface?
    @State private var addTarget: HardwareInterface?
    @State private var alert: NetworkAlert?

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.sectionSpacing) {
            PageHeader("Interfaces", subtitle: interfaceSummary) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label(store.isRefreshing ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                        .toolbarButtonFrame()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(store.isRefreshing)
            }

            content
        }
        .padding(AppUI.pagePadding)
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

    private var interfaceSummary: String {
        let count = store.interfaces.count
        return count == 1 ? "1 hardware port" : "\(count) hardware ports"
    }

    @ViewBuilder
    private var content: some View {
        if store.interfaces.isEmpty, store.isRefreshing {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.interfaces.isEmpty {
            VStack(spacing: 18) {
                EmptyStateView(
                    systemImage: "network.slash",
                    title: "No network interfaces found",
                    message: "Connect a network adapter or refresh after changing macOS network settings."
                )

                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .toolbarButtonFrame()
                }
                .controlSize(.large)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
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
        AppPanel {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        "Services",
                        subtitle: serviceSummary
                    ) {
                        Button(action: onAdd) {
                            Label("New Service", systemImage: "plus")
                                .toolbarButtonFrame()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    if hardware.logicInterfaces.isEmpty {
                        EmptyStateView(
                            systemImage: "network.slash",
                            title: "No services",
                            message: nil
                        )
                        .frame(minHeight: 120)
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

                    StatusBadge(hardware.isActive ? "Link up" : "Link down", color: hardware.isActive ? .green : .secondary)

                    Text(hardware.mac.isEmpty ? "Unknown MAC" : hardware.mac)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
        }
    }

    private var serviceSummary: String {
        let count = hardware.logicInterfaces.count
        return count == 1 ? "1 configured service" : "\(count) configured services"
    }
}

private struct LogicInterfaceGrid: View {
    var logicInterfaces: [LogicInterface]
    var onEdit: (LogicInterface) -> Void
    var onDelete: (LogicInterface) -> Void

    var body: some View {
        ScrollView(.horizontal) {
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
                            .frame(minWidth: 150, alignment: .leading)
                        MethodBadge(method: logicInterface.method)
                        MonospaceCell(logicInterface.ip)
                        MonospaceCell(displayMask(logicInterface.mask))
                        MonospaceCell(logicInterface.gateway)
                        HStack(spacing: 8) {
                            Button {
                                onEdit(logicInterface)
                            } label: {
                                Image(systemName: "pencil")
                                    .iconButtonFrame()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .contentShape(Rectangle())
                            .help("Edit")

                            Button(role: .destructive) {
                                onDelete(logicInterface)
                            } label: {
                                Image(systemName: "trash")
                                    .iconButtonFrame()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .contentShape(Rectangle())
                            .help("Delete")
                        }
                    }

                    Divider()
                        .gridCellColumns(6)
                }
            }
            .padding(12)
            .frame(minWidth: 760, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: AppUI.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppUI.cornerRadius)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
        )
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
            .frame(minWidth: 110, alignment: .leading)
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
            .frame(minWidth: 130, alignment: .leading)
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
