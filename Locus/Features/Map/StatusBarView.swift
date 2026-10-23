import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject private var session: SpoofSession
    @ObservedObject private var diagnostics = TunnelDiagnostics.shared

    private var title: String {
        if diagnostics.isDraining { return L10n.tr("Native operation still finishing") }
        if session.restorationRequired && session.status == .idle {
            return L10n.tr("System location restoration is not confirmed")
        }
        switch session.status {
        case .idle: return diagnostics.state == .reachable || diagnostics.state == .ready ? diagnostics.statusLabel : L10n.tr("Not Spoofing")
        case .connecting: return L10n.tr("Connecting…")
        case .active: return L10n.tr("Spoofing")
        case .reconnecting: return L10n.tr("Reconnecting…")
        case .stopping: return L10n.tr("Stopping…")
        case .dropped: return L10n.tr("Interrupted — check connection")
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                statusLabel
                Spacer(minLength: 8)
                coordinateLabel
            }
            VStack(alignment: .leading, spacing: 6) {
                statusLabel
                coordinateLabel.padding(.leading, 35)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
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
    private var coordinateLabel: some View {
        if session.status == .active, let point = session.simulated {
            Text(String(format: "%.4f, %.4f", point.latitude, point.longitude))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var statusSymbol: String {
        if (session.restorationRequired && session.status == .idle) || session.status.isDropped {
            return "exclamationmark.triangle.fill"
        }
        switch session.status {
        case .active: return "location.fill"
        case .connecting, .reconnecting, .stopping: return "arrow.triangle.2.circlepath"
        default: return "circle.dotted"
        }
    }

    private var statusColor: Color {
        if (session.restorationRequired && session.status == .idle) || session.status.isDropped {
            return LocusTheme.statusWarn
        }
        return session.status == .active ? LocusTheme.statusGood : LocusTheme.accent
    }
}
