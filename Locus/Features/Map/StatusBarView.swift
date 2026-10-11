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
        HStack(spacing: 10) {
            Circle().fill(session.status == .active ? LocusTheme.statusGood : LocusTheme.statusWarn)
                .frame(width: 8, height: 8)
            Text(title).font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            if session.status == .active, let point = session.simulated {
                Text(String(format: "%.4f, %.4f", point.latitude, point.longitude))
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .locusGlass(.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
