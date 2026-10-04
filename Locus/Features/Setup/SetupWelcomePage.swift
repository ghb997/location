import SwiftUI

struct SetupWelcomePage: View {
    let appear: Bool
    let supportsOnDevicePairing: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(LocusTheme.accent)
                    .symbolEffect(.pulse, options: .repeating.speed(0.4), isActive: appear)
                    .opacity(appear ? 1 : 0)
                    .scaleEffect(appear ? 1 : 0.85)

                VStack(spacing: 10) {
                    Text("Locus")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .tracking(-0.5)

                    Text(supportsOnDevicePairing
                         ? L10n.tr("Teleport your location.\nPair directly on this iPhone.")
                         : L10n.tr("Teleport your location.\nImport a pairing file to get started."))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(appear ? 1 : 0)
                .offset(y: appear ? 0 : 12)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 14) {
                Text(L10n.tr("A short setup — about two minutes."))
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)

                SetupPrimaryButton(title: L10n.tr("Get started")) {
                    onContinue()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .opacity(appear ? 1 : 0)
        }
    }
}
