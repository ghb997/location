import SwiftUI

struct SetupWelcomePage: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 52
    let appear: Bool
    let supportsOnDevicePairing: Bool
    let onContinue: () -> Void

    var body: some View {
        SetupPageScroll {
            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 20) {
                    Image(systemName: "location.north.circle.fill")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(LocusTheme.accent)
                        .frame(width: 112, height: 112)
                        .locusGlass(.regular, tint: LocusTheme.accent.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                        .opacity(appear ? 1 : 0)
                        .scaleEffect(appear || reduceMotion ? 1 : 0.85)

                    VStack(spacing: 10) {
                        Text("location")
                            .font(.system(size: titleSize, weight: .bold, design: .rounded))
                            .tracking(-1)
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                            .accessibilityAddTraits(.isHeader)

                        Text(supportsOnDevicePairing
                             ? L10n.tr("Teleport your location.\nPair directly on this iPhone.")
                             : L10n.tr("Teleport your location.\nImport a pairing file to get started."))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear || reduceMotion ? 0 : 12)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 32)

                VStack(spacing: 14) {
                    Text(L10n.tr("A short setup — about two minutes."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

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
}
