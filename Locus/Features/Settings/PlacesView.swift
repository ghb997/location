import SwiftUI

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""

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
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
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
    }
}
