import SwiftUI

struct SettingsView: View {
    @ObservedObject var updateStore: UpdateStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppUI.sectionSpacing) {
                PageHeader("Settings", subtitle: "Application details and updates")

                AppPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader("Application")
                        LabeledContent("Version", value: AppInfo.version)
                    }
                }

                AppPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader("Updates") {
                            Button {
                                Task { await updateStore.checkForUpdates() }
                            } label: {
                                Label("Check Now", systemImage: "arrow.clockwise")
                                    .toolbarButtonFrame()
                            }
                            .controlSize(.large)
                            .disabled(updateStore.isChecking || updateStore.isInstalling)
                        }

                        updateState
                    }
                }
            }
            .padding(AppUI.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var updateState: some View {
        if updateStore.isChecking {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking for updates...")
                    .foregroundStyle(.secondary)
            }
        } else if updateStore.isInstalling {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(updateStore.lastCheckMessage ?? "Installing update...")
                    .foregroundStyle(.secondary)
            }
        } else if let release = updateStore.availableRelease {
            VStack(alignment: .leading, spacing: 10) {
                StatusBadge("Update \(release.tagName)", systemImage: "arrow.down.circle.fill", color: .blue)

                if let assetName = updateStore.availableAssetName {
                    Text(assetName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if let body = release.body, !body.isEmpty {
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }

                HStack(spacing: AppUI.controlSpacing) {
                    Button {
                        Task { await updateStore.installAvailableUpdate() }
                    } label: {
                        Label("Install Update", systemImage: "arrow.down.circle")
                            .toolbarButtonFrame()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        updateStore.openCompatibleAsset()
                    } label: {
                        Label("Download Zip", systemImage: "safari")
                            .toolbarButtonFrame()
                    }
                    .controlSize(.large)

                    Button {
                        updateStore.openReleasePage()
                    } label: {
                        Label("Release Notes", systemImage: "doc.text")
                            .toolbarButtonFrame()
                    }
                    .controlSize(.large)
                }
            }
        } else if let error = updateStore.lastError {
            StatusBadge(error, systemImage: "exclamationmark.triangle.fill", color: .red)
        } else if let message = updateStore.lastCheckMessage {
            Text(message)
                .foregroundStyle(.secondary)
        } else {
            Text("MacBox checks GitHub releases for a compatible macOS zip asset.")
                .foregroundStyle(.secondary)
        }
    }
}
