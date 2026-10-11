import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var isRouting: Bool
    @Binding var selectedSegmentIndex: Int
    @Binding var importSystem: CoordinateSystem
    var tracks: [RouteTrack]
    var onSelectTrack: (UUID) -> Void
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("Route playback")) {
                    if let track = session.draftTrack {
                        Text(track.name).font(.headline)
                        if tracks.count > 1 {
                            Picker(L10n.tr("Track"), selection: Binding(
                                get: { track.id }, set: onSelectTrack
                            )) {
                                ForEach(tracks) { item in Text(item.name).tag(item.id) }
                            }
                        }
                        if track.segments.count > 1 {
                            Picker(L10n.tr("Start segment"), selection: $selectedSegmentIndex) {
                                ForEach(track.segments.indices, id: \.self) { index in
                                    Text(L10n.format("Segment %d", index + 1)).tag(index)
                                }
                            }
                        }
                        LabeledContent(L10n.tr("Distance"), value: distanceText(track))
                        Text(L10n.tr("Segments are separate. Moving to the next segment requires confirmation."))
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(L10n.tr("Start selected route"), action: onPlay)
                            .disabled(!session.canWrite)
                    } else {
                        Text(L10n.tr("Build, draw or import a route first."))
                            .foregroundStyle(.secondary)
                    }
                    if session.currentRoute != nil { RoutePlaybackControls() }
                }
                Section(L10n.tr("Road route")) {
                    Button(L10n.tr("Use current pin / spoof as start")) { start = session.simulated ?? session.pin }
                    Button(L10n.tr("Use current pin as end")) { end = session.pin }
                    LabeledContent(L10n.tr("Start"), value: coordinateText(start))
                    LabeledContent(L10n.tr("End"), value: coordinateText(end))
                    Button(action: onBuild) {
                        if isRouting { ProgressView().accessibilityLabel(L10n.tr("Starting…")) }
                        else { Label(L10n.tr("Build walk/drive route on roads"), systemImage: "road.lanes") }
                    }.disabled(isRouting)
                    Text(L10n.tr("Cycling uses cycling speed on driving roads; bicycle-specific routing is not available."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(L10n.tr("Play / draw / GPX")) {
                    Button(action: onUseDrawn) {
                        Label(L10n.tr("Use drawn path from map"), systemImage: "pencil.tip")
                    }
                    Picker(L10n.tr("GPX input coordinates"), selection: $importSystem) {
                        ForEach(CoordinateSystem.allCases, id: \.self) { system in Text(system.title).tag(system) }
                    }
                    Text(L10n.tr("Standard GPX uses WGS-84. Select GCJ-02 only for a file known to use it."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Button(action: onImportGPX) { Label(L10n.tr("Import GPX"), systemImage: "square.and.arrow.down") }
                    Button(action: onExportGPX) { Label(L10n.tr("Export current track"), systemImage: "square.and.arrow.up") }
                        .disabled(session.draftTrack == nil)
                }
            }
            .navigationTitle(L10n.tr("Routes"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.tr("Done")) { dismiss() } }
            }
        }
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D?) -> String {
        guard let coordinate else { return "—" }
        return String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private func distanceText(_ track: RouteTrack) -> String {
        let index = min(max(0, selectedSegmentIndex), max(0, track.segments.count - 1))
        let meters = track.segments.dropFirst(index).reduce(0.0) { total, segment in
            total + zip(segment.coordinates, segment.coordinates.dropFirst()).reduce(0.0) {
                $0 + RouteGeometry.distance(from: $1.0, to: $1.1)
            }
        }
        return String(format: "%.2f km", meters / 1000)
    }
}

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
