import SwiftUI

/// Primary actions live outside the scrolling information stack whenever space
/// permits. A constrained layout can move Joy/Go into that stack and pin Stop.
struct MapActionControls: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    var includesStop = true

    var body: some View {
        LocusGlassContainer(spacing: 10) {
        actionLayout {
            joystickButton
            Button {
                if let pin = session.pin { session.teleport(to: pin, pairing: pairing) }
            } label: {
                Text(L10n.tr("Go to pin"))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .locusActionStyle(prominent: true, tint: LocusTheme.accent)
            .disabled(!session.canWrite || session.pin == nil)
            if includesStop && session.canStop { MapStopControl() }
        }
        }
        .foregroundStyle(LocusTheme.ink)
        .contentShape(Rectangle())
        .onTapGesture { /* Keep taps between actions from selecting the map. */ }
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    private var joystickButton: some View {
        Button {
            if session.joystickActive { session.stopJoystick() }
            else { session.startJoystick(pairing: pairing) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                Text(session.joystickActive ? L10n.tr("On") : L10n.tr("Joy"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .locusActionStyle(prominent: session.joystickActive, tint: LocusTheme.accentSecondary)
        .disabled(!session.joystickActive && !session.canWrite)
        .accessibilityLabel(L10n.tr("Movement joystick"))
        .accessibilityAddTraits(session.joystickActive ? .isSelected : [])
    }
}

struct MapStopControl: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    var body: some View {
        Button { session.stop(pairing: pairing) } label: {
            Text(L10n.tr("Stop"))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .locusActionStyle(prominent: true, tint: LocusTheme.danger)
        .disabled(!session.canRetryRestore)
    }
}
