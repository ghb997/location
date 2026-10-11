import SwiftUI

struct BottomControlsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool

    private let trayShape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        VStack(spacing: 12) {
            if session.joystickActive {
                JoystickPad { vector in
                    session.updateJoystick(vector: vector)
                }
                .frame(width: 148, height: 148)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack(spacing: 8) {
                ForEach(TravelMode.allCases) { mode in
                    let selected = session.travelMode == mode
                    Button {
                        session.travelMode = mode
                    } label: {
                        Image(systemName: mode.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(selected ? .black : .primary)
                            .frame(width: 44, height: 40)
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
            HStack(spacing: 10) {
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
                            .lineLimit(1)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(session.joystickActive ? .black : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(session.joystickActive ? LocusTheme.accentSecondary : Color.primary.opacity(0.08))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!session.canWrite)
            }
            HStack(spacing: 10) {
                Button {
                    if let pin = session.pin { session.teleport(to: pin, pairing: pairing) }
                } label: {
                    Text(L10n.tr("Go to pin"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12).padding(.horizontal, 10)
                        .background(Capsule().fill(LocusTheme.accent))
                }
                .buttonStyle(.plain)
                .disabled(!session.canWrite || session.pin == nil)
                if session.canStop {
                    Button { session.stop(pairing: pairing) } label: {
                        Text(L10n.tr("Stop"))
                            .font(.subheadline.weight(.bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12).padding(.horizontal, 10)
                            .background(Capsule().fill(LocusTheme.danger))
                    }
                    .buttonStyle(.plain)
                    .disabled(!session.canRetryRestore)
                }
            }
        }
        .padding(14)
        .locusGlass(.regular, in: trayShape)
        // Whole tray absorbs taps so near-misses don't fall through to the map.
        .contentShape(trayShape)
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
