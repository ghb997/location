import Foundation

enum TunnelConfig {
    /// LocalDevVPN / SideStore-style loopback tunnel endpoint.
    static let defaultIP = "10.7.0.1"
    static let defaultsKey = "locus.targetDeviceIP"
    static let automaticPortKey = "locus.tunnelPortAutomatic"
    static let portKey = "locus.tunnelPort"

    static var automaticPort: Bool {
        UserDefaults.standard.object(forKey: automaticPortKey) == nil
            || UserDefaults.standard.bool(forKey: automaticPortKey)
    }

    static var port: UInt16 {
        let stored = UserDefaults.standard.integer(forKey: portKey)
        return (1...65535).contains(stored) ? UInt16(stored) : 49152
    }

    static func isValidPort(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf8.allSatisfy { (48...57).contains($0) }
            && UInt16(trimmed).map { $0 > 0 } == true
    }

    @discardableResult
    static func setPort(_ value: String, automatic: Bool? = nil) -> Bool {
        guard isValidPort(value), let number = UInt16(value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        UserDefaults.standard.set(Int(number), forKey: portKey)
        if let automatic { UserDefaults.standard.set(automatic, forKey: automaticPortKey) }
        return true
    }

    static var targetIP: String {
        let stored = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let stored, !stored.isEmpty else { return defaultIP }
        return stored
    }

    static func isValidIP(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy {
            !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) }
                && ($0.count == 1 || $0.first != "0") && UInt8($0) != nil
        }
    }

    @discardableResult
    static func setTargetIP(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? defaultIP : trimmed
        guard isValidIP(normalized) else { return false }
        UserDefaults.standard.set(normalized, forKey: defaultsKey)
        return true
    }
}
