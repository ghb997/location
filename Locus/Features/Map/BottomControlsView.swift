import SwiftUI

struct BottomControlsView: View {
    @Namespace private var modeSelection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool

    var body: some View {
        LocusGlassContainer(spacing: 10) {
            VStack(spacing: 12) {
                if session.joystickActive {
                    JoystickPad { vector in
                        session.updateJoystick(vector: vector)
                    }
                    .frame(width: 148, height: 148)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                controls
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                modeSelector
                IconButton(systemName: "gearshape.fill") { showSettings = true }
                    .accessibilityLabel(L10n.tr("Settings"))
                IconButton(systemName: "star.fill") { showPlaces = true }
                    .accessibilityLabel(L10n.tr("Places"))
            }

            if session.currentRoute != nil {
                RoutePlaybackControls()
                    .padding(16)
                    .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }

            // Each action has its own glass surface, so the map can refract through
            // the spaces between controls instead of a second glass backing tray.
            actionLayout {
                joystickButton
                Button {
                    if let pin = session.pin { session.teleport(to: pin, pairing: pairing) }
                } label: {
                    Text(L10n.tr("Go to pin"))
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                }
                .locusActionStyle(prominent: true, tint: LocusTheme.accent)
                .disabled(!session.canWrite || session.pin == nil)
                if session.canStop {
                    Button { session.stop(pairing: pairing) } label: {
                        Text(L10n.tr("Stop"))
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    }
                    .locusActionStyle(prominent: true, tint: LocusTheme.danger)
                    .disabled(!session.canRetryRestore)
                }
            }
        }
        .foregroundStyle(LocusTheme.ink)
        .contentShape(Rectangle())
        .onTapGesture { /* Absorb near-misses between actions instead of dropping a map pin. */ }
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
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

    private var joystickButton: some View {
        Button {
            if session.joystickActive {
                session.stopJoystick()
            } else {
                session.startJoystick(pairing: pairing)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                Text(session.joystickActive ? L10n.tr("On") : L10n.tr("Joy"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
        }
        .locusActionStyle(prominent: session.joystickActive, tint: LocusTheme.accentSecondary)
        .disabled(!session.canWrite)
        .accessibilityLabel(L10n.tr("Movement joystick"))
        .accessibilityAddTraits(session.joystickActive ? .isSelected : [])
    }
}
