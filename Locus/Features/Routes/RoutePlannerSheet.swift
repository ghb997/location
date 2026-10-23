import CoreLocation
import SwiftUI

struct RoutePlannerSheet: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @State private var remainingDistances: [Double] = []
    @Binding var start: CLLocationCoordinate2D?
    @Binding var end: CLLocationCoordinate2D?
    @Binding var isRouting: Bool
    @Binding var selectedSegmentIndex: Int
    @Binding var importSystem: CoordinateSystem
    var tracks: [RouteTrack]
    var onSelectTrack: (UUID) -> Void
    var onBuild: () -> Void
    var onPlay: () -> Void
    var onPreviewDraft: () -> Void
    var onShowCurrentRoute: () -> Void
    var onImportGPX: () -> Void
    var onExportGPX: () -> Void
    var onUseDrawn: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if let issue = session.routeStorageIssue {
                    Section { Text(issue).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Label(L10n.tr("Routes reopen paused at their last confirmed progress."), systemImage: "pause.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(L10n.tr("Selected route")) {
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
                        Button(L10n.tr("Preview selected route")) {
                            onPreviewDraft()
                            dismiss()
                        }
                        Button(L10n.tr("Start selected route"), action: onPlay)
                            .disabled(!session.canWrite)
                    } else {
                        Text(L10n.tr("Build, draw or import a route first."))
                            .foregroundStyle(.secondary)
                    }
                }
                if let current = session.currentRoute {
                    Section(L10n.tr("Current route")) {
                        Text(current.name).font(.headline)
                        Text(L10n.tr("Previewing another route keeps this route and its progress."))
                            .font(.footnote).foregroundStyle(.secondary)
                        Button(L10n.tr("Show current route")) {
                            onShowCurrentRoute()
                            dismiss()
                        }
                        RoutePlaybackControls()
                    }
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
            .scrollContentBackground(.hidden)
            .background { LocusSheetBackground() }
            .navigationTitle(L10n.tr("Routes"))
            .task(id: session.routeDraftRevision) {
                remainingDistances = []
                guard let track = session.draftTrack else { remainingDistances = []; return }
                let preparation = Task.detached(priority: .userInitiated) { try RouteDisplayGeometry(track: track).remainingDistances }
                do {
                    let distances = try await withTaskCancellationHandler { try await preparation.value } onCancel: { preparation.cancel() }
                    guard !Task.isCancelled else { return }
                    remainingDistances = distances
                } catch { }
            }
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
        guard remainingDistances.indices.contains(index) else { return "—" }
        let meters = remainingDistances[index]
        return String(format: "%.2f km", meters / 1000)
    }
}
