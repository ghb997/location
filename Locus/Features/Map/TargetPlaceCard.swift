import CoreLocation
import SwiftUI

/// A preview of the selected target. Applying it remains an explicit map action.
struct TargetPlaceCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let coordinate: CLLocationCoordinate2D
    let name: String?
    let address: String?
    let isFavorite: Bool
    let canSaveFavorite: Bool
    let onFavorite: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.tr("Pending target"), systemImage: "mappin.and.ellipse")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(LocusTheme.accent)
                    Text(displayName)
                        .font(.headline)
                        .foregroundStyle(LocusTheme.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 2) {
                    Button(action: onFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isFavorite ? LocusTheme.accentSecondary : LocusTheme.accent)
                            .frame(width: 44, height: 44)
                            .background(LocusTheme.accent.opacity(0.08), in: Circle())
                            .contentShape(Circle())
                    }
                    .disabled(isFavorite || !canSaveFavorite)
                    .accessibilityLabel(isFavorite ? L10n.tr("Saved to favorites") : L10n.tr("Save this place"))

                    Button(action: onClear) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(LocusTheme.secondaryInk)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .accessibilityLabel(L10n.tr("Clear pending target"))
                }
                .buttonStyle(.plain)
            }

            if let address, !address.isEmpty {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(LocusTheme.secondaryInk)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    coordinates.fixedSize()
                    Spacer(minLength: 4)
                    favoriteState.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    coordinates
                    favoriteState
                }
            }
        }
        .padding(14)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
    }

    private var displayName: String {
        guard let name, !name.isEmpty else { return L10n.tr("Selected location") }
        return name
    }

    private var coordinateText: String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }

    private var coordinates: some View {
        Text("WGS-84 · " + coordinateText)
            .font(.caption2.monospaced())
            .foregroundStyle(LocusTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(L10n.format("WGS-84 coordinates: %@", coordinateText))
    }

    private var favoriteState: some View {
        Text(isFavorite ? L10n.tr("Saved to favorites")
             : (canSaveFavorite ? L10n.tr("Not saved yet") : L10n.tr("Favorites need recovery")))
            .font(.caption2.weight(.medium))
            .foregroundStyle(isFavorite ? LocusTheme.accentSecondary : LocusTheme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
    }
}
