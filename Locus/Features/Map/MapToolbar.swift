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
        LocusGlassContainer(spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    icon("square.3.layers.3d", title: L10n.tr("Map style"), action: onMapStyle)
                    icon("point.topleft.down.to.point.bottomright.curvepath", title: L10n.tr("Routes"), action: onRoutes)
                    icon(drawMode ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle", title: L10n.tr("Draw route"), selected: drawMode, action: onDraw)
                    if hasPin {
                        icon("star.circle", title: L10n.tr("Add favorite"), action: onFavorite)
                    }
                }
                .padding(4)
                .locusGlass(.regular, in: Capsule())
                .contentShape(Capsule())
                Spacer(minLength: 0)
                IconButton(systemName: "location.fill", action: onLocate)
                    .accessibilityLabel(L10n.tr("Current location"))
            }
        }
    }

    private func icon(_ systemName: String, title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(selected ? LocusTheme.accentSecondary : LocusTheme.ink)
                .background {
                    if selected {
                        Circle().fill(LocusTheme.accentSecondary.opacity(0.12))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
