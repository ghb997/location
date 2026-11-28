import SwiftUI

struct SetupVPNPage: View {
    let onFinished: () -> Void
    @ObservedObject private var vpn = BuiltInVPN.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var tunnelInterfaceDetected = false

    var body: some View {
        SetupPageScroll {
            LocusGlassContainer(spacing: 16) {
                VStack(spacing: 0) {
                    Spacer(minLength: 20)

                    VStack(spacing: 22) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(LocusTheme.accent)
                            .accessibilityHidden(true)

                        VStack(spacing: 10) {
                            Text(L10n.tr("Connect the built-in VPN"))
                                .font(.title.weight(.bold))
                                .multilineTextAlignment(.center)
                                .accessibilityAddTraits(.isHeader)

                            Text(L10n.tr("The tunnel connects location to developer services on this device. The first time you connect, tap Allow when iOS asks to add a VPN configuration."))
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SetupTipRow(systemImage: "lock.shield", title: L10n.tr("Built-in VPN"), detail: vpn.statusTitle)
                            SetupTipRow(systemImage: "wifi", title: L10n.tr("First teleport on Wi‑Fi"), detail: L10n.tr("Start your first teleport while on Wi‑Fi. After that, it can keep working on cellular."))
                        }
                        .padding(18)
                        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 28)

                    VStack(spacing: 12) {
                        if let message = vpn.errorMessage {
                            Text(message).font(.footnote).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        if vpn.matchesEndpoint {
                            SetupPrimaryButton(title: L10n.tr("Continue to map"), action: onFinished)
                        } else if vpn.isConnected {
                            Text(L10n.tr("The VPN is connected, but the configured endpoint has no matching tunnel route."))
                                .font(.footnote).foregroundStyle(.secondary)
                            Button(L10n.tr("Disconnect built-in VPN")) { vpn.disconnect() }
                            Button(L10n.tr("Set up later"), action: onFinished)
                        } else {
                            SetupPrimaryButton(title: vpn.isTransitioning ? vpn.statusTitle : L10n.tr("Connect the built-in VPN")) {
                                Task { await vpn.connect() }
                            }
                            .disabled(vpn.isTransitioning)
                            Button(tunnelInterfaceDetected ? L10n.tr("Continue with existing tunnel") : L10n.tr("Set up later"), action: onFinished)
                        }
                        if vpn.errorMessage != nil {
                            Button(L10n.tr("Use external LocalDevVPN")) { LocalDevVPN.openOrInstall() }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                }
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await vpn.refresh()
            tunnelInterfaceDetected = LocalDevVPN.isConnected
        }
        .onChange(of: vpn.status) { _, _ in tunnelInterfaceDetected = LocalDevVPN.isConnected }
    }
}
