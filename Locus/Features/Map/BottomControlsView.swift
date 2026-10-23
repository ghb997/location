import SwiftUI

struct BottomControlsView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool

    private let trayShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        LocusGlassContainer(spacing: 16) {
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
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(TravelMode.allCases) { mode in
                    let selected = session.travelMode == mode
                    Button {
                        session.travelMode = mode
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selected ? .black : .primary)
                            .frame(minWidth: 48, minHeight: 44)
                            .background(
                                Capsule().fill(selected ? LocusTheme.accent : Color.primary.opacity(0.08))
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }

            if session.currentRoute != nil { RoutePlaybackControls() }
            HStack(spacing: 12) {
                trayIcon("gearshape.fill") { showSettings = true }
                    .accessibilityLabel(L10n.tr("Settings"))
                trayIcon("star.fill") { showPlaces = true }
                    .accessibilityLabel(L10n.tr("Places"))

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
                    .foregroundStyle(session.joystickActive ? .black : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(session.joystickActive ? LocusTheme.accentSecondary : Color.primary.opacity(0.08))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!session.canWrite)
            }
            actionLayout {
                Button {
                    if let pin = session.pin { session.teleport(to: pin, pairing: pairing) }
                } label: {
                    Text(L10n.tr("Go to pin"))
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .padding(.horizontal, 14)
                        .background(Capsule().fill(LocusTheme.accent))
                }
                .buttonStyle(.plain)
                .disabled(!session.canWrite || session.pin == nil)
                if session.canStop {
                    Button { session.stop(pairing: pairing) } label: {
                        Text(L10n.tr("Stop"))
                            .font(.headline).foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                            .padding(.horizontal, 14)
                            .background(Capsule().fill(LocusTheme.danger))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canRetryRestore)
                }
            }
        }
        .padding(16)
        .locusGlass(.regular, in: trayShape)
        // Whole tray absorbs taps so near-misses don't fall through to the map.
        .contentShape(trayShape)
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    private func trayIcon(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.primary.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
