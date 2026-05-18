import AppKit
import CoreServices
import Foundation

actor LegacyBundleMigrator {
    private let fileManager = FileManager.default
    private let githubOwner = "argnux"
    private let githubRepo = "macbox"
    private let targetBundleName = "MacBox.app"
    private let targetBundleIdentifier = "com.argnux.macbox"
    private let targetExecutableName = "macbox"

    func repairIfNeeded() async {
        let currentBundleURL = Bundle.main.bundleURL
        let repairPlan = makeRepairPlan(for: currentBundleURL)

        guard repairPlan.needsMetadataRepair || repairPlan.needsBundleRename else {
            return
        }

        do {
            var launchBundleURL = currentBundleURL
            var repaired = false

            if repairPlan.needsMetadataRepair {
                let release = try await latestRelease()
                guard let asset = compatibleAsset(in: release.assets) else {
                    return
                }

                let extractedBundle = try await downloadAndExtractBundle(from: asset.browserDownloadURL)
                defer { try? fileManager.removeItem(at: extractedBundle.temporaryRootURL) }
                try copyBundleMetadata(from: extractedBundle.bundleURL, to: currentBundleURL)
                repaired = true
            }

            if repairPlan.needsBundleRename, shouldAttemptRename(currentBundleURL) {
                launchBundleURL = (try? renameBundleIfPossible(currentBundleURL)) ?? currentBundleURL
            }

            if repaired || launchBundleURL != currentBundleURL {
                registerBundle(at: launchBundleURL)
                await relaunch(from: launchBundleURL)
            }
        } catch {
            return
        }
    }

    private func makeRepairPlan(for bundleURL: URL) -> LegacyBundleRepairPlan {
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let info = NSDictionary(contentsOf: infoURL) as? [String: Any] ?? [:]
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)

        let bundleIdentifier = info["CFBundleIdentifier"] as? String
        let displayName = info["CFBundleDisplayName"] as? String
        let bundleName = info["CFBundleName"] as? String
        let executableName = info["CFBundleExecutable"] as? String
        let bundleVersion = info["CFBundleShortVersionString"] as? String
        let iconName = info["CFBundleIconName"] as? String
        let iconFile = info["CFBundleIconFile"] as? String

        let hasAppIcon = fileManager.fileExists(
            atPath: resourcesURL.appendingPathComponent("AppIcon.icns").path
        )
        let hasAssetCatalog = fileManager.fileExists(
            atPath: resourcesURL.appendingPathComponent("Assets.car").path
        )

        let needsMetadataRepair = bundleIdentifier != targetBundleIdentifier
            || displayName != "MacBox"
            || bundleName != "MacBox"
            || executableName != targetExecutableName
            || bundleVersion != AppInfo.builtVersion
            || iconName != "AppIcon"
            || iconFile != "AppIcon"
            || !hasAppIcon
            || !hasAssetCatalog

        return LegacyBundleRepairPlan(
            needsMetadataRepair: needsMetadataRepair,
            needsBundleRename: bundleURL.lastPathComponent != targetBundleName
        )
    }

    private func latestRelease() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest") else {
            throw LegacyBundleMigrationError.invalidReleaseURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MacBox/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LegacyBundleMigrationError.invalidReleaseResponse
        }

        return try JSONDecoder().decode(ReleaseInfo.self, from: data)
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

    private func downloadAndExtractBundle(from url: URL) async throws -> ExtractedReleaseBundle {
        let tempRoot = fileManager.temporaryDirectory
            .appendingPathComponent("MacBoxLegacyMigration-\(UUID().uuidString)", isDirectory: true)
        let extractedRoot = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractedRoot, withIntermediateDirectories: true)

        let (zipURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw LegacyBundleMigrationError.invalidAssetResponse
        }

        let localZipURL = tempRoot.appendingPathComponent("release.zip")
        try fileManager.moveItem(at: zipURL, to: localZipURL)
        try await runDittoExtract(zipURL: localZipURL, destinationURL: extractedRoot)

        let bundleURL = extractedRoot.appendingPathComponent(targetBundleName, isDirectory: true)
        guard fileManager.fileExists(atPath: bundleURL.path) else {
            throw LegacyBundleMigrationError.extractedBundleNotFound
        }

        return ExtractedReleaseBundle(bundleURL: bundleURL, temporaryRootURL: tempRoot)
    }

    private func copyBundleMetadata(from sourceBundleURL: URL, to destinationBundleURL: URL) throws {
        let sourceContentsURL = sourceBundleURL.appendingPathComponent("Contents", isDirectory: true)
        let destinationContentsURL = destinationBundleURL.appendingPathComponent("Contents", isDirectory: true)

        try copyInfoPlist(
            from: sourceContentsURL.appendingPathComponent("Info.plist"),
            to: destinationContentsURL.appendingPathComponent("Info.plist")
        )

        let sourcePkgInfoURL = sourceContentsURL.appendingPathComponent("PkgInfo")
        if fileManager.fileExists(atPath: sourcePkgInfoURL.path) {
            try replaceItem(
                at: destinationContentsURL.appendingPathComponent("PkgInfo"),
                with: sourcePkgInfoURL
            )
        }

        try replaceItem(
            at: destinationContentsURL.appendingPathComponent("Resources", isDirectory: true),
            with: sourceContentsURL.appendingPathComponent("Resources", isDirectory: true)
        )
    }

    private func replaceItem(at destinationURL: URL, with sourceURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    private func copyInfoPlist(from sourceURL: URL, to destinationURL: URL) throws {
        let sourceData = try Data(contentsOf: sourceURL)
        guard var info = try PropertyListSerialization.propertyList(
            from: sourceData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            throw LegacyBundleMigrationError.invalidInfoPlist
        }

        info["CFBundleDisplayName"] = "MacBox"
        info["CFBundleName"] = "MacBox"
        info["CFBundleExecutable"] = targetExecutableName
        info["CFBundleIdentifier"] = targetBundleIdentifier
        info["CFBundleShortVersionString"] = AppInfo.builtVersion
        info["CFBundleIconFile"] = "AppIcon"
        info["CFBundleIconName"] = "AppIcon"

        let destinationData = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try destinationData.write(to: destinationURL, options: .atomic)
    }

    private func shouldAttemptRename(_ bundleURL: URL) -> Bool {
        let key = "legacy-bundle-rename-attempted-\(bundleURL.path)"
        if UserDefaults.standard.bool(forKey: key) {
            return false
        }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }

    private func renameBundleIfPossible(_ bundleURL: URL) throws -> URL {
        let targetURL = bundleURL.deletingLastPathComponent()
            .appendingPathComponent(targetBundleName, isDirectory: true)

        guard bundleURL != targetURL else {
            return bundleURL
        }

        let temporaryURL = bundleURL.deletingLastPathComponent()
            .appendingPathComponent(".MacBox.app.migrating-\(UUID().uuidString)", isDirectory: true)

        try fileManager.moveItem(at: bundleURL, to: temporaryURL)
        do {
            try fileManager.moveItem(at: temporaryURL, to: targetURL)
        } catch {
            try? fileManager.moveItem(at: temporaryURL, to: bundleURL)
            throw error
        }

        return targetURL
    }

    private func registerBundle(at bundleURL: URL) {
        _ = LSRegisterURL(bundleURL as CFURL, true)
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
                    continuation.resume(throwing: LegacyBundleMigrationError.zipExtractionFailed)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    @MainActor
    private func relaunch(from bundleURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            NSApp.terminate(nil)
        }
    }
}

private struct LegacyBundleRepairPlan {
    var needsMetadataRepair: Bool
    var needsBundleRename: Bool
}

private struct ExtractedReleaseBundle {
    var bundleURL: URL
    var temporaryRootURL: URL
}

private enum LegacyBundleMigrationError: Error {
    case invalidReleaseURL
    case invalidReleaseResponse
    case invalidAssetResponse
    case extractedBundleNotFound
    case invalidInfoPlist
    case zipExtractionFailed
}
