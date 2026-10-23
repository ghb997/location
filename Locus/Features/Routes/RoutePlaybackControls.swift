import SwiftUI
import CoreLocation

struct RoutePlaybackControls: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var confirmNextSegment = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: session.routeProgress).accessibilityLabel(L10n.tr("Route progress"))
            HStack {
                Text(stateTitle).font(.caption)
                Spacer()
                Text(session.routeProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
            }
            if session.routeState == .playing || (session.routeState == .idle && session.isBusy) {
                Button(L10n.tr("Pause route")) { session.pauseRoute() }
            } else if session.routeState == .paused {
                Text(L10n.tr("The route stays paused after reconnecting. Continue when ready."))
                    .font(.caption).foregroundStyle(.secondary)
                Button(L10n.tr("Continue route")) { session.resumeRoute(pairing: pairing) }.disabled(!session.canWrite)
            } else if session.routeState == .awaitingNextSegment {
                Text(L10n.tr("The next segment may start far away. Continuing moves directly to its first point."))
                    .font(.caption).foregroundStyle(.secondary)
                if let next = nextSegmentStart {
                    Text(L10n.format("Next segment begins at %@, %.0f m from the current position.",
                         String(format: "%.5f, %.5f", next.latitude, next.longitude),
                         session.simulated.map { RouteGeometry.distance(from: $0, to: next) } ?? 0))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button(L10n.tr("Move to next segment and continue")) { confirmNextSegment = true }
                    .disabled(!session.canWrite)
            }
        }
        .confirmationDialog(L10n.tr("Move to next segment?"), isPresented: $confirmNextSegment, titleVisibility: .visible) {
            Button(L10n.tr("Continue")) { session.nextRouteSegment(pairing: pairing) }
            Button(L10n.tr("Cancel"), role: .cancel) {}
        }
    }

    private var nextSegmentStart: CLLocationCoordinate2D? {
        guard let track = session.currentRoute else { return nil }
        guard let index = track.segments.indices.first(where: { $0 > session.routeSegmentIndex && track.segments[$0].canPlay }) else { return nil }
        return track.segments[index].coordinates.first
    }

    private var stateTitle: String {
        switch session.routeState {
        case .idle: return session.isBusy ? L10n.tr("Preparing route…") : L10n.tr("Route ready")
        case .playing: return L10n.tr("Route moving")
        case .pausing: return L10n.tr("Waiting for the last position update…")
        case .paused: return L10n.tr("Route paused")
        case .awaitingNextSegment: return L10n.tr("Waiting for next segment")
        case .completed: return L10n.tr("Route completed")
        }
    }
}
