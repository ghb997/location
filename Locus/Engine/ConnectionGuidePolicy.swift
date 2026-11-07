import Foundation

/// Read-only guidance is derived from structured session state, never from a
/// translated error string. Opening a guide cannot start a connection or write.
enum ConnectionGuidePolicy {
    enum SessionState: Equatable { case idle, connecting, active, reconnecting, stopping, interrupted }
    enum ServiceState: Equatable { case unknown, checking, reachable, ready, failed }
    enum SettingsSection: String, Hashable { case pairing, tunnel, diagnostics, restoration }
    enum Topic: String, Equatable {
        case nativeWaiting, restoration, pairingWaiting, pairing, connecting, reconnecting
        case stopping, interrupted, connectionFailed, unchecked, checking, reachable, ready, active
    }

    struct Snapshot: Equatable {
        var hasPairingFile: Bool
        var nativeDraining = false
        var restorationRequired = false
        var pairingWorkerRunning = false
        var isBusy = false
        var canRetryRestore = false
        var session: SessionState = .idle
        var service: ServiceState = .unknown
    }

    struct Step: Equatable {
        let titleKey: String
        let detailKey: String
    }

    struct Guide: Identifiable, Equatable {
        let topic: Topic
        let titleKey: String
        let summaryKey: String
        let steps: [Step]
        let settingsSection: SettingsSection
        let canCheckConnection: Bool
        let canRestoreLocation: Bool
        var id: String { topic.rawValue }
    }

    static func resolve(_ state: Snapshot) -> Guide {
        // The persisted marker also exists during a healthy live simulation.
        // It requires user recovery only when no live session is progressing.
        let needsRecovery = state.restorationRequired
            && (state.session == .idle || state.session == .interrupted)
        let topic: Topic
        if state.nativeDraining { topic = .nativeWaiting }
        else if needsRecovery { topic = .restoration }
        else if state.pairingWorkerRunning { topic = .pairingWaiting }
        else if !state.hasPairingFile { topic = .pairing }
        else {
            switch state.session {
            case .connecting: topic = .connecting
            case .reconnecting: topic = .reconnecting
            case .stopping: topic = .stopping
            case .active: topic = .active
            case .interrupted: topic = .interrupted
            case .idle:
                switch state.service {
                case .unknown: topic = .unchecked
                case .checking: topic = .checking
                case .reachable: topic = .reachable
                case .ready: topic = .ready
                case .failed: topic = .connectionFailed
                }
            }
        }
        let busy = state.nativeDraining || state.pairingWorkerRunning || state.isBusy
            || state.session == .connecting || state.session == .reconnecting || state.session == .stopping
            || state.service == .checking
        let canCheck = !busy && state.hasPairingFile && !needsRecovery
        let canRestore = needsRecovery && state.hasPairingFile && state.canRetryRestore && !busy
        let content = content(for: topic)
        return Guide(topic: topic, titleKey: content.title, summaryKey: content.summary,
                     steps: content.steps, settingsSection: content.settings,
                     canCheckConnection: canCheck, canRestoreLocation: canRestore)
    }

    private static let tunnelStep = Step(
        titleKey: "Open your developer tunnel",
        detailKey: "Keep the configured loopback tunnel running. A VPN interface alone does not confirm that the developer service is reachable.")
    private static let endpointStep = Step(
        titleKey: "Check the connection settings",
        detailKey: "Match the tunnel IP and port to your tunnel app. Use automatic discovery unless you know the service port.")
    private static let checkStep = Step(
        titleKey: "Check service reachability",
        detailKey: "Run a connection check. It probes the service without changing your location; starting simulation also requires developer-service access.")
    private static let targetStep = Step(
        titleKey: "Review the pending location",
        detailKey: "Check the place name and WGS-84 coordinates in the target card. Selecting a place does not start simulation.")
    private static let stopStep = Step(
        titleKey: "Finish with Stop",
        detailKey: "Stop requests location clearing, then obtains a fresh system fix. Verify your real position in Maps; closing the app is not a restoration check.")
    private static let retryStep = Step(
        titleKey: "Retry location restoration",
        detailKey: "When the native worker is free, tap Retry restoring system location. The recovery marker remains until clearing succeeds.")

