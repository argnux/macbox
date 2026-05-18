import Foundation

enum AppInfo {
    static let builtVersion = "2.2.0"

    static var version: String {
        guard let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !bundleVersion.isEmpty else {
            return builtVersion
        }

        return isVersion(builtVersion, newerThan: bundleVersion) ? builtVersion : bundleVersion
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = semanticParts(candidate)
        let currentParts = semanticParts(current)
        return candidateParts.lexicographicallyPrecedes(currentParts) == false
            && candidateParts != currentParts
    }

    private static func semanticParts(_ value: String) -> [Int] {
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
