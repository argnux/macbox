import Foundation

enum IPAddressValidator {
    static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }

        return parts.allSatisfy { part in
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  let number = Int(part),
                  number >= 0,
                  number <= 255 else {
                return false
            }
            return true
        }
    }

    static func maskToCIDR(_ mask: String) -> String? {
        guard isValidIPv4(mask) else { return nil }
        let octets = mask.split(separator: ".").compactMap { UInt8($0) }
        let bits = octets.flatMap { octet -> [Bool] in
            (0..<8).reversed().map { ((octet >> $0) & 1) == 1 }
        }

        var seenZero = false
        var count = 0
        for bit in bits {
            if bit {
                if seenZero { return nil }
                count += 1
            } else {
                seenZero = true
            }
        }
        return "/\(count)"
    }

    static func cidrToMask(_ cidr: String) -> String? {
        let trimmed = cidr.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        guard let prefix = Int(rawValue), prefix >= 0, prefix <= 32 else { return nil }

        var remaining = prefix
        let octets = (0..<4).map { _ -> Int in
            let bits = min(remaining, 8)
            remaining -= bits
            guard bits > 0 else { return 0 }
            return 256 - Int(pow(2.0, Double(8 - bits)))
        }
        return octets.map(String.init).joined(separator: ".")
    }

    static func isCIDRInput(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("/") || (!trimmed.contains(".") && trimmed.count <= 2)
    }

    static func normalizedMask(from value: String) -> String? {
        if isCIDRInput(value) {
            return cidrToMask(value)
        }
        return isValidIPv4(value) ? value : nil
    }
}
