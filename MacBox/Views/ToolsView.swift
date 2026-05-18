import SwiftUI

struct ToolsView: View {
    @ObservedObject var store: PingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Tools")
                .font(.title2.weight(.semibold))

            GroupBox("Ping") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 12) {
                        TextField("IP Address or Host", text: $store.target)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .disabled(store.isRunning)

                        Toggle("Infinite", isOn: $store.isInfinite)
                            .disabled(store.isRunning)

                        Stepper(value: $store.packetCount, in: 1...100) {
                            Text("\(store.packetCount)")
                                .frame(width: 34, alignment: .trailing)
                        }
                        .disabled(store.isRunning || store.isInfinite)

                        Button {
                            store.start()
                        } label: {
                            Label(store.isRunning ? "Pinging..." : "Start", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.isRunning || store.target.isEmpty)

                        Button(role: .destructive) {
                            store.stop()
                        } label: {
                            Label("Stop", systemImage: "stop.fill")
                        }
                        .disabled(!store.isRunning)
                    }

                    TextEditor(text: .constant(store.logs))
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(minHeight: 260)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .padding(20)
    }
}
