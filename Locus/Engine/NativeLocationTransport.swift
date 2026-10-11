import Foundation

@MainActor
struct NativeLocationTransport: LocationTransport {
    var isStopPending: Bool { LocationEngine.isStopPending }
    var isDraining: Bool { TunnelDiagnostics.shared.isDraining }

    func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        await LocationEngine.set(latitude: latitude, longitude: longitude, pairingPath: pairingPath, deviceIP: deviceIP)
    }

    func clear(pairingPath: String?, deviceIP: String?) async -> Result<Void, LocationEngineError> {
        await LocationEngine.clear(pairingPath: pairingPath, deviceIP: deviceIP)
    }

    func validateConnection(pairingPath: String, deviceIP: String) async -> Result<Void, LocationEngineError> {
        await LocationEngine.validateConnection(pairingPath: pairingPath, deviceIP: deviceIP)
    }

    func cancelPendingPreparation() { LocationEngine.cancelPendingPreparation() }
}
