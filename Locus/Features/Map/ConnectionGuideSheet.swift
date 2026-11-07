import SwiftUI

/// Display-only content with explicit actions. Showing this sheet never starts
/// a check, repair or simulation; the owner supplies the live session gates.
struct ConnectionGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    let guide: ConnectionGuidePolicy.Guide
    let onOpenSettings: (ConnectionGuidePolicy.SettingsSection) -> Void
    let onCheckConnection: () -> Void
    let onRestoreLocation: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    VStack(spacing: 14) {
                        ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                            stepRow(step, number: index + 1)
                        }
                    }
                    actions
                }
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background { LocusSheetBackground() }
            .navigationTitle(L10n.tr("Connection guide"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.tr("Done")) { dismiss() }
                }
            }
        }
        .locusSheetBackdrop()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(LocusTheme.accent)
                .frame(width: 54, height: 54)
                .background(LocusTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityHidden(true)
            Text(L10n.tr(guide.titleKey))
                .font(.title2.weight(.bold))
                .foregroundStyle(LocusTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.tr(guide.summaryKey))
                .font(.subheadline)
                .foregroundStyle(LocusTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepRow(_ step: ConnectionGuidePolicy.Step, number: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(LocusTheme.accent)
                .frame(minWidth: 30, minHeight: 30)
                .background(LocusTheme.accent.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.tr(step.titleKey))
                    .font(.headline)
                    .foregroundStyle(LocusTheme.ink)
                Text(L10n.tr(step.detailKey))
                    .font(.subheadline)
                    .foregroundStyle(LocusTheme.secondaryInk)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(LocusTheme.accent.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if guide.topic == .restoration {
                Button(action: onRestoreLocation) {
                    actionLabel(L10n.tr("Retry restoring system location"), symbol: "location.circle")
                }
                .locusActionStyle(prominent: true)
                .disabled(!guide.canRestoreLocation)
            } else if showsCheckButton {
                Button(action: onCheckConnection) {
                    actionLabel(L10n.tr("Check service connection"), symbol: "network")
                }
                .locusActionStyle(prominent: true)
                .disabled(!guide.canCheckConnection)
            }
            Button { onOpenSettings(guide.settingsSection) } label: {
                actionLabel(L10n.tr(settingsTitleKey), symbol: "slider.horizontal.3")
            }
            .locusActionStyle()
        }
    }

    private func actionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private var settingsTitleKey: String {
        switch guide.settingsSection {
        case .pairing: return "Open pairing settings"
        case .tunnel: return "Open tunnel settings"
        case .diagnostics: return "Open connection diagnostics"
        case .restoration: return "Open restoration settings"
        }
    }

    private var showsCheckButton: Bool {
        // Heartbeat writes can briefly change the enabled gate. Keep the action
        // in place so the sheet does not jump on every busy-state update.
        switch guide.topic {
        case .unchecked, .checking, .reachable, .ready, .active, .interrupted, .connectionFailed: return true
        default: return false
        }
    }

    private var symbol: String {
        switch guide.topic {
        case .nativeWaiting, .pairingWaiting, .checking, .connecting, .reconnecting, .stopping: return "hourglass"
        case .restoration: return "location.circle"
        case .pairing: return "link"
        case .connectionFailed, .interrupted: return "exclamationmark.triangle"
        case .active: return "location.fill"
        default: return "checklist"
        }
    }
}
