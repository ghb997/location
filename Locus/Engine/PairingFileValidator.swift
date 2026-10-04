import Foundation

enum PairingFileValidator {
    static let maximumBytes = 1024 * 1024

    static func isValid(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximumBytes,
              let dictionary = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
              let publicKey = dictionary["public_key"] as? Data, publicKey.count == 32,
              let privateKey = dictionary["private_key"] as? Data, privateKey.count == 32,
              let identifier = dictionary["identifier"] as? String,
              !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let irk = dictionary["alt_irk"] {
            guard let bytes = irk as? Data, bytes.count == 16 else { return false }
        }
        return true
    }
}
