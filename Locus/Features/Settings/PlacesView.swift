import CoreLocation
import SwiftUI

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var recoveryExport: URL?
    @State private var recoveryIsRecent = false
    @State private var showRecoveryConfirmation = false
    @State private var showResetConfirmation = false
    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""
    @State private var correctionPreview: CoordinateCorrectionPreview?
    @State private var correctionError: String?

    var body: some View {
        NavigationStack {
            List {
                if session.favoritesNeedRecovery { recoverySection(recent: false) }
                if session.recentsNeedRecovery { recoverySection(recent: true) }
                if let recoveryExport {
                    Section {
                        ShareLink(item: recoveryExport) { Label(L10n.tr("Share saved-place recovery file"), systemImage: "square.and.arrow.up") }
                        Text(L10n.tr("This export contains your saved names and coordinates.")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section(L10n.tr("Favorites")) {
                    if !session.favoritesNeedRecovery && session.hasArchivedPlaceData(recent: false) {
                        Button(L10n.tr("Export preserved recovery data")) { recoveryExport = session.exportDamagedPlaces(recent: false, archived: true) }
                    }
                    if session.favorites.isEmpty && !session.favoritesNeedRecovery {
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
                    if !session.recentsNeedRecovery && session.hasArchivedPlaceData(recent: true) {
                        Button(L10n.tr("Export preserved recovery data")) { recoveryExport = session.exportDamagedPlaces(recent: true, archived: true) }
                    }
                    if session.recents.isEmpty && !session.recentsNeedRecovery {
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
            .scrollContentBackground(.hidden)
            .navigationTitle(L10n.tr("Places"))
            .confirmationDialog(L10n.tr("Restore saved-place backup?"), isPresented: $showRecoveryConfirmation, titleVisibility: .visible) {
                Button(L10n.tr("Restore backup")) { session.recoverPlaces(recent: recoveryIsRecent) }
                Button(L10n.tr("Cancel"), role: .cancel) { }
            } message: { Text(L10n.tr("The damaged original is preserved. The list will return to the last readable backup.")) }
            .confirmationDialog(L10n.tr("Start a new saved-place list?"), isPresented: $showResetConfirmation, titleVisibility: .visible) {
                Button(L10n.tr("Preserve original and start new list"), role: .destructive) { session.resetDamagedPlaces(recent: recoveryIsRecent) }
                Button(L10n.tr("Cancel"), role: .cancel) { }
            } message: { Text(L10n.tr("The damaged original is kept in recovery storage. Export it first if you want a separate copy.")) }
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
        .locusSheetBackdrop()
    }

    private func recoverySection(recent: Bool) -> some View {
        Section(recent ? L10n.tr("Recents need recovery") : L10n.tr("Favorites need recovery")) {
            Label(L10n.tr("Saved places could not be read. The original data is protected. Open Places to export or recover it."), systemImage: "exclamationmark.shield")
                .font(.footnote)
            Button(L10n.tr("Prepare recovery export")) { recoveryExport = session.exportDamagedPlaces(recent: recent) }
            if session.canRecoverPlaces(recent: recent) {
                Button(L10n.tr("Restore backup")) { recoveryIsRecent = recent; showRecoveryConfirmation = true }
            }
            Button(L10n.tr("Start a new list")) { recoveryIsRecent = recent; showResetConfirmation = true }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            guard session.canWrite else { return }
            session.selectTarget(place.coordinate, source: place.source)
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
