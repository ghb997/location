import SwiftUI

struct SetupVPNPage: View {
    let localDevVPNInstalled: Bool
    let onFinished: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 20)

            VStack(spacing: 22) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(LocusTheme.accent)

                VStack(spacing: 10) {
                    Text(localDevVPNInstalled ? L10n.tr("Connect LocalDevVPN") : L10n.tr("One more app"))
                        .font(.title.weight(.bold))

                    Text(localDevVPNInstalled
                         ? L10n.tr("LocalDevVPN is installed. Open it to turn on the private tunnel Locus needs, then come back here.")
                         : L10n.tr("LocalDevVPN creates a private tunnel Locus uses to talk to your phone’s location system. Install it, turn it on, then you’re ready to teleport."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    if localDevVPNInstalled {
                        SetupTipRow(systemImage: "checkmark.circle.fill", title: L10n.tr("Installed"), detail: L10n.tr("LocalDevVPN is on this iPhone."))
                        SetupTipRow(systemImage: "power.circle.fill", title: L10n.tr("Connect"), detail: L10n.tr("Tap below to open it and start the tunnel. You’ll bounce back to Locus."))
                    } else {
                        SetupTipRow(systemImage: "arrow.down.app.fill", title: L10n.tr("Install"), detail: L10n.tr("Get LocalDevVPN from the App Store."))
                        SetupTipRow(systemImage: "power.circle.fill", title: L10n.tr("Connect"), detail: L10n.tr("Open it and turn the VPN on. Leave the default IP alone."))
                    }
                    SetupTipRow(systemImage: "wifi", title: L10n.tr("First teleport on Wi‑Fi"), detail: L10n.tr("Start your first teleport while on Wi‑Fi. After that, it can keep working on cellular."))
                }
                .padding(18)
                .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    if localDevVPNInstalled {
                        LocalDevVPN.openInstalled()
                    } else {
                        LocalDevVPN.openAppStore()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: localDevVPNInstalled ? "lock.shield.fill" : "apple.logo")
                        Text(localDevVPNInstalled ? L10n.tr("Open LocalDevVPN") : L10n.tr("Get LocalDevVPN"))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(.primary)
                    .locusGlass(.interactive, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                SetupPrimaryButton(title: L10n.tr("I’ve connected it — continue")) {
                    onFinished()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }
}
