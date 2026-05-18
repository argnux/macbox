import AppKit
import Foundation

struct ReleaseAsset: Decodable, Identifiable, Hashable {
    var id: String { browserDownloadURL.absoluteString }
    var name: String
    var browserDownloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

struct ReleaseInfo: Decodable, Identifiable, Hashable {
    var id: String { tagName }
    var tagName: String
    var body: String?
    var htmlURL: URL
    var assets: [ReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case body
        case assets
    }
}

@MainActor
final class UpdateStore: ObservableObject {
    @Published private(set) var availableRelease: ReleaseInfo?
    @Published private(set) var isChecking = false
    @Published var lastError: String?
    @Published var lastCheckMessage: String?

    private let githubOwner = "argnux"
    private let githubRepo = "macbox"

    var availableAssetName: String? {
        guard let availableRelease else { return nil }
        return compatibleAsset(in: availableRelease.assets)?.name
    }

    func checkForUpdates() async {
        let currentVersion = AppInfo.version
        guard currentVersion.lowercased() != "dev" else { return }

        isChecking = true
        lastError = nil
        lastCheckMessage = nil
        defer { isChecking = false }

        guard let url = URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest") else {
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("MacBox/\(currentVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw UpdateError.invalidResponse
            }

            let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)

            if isVersion(release.tagName, newerThan: currentVersion),
               compatibleAsset(in: release.assets) != nil {
                availableRelease = release
                lastCheckMessage = "Update \(release.tagName) is available."
            } else {
                availableRelease = nil
                lastCheckMessage = "MacBox is up to date."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openCompatibleAsset() {
        guard let release = availableRelease,
              let url = compatibleAsset(in: release.assets) else {
            return
        }
        NSWorkspace.shared.open(url.browserDownloadURL)
    }

    func openReleasePage() {
        guard let release = availableRelease else { return }
        NSWorkspace.shared.open(release.htmlURL)
    }

    private func compatibleAsset(in assets: [ReleaseAsset]) -> ReleaseAsset? {
        #if arch(arm64)
        let archCandidates = ["arm64", "aarch64"]
        #else
        let archCandidates = ["amd64", "x86_64", "x64"]
        #endif

        return assets.first { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".zip") && archCandidates.contains { name.contains($0) }
        }
    }

    private func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        semanticParts(candidate).lexicographicallyPrecedes(semanticParts(current)) == false
            && semanticParts(candidate) != semanticParts(current)
    }

    private func semanticParts(_ value: String) -> [Int] {
        let clean = value
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: "-")
            .first ?? ""

        var parts = clean.split(separator: ".").compactMap { Int($0) }
        while parts.count < 3 {
            parts.append(0)
        }
        return Array(parts.prefix(3))
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid update response."
        }
    }
}
