import SwiftUI

struct MapToolbar: View {
    let drawMode: Bool
    let hasPin: Bool
    let onMapStyle: () -> Void
    let onRoutes: () -> Void
    let onDraw: () -> Void
    let onFavorite: () -> Void
    let onLocate: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                icon("square.3.layers.3d", title: L10n.tr("Map style"), action: onMapStyle)
                icon("point.topleft.down.to.point.bottomright.curvepath", title: L10n.tr("Routes"), action: onRoutes)
                icon(drawMode ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle", title: L10n.tr("Draw route"), action: onDraw)
                    .foregroundStyle(drawMode ? LocusTheme.accentSecondary : .primary)
                if hasPin {
                    icon("star.circle", title: L10n.tr("Add favorite"), action: onFavorite)
                }
            }
            .padding(6)
            .locusGlass(.clear, in: Capsule())
            .contentShape(Capsule())
            Spacer(minLength: 0)
            Button(action: onLocate) {
                Image(systemName: "location.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .locusGlass(.interactive, in: Circle())
            .foregroundStyle(.primary)
            .accessibilityLabel(L10n.tr("Current location"))
        }
    }

    private func icon(_ systemName: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(title)
    }
}
