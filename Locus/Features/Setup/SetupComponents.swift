import SwiftUI

/// Keep setup usable in landscape, Split View, and accessibility text sizes.
struct SetupPageScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                content()
                    .frame(maxWidth: 560)
                    .frame(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

struct SetupProgressView: View {
    let step: Int
    let total: Int
    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...total, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? LocusTheme.accent : Color.primary.opacity(0.12))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Step %d of %d", step, total))
    }
}

struct SetupPrimaryButton: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let title: String
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            Button(action: action) { label }
                .buttonStyle(.glassProminent)
                .tint(LocusTheme.accent)
                .buttonBorderShape(.capsule)
        } else {
            Button(action: action) {
                label.background(Capsule().fill(LocusTheme.accent))
            }
            .buttonStyle(.plain)
        }
    }

    private var label: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.black)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Capsule())
    }
}

struct SetupStepRow: View {
    let number: Int
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 22, height: 22)
                .background(LocusTheme.accent, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SetupTipRow: View {
    let systemImage: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(LocusTheme.accent)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct SetupImportPairingCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SetupStepRow(number: 1, text: L10n.tr("On your computer, run idevice_pair and create an RPPairing file."))
            SetupStepRow(number: 2, text: L10n.tr("AirDrop / Share into location, or copy the plist text."))
            SetupStepRow(number: 3, text: L10n.tr("Tap Import, or Paste from clipboard if the picker doesn’t work (LiveContainer)."))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
