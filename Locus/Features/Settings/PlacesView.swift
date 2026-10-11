import CoreLocation
import SwiftUI

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""
    @State private var correctionPreview: CoordinateCorrectionPreview?
    @State private var correctionError: String?

    var body: some View {
        NavigationStack {
            List {
                Section(L10n.tr("Favorites")) {
                    if session.favorites.isEmpty {
                        Text(L10n.tr("Star a pin from the map to save it."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.favorites) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeFavorite(place)
                                } label: {
                                    Label(L10n.tr("Delete"), systemImage: "trash.fill")
                                }
                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
                                    Label(L10n.tr("Rename"), systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                            .contextMenu {
                                if place.isLegacy {
                                    Button(L10n.tr("Interpret legacy coordinates as GCJ-02")) {
                                        previewCorrection(place)
                                    }
                                }
                                if place.canRestore {
                                    Button(L10n.tr("Restore original coordinates")) {
                                        session.restoreFavoriteOriginalCoordinate(place)
                                    }
                                }
                            }
                    }
                }

                Section(L10n.tr("Recents")) {
                    if session.recents.isEmpty {
                        Text(L10n.tr("Teleports show up here."))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label(L10n.tr("Delete"), systemImage: "trash.fill")
                                }
                            }
                            .contextMenu {
                                if place.isLegacy {
                                    Button(L10n.tr("Interpret legacy coordinates as GCJ-02")) {
                                        previewCorrection(place, isRecent: true)
                                    }
                                }
                                if place.canRestore {
                                    Button(L10n.tr("Restore original coordinates")) {
                                        session.restoreRecentOriginalCoordinate(place)
                                    }
                                }
                            }
                    }
                }
            }
            .navigationTitle(L10n.tr("Places"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Done")) { dismiss() }
                }
            }
            .alert(L10n.tr("Rename Favorite"), isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField(L10n.tr("Name"), text: $renameText)
                Button(L10n.tr("Cancel"), role: .cancel) {
                    placeToRename = nil
                }
                Button(L10n.tr("Save")) {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
            } message: {
                Text(L10n.tr("Choose a name you’ll recognize later."))
            }
            .sheet(item: $correctionPreview) { preview in
                correctionSheet(preview)
            }
            .alert(L10n.tr("Coordinate correction"), isPresented: Binding(
                get: { correctionError != nil },
                set: { if !$0 { correctionError = nil } }
            )) {
                Button(L10n.tr("OK"), role: .cancel) { correctionError = nil }
            } message: {
                Text(correctionError ?? "")
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            guard session.canWrite else { return }
            session.pinSource = place.source
            session.teleport(to: place.coordinate, pairing: pairing)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!session.canWrite)
    }

    private func previewCorrection(_ place: SavedPlace, isRecent: Bool = false) {
        do {
            correctionPreview = CoordinateCorrectionPreview(original: place, corrected: try place.correctedFromGCJ02(), isRecent: isRecent)
        } catch {
            correctionError = error.localizedDescription
        }
    }

    private func correctionSheet(_ preview: CoordinateCorrectionPreview) -> some View {
        NavigationStack {
            List {
                Section {
                    Text(preview.original.name)
                    LabeledContent(L10n.tr("Original coordinates"), value: coordinateText(preview.original))
                    LabeledContent(L10n.tr("WGS84 coordinates"), value: coordinateText(preview.corrected))
                    Text(L10n.format("Approximate shift: %.0f m", preview.distance))
                }
                Section {
                    Text(L10n.tr("Only apply this correction if the legacy numbers originally came from GCJ-02. WGS84 points do not need correction. You can restore the original coordinates afterward."))
                        .font(.footnote)
                }
                Section {
                    Button(L10n.tr("Apply coordinate correction")) {
                        if preview.isRecent {
                            session.correctRecentFromGCJ02(preview.original)
                        } else {
                            session.correctFavoriteFromGCJ02(preview.original)
                        }
                        correctionPreview = nil
                    }
                }
            }
            .navigationTitle(L10n.tr("Coordinate correction"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Cancel")) { correctionPreview = nil }
                }
            }
        }
    }

    private func coordinateText(_ place: SavedPlace) -> String {
        String(format: "%.6f, %.6f", place.latitude, place.longitude)
    }
}

private struct CoordinateCorrectionPreview: Identifiable {
    let original: SavedPlace
    let corrected: SavedPlace
    var isRecent: Bool = false
    var id: String { original.id }
    var distance: Double {
        CLLocation(latitude: original.latitude, longitude: original.longitude)
            .distance(from: CLLocation(latitude: corrected.latitude, longitude: corrected.longitude))
    }
}
