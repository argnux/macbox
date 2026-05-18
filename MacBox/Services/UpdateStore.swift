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
    @Published private(set) var isInstalling = false
    @Published var lastError: String?
    @Published var lastCheckMessage: String?

    private let githubOwner = "argnux"
    private let githubRepo = "macbox"
    private let targetBundleIdentifier = "com.argnux.macbox"
    private let targetBundleName = "MacBox.app"
    private let targetExecutableName = "macbox"

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

    func installAvailableUpdate() async {
        guard let release = availableRelease,
              let asset = compatibleAsset(in: release.assets) else {
            return
        }

        isInstalling = true
        lastError = nil
        lastCheckMessage = "Downloading \(release.tagName)..."
        defer { isInstalling = false }

        do {
            let extractedBundle = try await downloadAndExtractBundle(from: asset.browserDownloadURL)
            try validateUpdateBundle(extractedBundle.bundleURL)
            lastCheckMessage = "Installing \(release.tagName)..."
            try runInstaller(
                sourceBundleURL: extractedBundle.bundleURL,
                temporaryRootURL: extractedBundle.temporaryRootURL
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func openCompatibleAsset() {
        guard let release = availableRelease,
              let asset = compatibleAsset(in: release.assets) else {
            return
        }
        NSWorkspace.shared.open(asset.browserDownloadURL)
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

    private func downloadAndExtractBundle(from url: URL) async throws -> ExtractedUpdateBundle {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacBoxUpdate-\(UUID().uuidString)", isDirectory: true)
        let extractedRoot = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractedRoot, withIntermediateDirectories: true)

        let (zipURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw UpdateError.invalidAssetResponse
        }

        let localZipURL = tempRoot.appendingPathComponent("release.zip")
        try FileManager.default.moveItem(at: zipURL, to: localZipURL)
        try await runDittoExtract(zipURL: localZipURL, destinationURL: extractedRoot)

        let bundleURL = extractedRoot.appendingPathComponent(targetBundleName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: bundleURL.path) else {
            throw UpdateError.extractedBundleNotFound
        }

        return ExtractedUpdateBundle(bundleURL: bundleURL, temporaryRootURL: tempRoot)
    }

    private func validateUpdateBundle(_ bundleURL: URL) throws {
        let contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        let infoURL = contentsURL.appendingPathComponent("Info.plist")
        let executableURL = contentsURL
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(targetExecutableName)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)

        guard let info = NSDictionary(contentsOf: infoURL) as? [String: Any],
              info["CFBundleIdentifier"] as? String == targetBundleIdentifier,
              info["CFBundleExecutable"] as? String == targetExecutableName,
              let version = info["CFBundleShortVersionString"] as? String,
              isVersion(version, newerThan: AppInfo.version),
              FileManager.default.fileExists(atPath: executableURL.path),
              FileManager.default.fileExists(atPath: resourcesURL.appendingPathComponent("AppIcon.icns").path),
              FileManager.default.fileExists(atPath: resourcesURL.appendingPathComponent("Assets.car").path) else {
            throw UpdateError.invalidUpdateBundle
        }
    }

    private func runInstaller(sourceBundleURL: URL, temporaryRootURL: URL) throws {
        let destinationURL = Bundle.main.bundleURL.resolvingSymlinksInPath()
        let parentURL = destinationURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentURL.path) else {
            throw UpdateError.destinationNotWritable(destinationURL.path)
        }

        let backupURL = parentURL.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).backup-\(UUID().uuidString)",
            isDirectory: true
        )
        let scriptURL = temporaryRootURL.appendingPathComponent("install-update.zsh")
        let script = """
        #!/bin/zsh
        set -u

        APP_PID="$1"
        SOURCE="$2"
        DEST="$3"
        BACKUP="$4"
        TEMP_ROOT="$5"

        while /bin/kill -0 "$APP_PID" 2>/dev/null; do
            /bin/sleep 0.2
        done

        /bin/rm -rf "$BACKUP"
        if [ -e "$DEST" ]; then
            /bin/mv "$DEST" "$BACKUP" || exit 20
        fi

        if ! /usr/bin/ditto "$SOURCE" "$DEST"; then
            /bin/rm -rf "$DEST"
            if [ -e "$BACKUP" ]; then
                /bin/mv "$BACKUP" "$DEST"
            fi
            exit 21
        fi

        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
        /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$DEST" 2>/dev/null || true
        /usr/bin/open "$DEST"
        /bin/rm -rf "$BACKUP"
        /bin/rm -rf "$TEMP_ROOT"
        exit 0
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            scriptURL.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            sourceBundleURL.path,
            destinationURL.path,
            backupURL.path,
            temporaryRootURL.path
        ]
        try process.run()

        NSApp.terminate(nil)
    }

    private func runDittoExtract(zipURL: URL, destinationURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zipURL.path, destinationURL.path]
            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.zipExtractionFailed)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

private enum UpdateError: LocalizedError {
    case invalidResponse
    case invalidAssetResponse
    case extractedBundleNotFound
    case invalidUpdateBundle
    case destinationNotWritable(String)
    case zipExtractionFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid update response."
        case .invalidAssetResponse:
            return "GitHub returned an invalid update asset."
        case .extractedBundleNotFound:
            return "The update archive does not contain MacBox.app."
        case .invalidUpdateBundle:
            return "The downloaded update is not a valid newer MacBox app."
        case .destinationNotWritable(let path):
            return "MacBox cannot replace the app at \(path). Move it to a writable location or install the zip manually."
        case .zipExtractionFailed:
            return "Could not extract the update zip."
        }
    }
}

private struct ExtractedUpdateBundle {
    var bundleURL: URL
    var temporaryRootURL: URL
}
