import SwiftUI

struct BottomControlsView: View {
    @Namespace private var modeSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var session: SpoofSession
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool
    var joystickAvailableHeight: CGFloat = 148

    private var joystickSize: CGFloat { min(148, max(0, joystickAvailableHeight)) }

    var body: some View {
        LocusGlassContainer(spacing: 10) {
            VStack(spacing: 12) {
                if session.joystickActive && joystickSize >= 50 {
                    // At full travel the thumb reaches the 148-point outer frame.
                    // Scale that frame and the 132-point glass circle together.
                    JoystickPad(diameter: joystickSize * 132 / 148) { vector in
                        session.updateJoystick(vector: vector)
                    }
                    .frame(width: joystickSize, height: joystickSize)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: JoystickLayoutPreferenceKey.self,
                                value: JoystickLayout(frame: geometry.frame(in: .global)))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                controls
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let pin = session.pin {
                TargetPlaceCard(
                    coordinate: pin,
                    name: session.pinName,
                    address: session.pinAddress,
                    isFavorite: session.isFavoriteTarget,
                    canSaveFavorite: session.canSaveTargetFavorite,
                    onFavorite: {
                        session.addFavorite(
                            name: session.suggestedFavoriteName(for: pin, fallback: session.pinName),
                            coordinate: pin)
                    },
                    onClear: { session.selectTarget(nil) }
                )
            }

            HStack(spacing: 10) {
                modeSelector
                IconButton(systemName: "gearshape.fill") { showSettings = true }
                    .accessibilityLabel(L10n.tr("Settings"))
                IconButton(systemName: "star.fill") { showPlaces = true }
                    .accessibilityLabel(L10n.tr("Places"))
            }

            if session.currentRoute != nil {
                RoutePlaybackControls()
                    .padding(14)
                    .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

        }
        .foregroundStyle(LocusTheme.ink)
        .contentShape(Rectangle())
        .onTapGesture { /* Absorb near-misses between actions instead of dropping a map pin. */ }
    }

    private var modeSelector: some View {
        HStack(spacing: 0) {
            ForEach(TravelMode.allCases) { mode in
                let selected = session.travelMode == mode
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { session.travelMode = mode }
                } label: {
                    Image(systemName: mode.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(selected ? LocusTheme.accent : LocusTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minWidth: 44, minHeight: 44)
                        .background {
                            if selected {
                                Capsule().fill(LocusTheme.accent.opacity(0.14))
                                    .overlay(Capsule().stroke(LocusTheme.accent.opacity(0.22), lineWidth: 1))
                                    .matchedGeometryEffect(id: "travel-mode", in: modeSelection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .locusGlass(.regular, in: Capsule())
    }

}
