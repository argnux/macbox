import SwiftUI

struct SettingsView: View {
    @ObservedObject var updateStore: UpdateStore

    var body: some View {
        Form {
            Section("Application") {
                LabeledContent("Version", value: AppInfo.version)
            }

            Section("Updates") {
                HStack {
                    Button {
                        Task { await updateStore.checkForUpdates() }
                    } label: {
                        Label("Check Now", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.large)
                    .disabled(updateStore.isChecking)

                    if updateStore.isChecking {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let release = updateStore.availableRelease {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Update \(release.tagName)")
                            .font(.headline)

                        if let assetName = updateStore.availableAssetName {
                            Text(assetName)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let body = release.body, !body.isEmpty {
                            Text(body)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(8)
                        }

                        HStack {
                            Button {
                                updateStore.openCompatibleAsset()
                            } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)

                            Button {
                                updateStore.openReleasePage()
                            } label: {
                                Label("Release Notes", systemImage: "doc.text")
                            }
                            .controlSize(.large)
                        }
                    }
                } else if let error = updateStore.lastError {
                    Text(error)
                        .foregroundStyle(.red)
                } else if let message = updateStore.lastCheckMessage {
                    Text(message)
                        .foregroundStyle(.secondary)
                } else {
                    Text("MacBox checks GitHub releases for a compatible macOS zip asset.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}
