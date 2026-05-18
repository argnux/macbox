import SwiftUI

struct ToolsView: View {
    @ObservedObject var store: PingStore

    var body: some View {
        VStack(alignment: .leading, spacing: AppUI.sectionSpacing) {
            PageHeader("Tools", subtitle: "Run network checks from one place")

            AppPanel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader("Ping", subtitle: store.isRunning ? "Running" : "Ready") {
                        if store.isRunning {
                            StatusBadge("Active", systemImage: "dot.radiowaves.left.and.right", color: .green)
                        }
                    }

                    controls

                    Divider()

                    SectionHeader("Output") {
                        Button {
                            store.clearLogs()
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .toolbarButtonFrame()
                        }
                        .controlSize(.large)
                        .disabled(store.logs.isEmpty)
                    }

                    TextEditor(text: .constant(store.logs.isEmpty ? "No output yet." : store.logs))
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: AppUI.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppUI.cornerRadius)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.55))
                        )
                        .frame(minHeight: 320)
                }
            }

            Spacer()
        }
        .padding(AppUI.pagePadding)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            pingControls
            pingControlsVertical
        }
    }

    private var pingControls: some View {
        HStack(spacing: AppUI.controlSpacing) {
            TextField("IP Address or Host", text: $store.target)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .disabled(store.isRunning)

            Toggle("Infinite", isOn: $store.isInfinite)
                .disabled(store.isRunning)

            Stepper(value: $store.packetCount, in: 1...100) {
                Text("\(store.packetCount) packets")
                    .frame(width: 78, alignment: .trailing)
            }
            .disabled(store.isRunning || store.isInfinite)

            Button {
                store.start()
            } label: {
                Label(store.isRunning ? "Pinging..." : "Start", systemImage: "play.fill")
                    .toolbarButtonFrame()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(store.isRunning || store.target.isEmpty)

            Button(role: .destructive) {
                store.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .toolbarButtonFrame()
            }
            .controlSize(.large)
            .disabled(!store.isRunning)
        }
    }

    private var pingControlsVertical: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("IP Address or Host", text: $store.target)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
                .disabled(store.isRunning)

            HStack(spacing: AppUI.controlSpacing) {
                Toggle("Infinite", isOn: $store.isInfinite)
                    .disabled(store.isRunning)

                Stepper(value: $store.packetCount, in: 1...100) {
                    Text("\(store.packetCount) packets")
                        .frame(width: 78, alignment: .trailing)
                }
                .disabled(store.isRunning || store.isInfinite)
            }

            HStack(spacing: AppUI.controlSpacing) {
                Button {
                    store.start()
                } label: {
                    Label(store.isRunning ? "Pinging..." : "Start", systemImage: "play.fill")
                        .toolbarButtonFrame()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isRunning || store.target.isEmpty)

                Button(role: .destructive) {
                    store.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .toolbarButtonFrame()
                }
                .controlSize(.large)
                .disabled(!store.isRunning)
            }
        }
    }
}