    private static func content(for topic: Topic) -> (title: String, summary: String, steps: [Step], settings: SettingsSection) {
        switch topic {
        case .nativeWaiting:
            return ("Wait for the native operation", "The previous request has not finished. New writes remain blocked while it returns.", [
                Step(titleKey: "Keep the connection available", detailKey: "Leave the developer tunnel available while the submitted operation finishes. Repeated taps cannot cancel a native call."),
                Step(titleKey: "Watch the status update", detailKey: "When the waiting state ends, follow the current status. If restoration remains unconfirmed, retry clearing before starting again."),
                Step(titleKey: "Inspect the diagnostics", detailKey: "Connection diagnostics show the current stage and timing. You can share a redacted report if the wait persists.")
            ], .diagnostics)
        case .restoration:
            return ("Confirm location restoration", "A previous simulation still needs a confirmed clear. New simulations remain blocked.", [
                tunnelStep,
                Step(titleKey: "Repair changed connection details", detailKey: "If pairing or the endpoint changed, open restoration settings and repair the connection first. Keep the recovery record until clearing succeeds."),
                retryStep,
                Step(titleKey: "Verify the fresh position", detailKey: "After clearing succeeds, check the fresh system location and confirm your real position in Maps.")
            ], .restoration)
        case .pairingWaiting:
            return ("Finish the pairing attempt", "The native pairing worker is still active. A second attempt must wait for it to finish.", [
                Step(titleKey: "Follow the pairing screen", detailKey: "Return to Developer pairing to follow the current attempt. Cancellation stops the UI workflow; the native listener may still need time to return."),
                Step(titleKey: "Wait before trying again", detailKey: "Start another attempt only after the previous worker has stopped. Do not remove or replace pairing data while it is active.")
            ], .pairing)
        case .pairing:
            return ("Set up developer pairing", "Install an RPPairing file before starting location simulation.", [
                Step(titleKey: "Enable Developer Mode", detailKey: "Enable Developer Mode in iPhone or iPad Settings, then follow the system restart and confirmation steps."),
                Step(titleKey: "Import the correct pairing file", detailKey: "Use an RPPairing file created by idevice_pair. A SideStore lockdown mobiledevicepairing file is a different format."),
                Step(titleKey: "Use the supported pairing entry", detailKey: "Open Developer pairing to import or paste the file. The on-device pairing entry appears only on supported system versions."),
                tunnelStep
            ], .pairing)
        case .connecting, .reconnecting:
            return (topic == .reconnecting ? "Recover the connection" : "Connection in progress",
                    "The app is establishing developer-service access. Wait for the current request before checking again.", [
                tunnelStep,
                Step(titleKey: "Keep movement paused during recovery", detailKey: "A route stays paused after reconnection. Review the last confirmed position and tap Continue when ready."),
                Step(titleKey: "If the connection fails", detailKey: "Open connection diagnostics to check the endpoint and error stage. Stop remains available according to the session state.")
            ], .diagnostics)
        case .stopping:
            return ("Clearing the simulated location", "The clear request runs after any submitted position update. Wait for its result.", [
                tunnelStep,
                Step(titleKey: "Let clearing finish", detailKey: "Keep the tunnel connected until the clear request returns. If it fails, the app retains an unconfirmed-restoration state."),
                Step(titleKey: "Verify the fresh position", detailKey: "After clearing succeeds, check the fresh system location and confirm your real position in Maps.")
            ], .diagnostics)
        case .interrupted, .connectionFailed:
            return ("Check the interrupted connection", "The service could not be reached or a request failed. Review the connection before continuing.", [tunnelStep, endpointStep, checkStep,
                Step(titleKey: "Resume deliberately", detailKey: "A recovered route does not continue automatically. Review its confirmed position before tapping Continue.")
            ], .diagnostics)
        case .unchecked:
            return ("Check the developer service", "The connection has not been checked yet. A tunnel icon is only a hint.", [tunnelStep, endpointStep, checkStep], .tunnel)
        case .checking:
            return ("Connection check in progress", "This check probes the service and does not change your location.", [tunnelStep,
                Step(titleKey: "Wait for the check result", detailKey: "Service reachable confirms the endpoint only. Developer-service readiness is established by the simulation connection.")
            ], .diagnostics)
        case .reachable:
            return ("Service reachable; review your target", "The endpoint responds. Pairing and developer-service access are still required to simulate a location.", [
                targetStep,
                Step(titleKey: "Start when ready", detailKey: "Tap Go to pin to establish the developer connection and apply the selected location. A failed start leaves an error to review."),
                stopStep
            ], .diagnostics)
        case .ready:
            return ("Ready for your next location", "A developer-service request succeeded. Review the target before starting a new simulation.", [targetStep,
                Step(titleKey: "Start when ready", detailKey: "Tap Go to pin to establish the developer connection and apply the selected location. A failed start leaves an error to review."), stopStep
            ], .diagnostics)
        case .active:
            return ("While simulation is active", "The status shows the current simulated position. The target card is the separate location you may apply next.", [targetStep,
                Step(titleKey: "Control route movement", detailKey: "Pause a route before reviewing its progress. After a connection interruption, movement waits for your explicit Continue action."), stopStep
            ], .diagnostics)
        }
    }
}
