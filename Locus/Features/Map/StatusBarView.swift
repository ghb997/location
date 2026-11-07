import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @ObservedObject private var diagnostics = TunnelDiagnostics.shared
    var onHelp: () -> Void = {}

    private var title: String {
        if nativeWaiting { return L10n.tr("Native operation still finishing") }
        if session.restorationRequired && session.status == .idle {
            return L10n.tr("System location restoration is not confirmed")
        }
        switch session.status {
        case .idle: return pairing.hasPairingFile ? diagnostics.statusLabel : L10n.tr("No pairing file")
        case .connecting: return L10n.tr("Connecting…")
        case .active: return L10n.tr("Spoofing")
        case .reconnecting: return L10n.tr("Reconnecting…")
        case .stopping: return L10n.tr("Stopping…")
        case .dropped: return L10n.tr("Interrupted — check connection")
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    statusLabel
                    Spacer(minLength: 8)
                    coordinateLabel(wrap: false)
                }
                VStack(alignment: .leading, spacing: 6) {
                    statusLabel
                    coordinateLabel(wrap: true).padding(.leading, 35)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Button(action: onHelp) {
                Image(systemName: "questionmark.circle")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(LocusTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(LocusTheme.accent.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.tr("Connection guide"))
            .accessibilityHint(L10n.tr("Show steps for the current connection state."))
            .accessibilityValue(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private var statusLabel: some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: statusSymbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(statusColor)
                .frame(width: 26, height: 26)
                .background(statusColor.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LocusTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func coordinateLabel(wrap: Bool) -> some View {
        if session.status == .active, let point = session.simulated {
            Text(String(format: "%.4f, %.4f", point.latitude, point.longitude))
                .font(.caption.monospaced())
                .foregroundStyle(LocusTheme.secondaryInk)
                .fixedSize(horizontal: !wrap, vertical: true)
        }
    }

    private var statusSymbol: String {
        if nativeWaiting { return "hourglass" }
        if needsAttention { return "exclamationmark.triangle.fill" }
        switch session.status {
        case .active: return "location.fill"
        case .connecting, .reconnecting, .stopping: return "arrow.triangle.2.circlepath"
        case .idle where diagnostics.state == .checking: return "arrow.triangle.2.circlepath"
        default: return "circle.dotted"
        }
    }

    private var statusColor: Color {
        if nativeWaiting || needsAttention { return LocusTheme.statusWarn }
        return session.status == .active ? LocusTheme.statusGood : LocusTheme.accent
    }

    private var nativeWaiting: Bool { diagnostics.isDraining || diagnostics.state == .draining }

    private var needsAttention: Bool {
        session.status.isDropped || (session.status == .idle
            && (session.restorationRequired || !pairing.hasPairingFile || diagnostics.state == .failed))
    }
}
