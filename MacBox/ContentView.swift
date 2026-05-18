import AppKit
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case network
    case tools
    case watcher
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .network: "Interfaces"
        case .tools: "Tools"
        case .watcher: "Watcher"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .network: "network"
        case .tools: "wrench.and.screwdriver"
        case .watcher: "eye"
        case .settings: "gearshape"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct ContentView: View {
    @StateObject private var networkStore = NetworkStore()
    @StateObject private var pingStore = PingStore()
    @StateObject private var watcherStore = WatcherStore()
    @StateObject private var updateStore = UpdateStore()

    @AppStorage("app-theme") private var themeRawValue = AppTheme.system.rawValue
    @State private var selection: AppSection = .network

    private var theme: AppTheme {
        AppTheme(rawValue: themeRawValue) ?? .system
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detailView
        }
        .preferredColorScheme(theme.colorScheme)
        .task {
            networkStore.startLiveUpdates()
            await updateStore.checkForUpdates()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 1) {
                    Text("MacBox")
                        .font(.headline)
                    Text("Network control")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            List(selection: $selection) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Picker("Theme", selection: $themeRawValue) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.large)

                if let release = updateStore.availableRelease {
                    Button {
                        updateStore.openCompatibleAsset()
                    } label: {
                        Label("Update \(release.tagName)", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                            .toolbarButtonFrame()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Text("Version \(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .network:
            NetworkView(store: networkStore)
        case .tools:
            ToolsView(store: pingStore)
        case .watcher:
            WatcherView(store: watcherStore)
        case .settings:
            SettingsView(updateStore: updateStore)
        }
    }
}
