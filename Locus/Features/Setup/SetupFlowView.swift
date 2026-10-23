import SwiftUI
import UniformTypeIdentifiers

/// First-run walkthrough: welcome → pairing → LocalDevVPN → map.
/// Skipped when `SetupGate.isComplete` (see `LocusApp`).
struct SetupFlowView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession

    var onFinished: () -> Void

    @State private var step: Step
    @State private var appear = false
    @State private var showImporter = false
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Int, CaseIterable {
        case welcome
        case pairing
        case vpn
    }

    init(initialStep: Step = .welcome, onFinished: @escaping () -> Void) {
        _step = State(initialValue: initialStep)
        self.onFinished = onFinished
    }

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    var body: some View {
        ZStack {
            SetupBackground()

            VStack(spacing: 0) {
                SetupProgressView(step: step.rawValue + 1, total: Step.allCases.count)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                Group {
                    switch step {
                    case .welcome:
                        SetupWelcomePage(appear: appear, supportsOnDevicePairing: supportsOnDevicePairing) {
                            SetupGate.markInProgress()
                            move(to: .pairing)
                        }
                    case .pairing:
                        if supportsOnDevicePairing {
                            pairingPage
                        } else {
                            SetupPageScroll { pairingPage }
                        }
                    case .vpn:
                        SetupVPNPage(localDevVPNInstalled: localDevVPNInstalled, onFinished: onFinished)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(reduceMotion ? .opacity : .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
            .frame(maxWidth: 608)
            .padding(.bottom, 8)
        }
        .foregroundStyle(LocusTheme.ink)
        .preferredColorScheme(.light)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86), value: step)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.7)) { appear = true }
            localDevVPNInstalled = LocalDevVPN.isInstalled
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
        }
        .onChange(of: step) { _, newStep in
            if newStep == .vpn {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
        }
        .onChange(of: pairing.hasPairingFile) { _, hasFile in
            if hasFile, step == .welcome || step == .pairing {
                SetupGate.markInProgress()
                move(to: .vpn)
            }
        }
        .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                        move(to: .vpn)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
        .alert("location", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button(L10n.tr("OK"), role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    // MARK: - Pairing

    private func move(to nextStep: Step) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86)) {
            step = nextStep
        }
    }

    private var pairingPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Connect this iPhone"))
                    .font(.title.weight(.bold))
                Text(supportsOnDevicePairing
                     ? L10n.tr("location needs a one-time pairing so it can set your location. You’ll confirm a short code in Settings.")
                     : L10n.tr("Import a pairing file from your computer — location uses it to set your location securely on this device."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)

            if supportsOnDevicePairing {
                PairOnDeviceView(mode: .embedded) {
                    move(to: .vpn)
                }
                .environmentObject(pairing)
            } else {
                SetupImportPairingCard()
                    .padding(.horizontal, 24)
                Spacer(minLength: 28)
                VStack(spacing: 12) {
                    SetupPrimaryButton(title: L10n.tr("Import pairing file")) {
                        showImporter = true
                    }
                    Button {
                        do {
                            try pairing.importPairingFromClipboard()
                            move(to: .vpn)
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    } label: {
                        Text(L10n.tr("Paste from clipboard"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .locusGlass(.interactive, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

}

// MARK: - Gate

enum SetupGate {
    static let defaultsKey = "locus.setupComplete"
    static let inProgressKey = "locus.setupInProgress"

    static var isComplete: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static var isInProgress: Bool {
        UserDefaults.standard.bool(forKey: inProgressKey)
    }

    static func markInProgress() {
        UserDefaults.standard.set(true, forKey: inProgressKey)
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
        UserDefaults.standard.set(false, forKey: inProgressKey)
    }

    /// Already paired *during* this walkthrough → LocalDevVPN page.
    /// Fresh install → welcome. Already-paired upgrades are handled in `LocusApp`.
    static func initialStep(hasPairingFile: Bool) -> SetupFlowView.Step {
        if hasPairingFile, isInProgress { return .vpn }
        return .welcome
    }
}
