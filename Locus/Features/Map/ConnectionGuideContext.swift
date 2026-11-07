import SwiftUI

/// Platform adaptation stays outside the testable policy and the rendering view.
@MainActor
enum ConnectionGuideContext {
    static func guide(session: SpoofSession, pairing: PairingStore, diagnostics: TunnelDiagnostics,
                      pairingWorkerRunning: Bool) -> ConnectionGuidePolicy.Guide {
        let sessionState: ConnectionGuidePolicy.SessionState
        switch session.status {
        case .idle: sessionState = .idle
        case .connecting: sessionState = .connecting
        case .active: sessionState = .active
        case .reconnecting: sessionState = .reconnecting
        case .stopping: sessionState = .stopping
        case .dropped: sessionState = .interrupted
        }
        let serviceState: ConnectionGuidePolicy.ServiceState
        switch diagnostics.state {
        case .unknown, .draining: serviceState = .unknown
        case .checking: serviceState = .checking
        case .reachable: serviceState = .reachable
        case .ready: serviceState = .ready
        case .failed: serviceState = .failed
        }
        return ConnectionGuidePolicy.resolve(.init(
            hasPairingFile: pairing.hasPairingFile,
            nativeDraining: diagnostics.isDraining || diagnostics.state == .draining,
            restorationRequired: session.restorationRequired,
            pairingWorkerRunning: pairingWorkerRunning,
            isBusy: session.isBusy,
            canRetryRestore: session.canRetryRestore,
            session: sessionState,
            service: serviceState
        ))
    }
}
