import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var host: PairOnDeviceService
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var diagnostics = TunnelDiagnostics.shared
    @AppStorage(TunnelConfig.automaticPortKey) private var automaticPort = true
    @AppStorage(CoordinateSettings.mapKey) private var mapSystem = "wgs84"
    @AppStorage(CoordinateSettings.serviceKey) private var serviceSystem = "wgs84"
    @AppStorage(SilentAudioKeepAlive.preferenceKey) private var pairingAudio = false
    @State private var portText = String(TunnelConfig.port)
    @State private var showCoordinates = false
    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text(pairing.hasPairingFile ? L10n.tr("RPPairing file installed") : L10n.tr("No pairing file"))
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Toggle(L10n.tr("Keep pairing active with silent audio"), isOn: $pairingAudio)
                        Text(L10n.tr("Optional: play silent audio only while pairing in Settings. It stops when pairing finishes or is cancelled."))
                            .font(.footnote).foregroundStyle(.secondary)
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label(L10n.tr("Pair on this iPhone"), systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button(L10n.tr("Import RPPairing file…")) { showImporter = true }
                    Button(L10n.tr("Paste RPPairing from clipboard")) {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button(L10n.tr("Remove pairing file"), role: .destructive) {
                            do { try pairing.removePairing() }
                            catch { session.lastError = error.localizedDescription }
                        }
                    }
                } header: {
                    Text(L10n.tr("Developer pairing"))
                } footer: {
                    Text(supportsOnDevicePairing
                         ? L10n.tr("On iOS 27, use Pair on this iPhone — no computer. Locus advertises a pairable host; confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On older iOS, import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). LiveContainer: enable Fix File Picker on Locus, or use Paste / Share → LiveContainer → Locus.")
                         : L10n.tr("Import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). If the file picker fails (common in LiveContainer), enable Fix File Picker on the app, share the file into LiveContainer → Locus, or copy the plist and use Paste."))
                }
                .disabled(session.canStop || host.isWorkerRunning)

                Section {
                    TextField(L10n.tr("Device tunnel IP"), text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            saveTunnelIP()
                        }
                    Toggle(L10n.tr("Discover service port automatically"), isOn: $automaticPort)
                    if !automaticPort {
                        TextField(L10n.tr("Service port (1–65535)"), text: $portText).keyboardType(.numberPad)
                    }
                    LabeledContent(L10n.tr("VPN interface hint")) {
                        Text(LocalDevVPN.isConnected ? L10n.tr("Interface detected") : L10n.tr("No matching interface detected"))
                            .foregroundStyle(.secondary)
                    }
                    Button(L10n.tr("Save tunnel IP")) {
                        saveTunnelIP()
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? L10n.tr("Open LocalDevVPN") : L10n.tr("Get LocalDevVPN (App Store)"),
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text(L10n.tr("Tunnel"))
                } footer: {
                    Text(L10n.tr("Use the device endpoint configured by your loopback VPN, usually 10.7.0.1. A detected VPN interface does not prove the developer service is reachable."))
                }
                .disabled(session.canStop || host.isWorkerRunning)

                if session.canStop {
                    Text(L10n.tr("Stop the current simulation before changing pairing or tunnel settings."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.tr("Connection diagnostics")) {
                    LabeledContent(L10n.tr("Status"), value: diagnostics.statusLabel)
                    if let message = diagnostics.message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button(L10n.tr("Check service connection")) {
                        Task { await diagnostics.check() }
                    }.disabled(session.isBusy || host.isWorkerRunning || diagnostics.isDraining || diagnostics.state == .checking)
                    ShareLink(item: diagnostics.summaryForExport()) {
                        Label(L10n.tr("Share redacted diagnostics"), systemImage: "square.and.arrow.up")
                    }
                    if session.restorationRequired {
                        Button(L10n.tr("Retry restoring system location")) { session.stop(pairing: pairing) }
                            .disabled(!session.canRetryRestore)
                    }
                    Text(L10n.tr("Connection checks do not change your position. Shared diagnostics exclude pairing secrets, PINs and exact coordinates."))
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section(L10n.tr("Coordinates")) {
                    Button(L10n.tr("Enter coordinates…")) { showCoordinates = true }
                    Picker(L10n.tr("Map coordinate compatibility"), selection: $mapSystem) {
                        ForEach(CoordinateSystem.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    .onChange(of: mapSystem) { old, value in
                        if value == CoordinateSystem.gcj02.rawValue, !validateCoverage() { mapSystem = old }
                    }
                    Picker(L10n.tr("Search and road service compatibility"), selection: $serviceSystem) {
                        ForEach(CoordinateSystem.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    .onChange(of: serviceSystem) { old, value in
                        if value == CoordinateSystem.gcj02.rawValue, !validateCoverage() { serviceSystem = old }
                    }
                    Text(L10n.tr("Keep WGS-84 unless a reproducible mainland offset requires GCJ-02 compatibility. Map and service settings are independent; saved coordinates are never rewritten."))
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section(L10n.tr("Background and system location")) {
                    Toggle(L10n.tr("Keep simulation active in background"), isOn: $session.backgroundEnabled)
                    Text(L10n.tr("Background operation needs additional location permission and may still be suspended by iOS. Denying it does not prevent foreground use."))
                        .font(.footnote).foregroundStyle(.secondary)
                    if let fix = session.simulationStartFix {
                        locationFixRow(L10n.tr("Location before simulation"), fix: fix)
                    }
                    if let fix = session.latestFix {
                        locationFixRow(L10n.tr("Latest system location"), fix: fix)
                        Text(fix.isSimulated ? L10n.tr("System reports a simulated fix") : L10n.tr("Latest system fix; GPS restoration needs device verification"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let fix = session.restoredFix {
                        locationFixRow(L10n.tr("Fresh system location after stopping"), fix: fix)
                    }
                    if let issue = session.locationIssue { Text(issue).font(.footnote).foregroundStyle(.secondary) }
                    Button(L10n.tr("Refresh system location")) { session.requestLatestLocation() }
                }

                Section(L10n.tr("Privacy")) {
                    Text(L10n.tr("Fully on-device. Favorites and recents stay in UserDefaults. No analytics, no accounts, nothing uploaded."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.tr("About")) {
                    LabeledContent(L10n.tr("Version"), value: appVersion)
                    LabeledContent(L10n.tr("Engine"), value: L10n.tr("idevice DVT location simulation"))
                    Text(L10n.tr("Locus is free and open source (MIT). Location injection uses the MIT-licensed idevice FFI."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text(L10n.tr("locus, n. — a place. From the Latin for where you are."))
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle(L10n.tr("Settings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Done")) {
                        if session.canStop || saveTunnelIP() { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showCoordinates) {
                CoordinateEntrySheet { coordinate in
                    session.pin = coordinate
                    session.pinSource = .manual
                    dismiss()
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .alert("Locus", isPresented: Binding(
                get: { session.lastError != nil },
                set: { if !$0 { session.lastError = nil } }
            )) {
                Button(L10n.tr("OK"), role: .cancel) { session.lastError = nil }
            } message: {
                Text(session.lastError ?? "")
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }

    @discardableResult
    private func validateCoverage() -> Bool {
        do {
            _ = try OfflineMainlandCoverage.contains(.init(latitude: 39.9, longitude: 116.4))
            return true
        } catch { session.lastError = error.localizedDescription; return false }
    }

    private func locationFixRow(_ title: String, fix: SystemLocationFix) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) { Text(fix.timestamp, style: .relative).font(.caption) }
            Text(L10n.format("Accuracy: ±%.0f m", fix.horizontalAccuracy))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @discardableResult
    private func saveTunnelIP() -> Bool {
        guard automaticPort || TunnelConfig.setPort(portText) else {
            session.lastError = L10n.tr("Enter a service port from 1 to 65535.")
            return false
        }
        guard TunnelConfig.setTargetIP(tunnelIP) else {
            session.lastError = LocationEngineError.invalidIP.localizedDescription
            return false
        }
        tunnelIP = TunnelConfig.targetIP
        return true
    }
}
