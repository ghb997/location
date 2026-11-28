import NetworkExtension
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var initialSection: ConnectionGuidePolicy.SettingsSection? = nil
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var host: PairOnDeviceService
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var diagnostics = TunnelDiagnostics.shared
    @State private var automaticPort = TunnelConfig.automaticPort
    @AppStorage(CoordinateSettings.mapKey) private var mapSystem = "wgs84"
    @AppStorage(CoordinateSettings.serviceKey) private var serviceSystem = "wgs84"
    @AppStorage(SilentAudioKeepAlive.preferenceKey) private var pairingAudio = false
    @State private var portText = String(TunnelConfig.port)
    @State private var showCoordinates = false
    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @ObservedObject private var vpn = BuiltInVPN.shared
    @State private var tunnelInterfaceDetected = false
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

    private var canEditConnection: Bool {
        !host.isWorkerRunning && !session.isBusy && !diagnostics.isDraining
            && (!session.canStop || session.isRepairingRecovery)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            List {
                if session.restorationRequired {
                    Section(L10n.tr("Repair restoration connection")) {
                        Text(L10n.tr("If the pairing file or tunnel endpoint has changed, repair the connection here, then clear the previous simulation. New simulations remain blocked until restoration succeeds."))
                            .font(.footnote).foregroundStyle(.secondary)
                        if session.isRepairingRecovery {
                            Button(L10n.tr("Save connection and restore location")) {
                                guard saveTunnelIP() else { return }
                                session.endRecoveryRepair()
                                session.stop(pairing: pairing)
                            }.disabled(!canEditConnection)
                        } else {
                            Button(L10n.tr("Repair connection settings")) {
                                _ = session.beginRecoveryRepair()
                            }.disabled(!session.canRepairRecovery)
                        }
                    }
                    .id(ConnectionGuidePolicy.SettingsSection.restoration)
                }
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
                            if session.isRepairingRecovery { _ = saveTunnelIP() }
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button(L10n.tr("Remove pairing file"), role: .destructive) {
                            do { try pairing.removePairing() }
                            catch { session.lastError = error.localizedDescription }
                        }
                        .disabled(session.isRepairingRecovery)
                    }
                } header: {
                    Text(L10n.tr("Developer pairing"))
                } footer: {
                    Text(supportsOnDevicePairing
                         ? L10n.tr("On iOS 27, use Pair on this iPhone — no computer. Locus advertises a pairable host; confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On older iOS, import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). LiveContainer: enable Fix File Picker on Locus, or use Paste / Share → LiveContainer → Locus.")
                         : L10n.tr("Import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). If the file picker fails (common in LiveContainer), enable Fix File Picker on the app, share the file into LiveContainer → Locus, or copy the plist and use Paste."))
                }
                .disabled(!canEditConnection)
                .id(ConnectionGuidePolicy.SettingsSection.pairing)

                Section {
                    LabeledContent(L10n.tr("Built-in VPN"), value: vpn.statusTitle)
                    Button {
                        if vpn.canDisconnect {
                            vpn.disconnect()
                        } else if saveTunnelIP() {
                            Task { await vpn.connect() }
                        }
                    } label: {
                        Label(vpn.canDisconnect ? L10n.tr("Disconnect built-in VPN") : L10n.tr("Connect the built-in VPN"),
                              systemImage: "power")
                    }
                    .disabled(vpn.isSaving || vpn.status == .disconnecting || diagnostics.state == .checking)
                    if let message = vpn.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    if vpn.isConnected && !vpn.matchesEndpoint {
                        Text(L10n.tr("The VPN is connected, but the configured endpoint has no matching tunnel route."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    TextField(L10n.tr("Device tunnel IP"), text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(vpn.isConnected || vpn.isTransitioning)
                        .onSubmit {
                            saveTunnelIP()
                        }
                    Toggle(L10n.tr("Discover service port automatically"), isOn: $automaticPort)
                    if !automaticPort {
                        TextField(L10n.tr("Service port (1–65535)"), text: $portText).keyboardType(.numberPad)
                    }
                    LabeledContent(L10n.tr("VPN interface hint")) {
                        Text(tunnelInterfaceDetected ? L10n.tr("Interface detected") : L10n.tr("No matching interface detected"))
                            .foregroundStyle(.secondary)
                    }
                    Button(L10n.tr("Save tunnel IP")) {
                        saveTunnelIP()
                    }
                    Button {
                        LocalDevVPN.openOrInstall()
                    } label: {
                        Label(L10n.tr("Use external LocalDevVPN"), systemImage: "arrow.up.forward.app")
                    }
                    .disabled(vpn.isConnected || vpn.isTransitioning || diagnostics.state == .checking)
                } header: {
                    Text(L10n.tr("Tunnel"))
                } footer: {
                    Text(L10n.tr("Disconnect the built-in VPN before changing its IP. Use Check service connection to verify the developer service. If your installation cannot run VPN extensions, use external LocalDevVPN."))
                }
                .disabled(!canEditConnection)
                .id(ConnectionGuidePolicy.SettingsSection.tunnel)

                if session.canStop && !session.isRepairingRecovery {
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
                        Button(L10n.tr("Retry restoring system location")) {
                            if session.isRepairingRecovery {
                                guard saveTunnelIP() else { return }
                                session.endRecoveryRepair()
                            }
                            session.stop(pairing: pairing)
                        }
                            .disabled(session.isRepairingRecovery ? !canEditConnection : !session.canRetryRestore)
                    }
                    Text(L10n.tr("Connection checks do not change your position. Shared diagnostics exclude pairing secrets, PINs and exact coordinates."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .id(ConnectionGuidePolicy.SettingsSection.diagnostics)

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
                    Text(L10n.tr("Favorites, recents and route progress are stored on this device. Search and road routing send requests to Apple map services. location has no accounts or analytics."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L10n.tr("About")) {
                    LabeledContent(L10n.tr("Version"), value: appVersion)
                    LabeledContent(L10n.tr("Engine"), value: L10n.tr("idevice DVT location simulation"))
                    Text(L10n.tr("location is based on the open-source Locus project (MIT). Location injection uses the MIT-licensed idevice FFI."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(L10n.tr("Built-in VPN code from LocalDevVPN by jkcoxson, based on StosVPN by the SideStore Team."),
                         destination: URL(string: "https://github.com/jkcoxson/LocalDevVPN")!)
                        .font(.footnote)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text(L10n.tr("location · A place of your choosing."))
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
            .task(id: initialSection) {
                guard let initialSection else { return }
                // A guide can change state while its sheet is dismissing.
                let section = initialSection == .restoration && !session.restorationRequired
                    ? ConnectionGuidePolicy.SettingsSection.diagnostics : initialSection
                await Task.yield()
                guard !Task.isCancelled else { return }
                scroll.scrollTo(section, anchor: .top)
            }
            .scrollContentBackground(.hidden)
            .background { LocusSheetBackground() }
            .navigationTitle(L10n.tr("Settings"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.tr("Done")) {
                        if session.isRepairingRecovery {
                            guard saveTunnelIP() else { return }
                            session.endRecoveryRepair()
                            dismiss()
                        } else if session.canStop || saveTunnelIP() { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showCoordinates) {
                CoordinateEntrySheet { coordinate in
                    session.selectTarget(coordinate, source: .manual)
                    dismiss()
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        guard canEditConnection else { return }
                        try pairing.importPairing(from: url)
                        if session.isRepairingRecovery { _ = saveTunnelIP() }
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
            .alert("location", isPresented: Binding(
                get: { session.lastError != nil },
                set: { if !$0 { session.lastError = nil } }
            )) {
                Button(L10n.tr("OK"), role: .cancel) { session.lastError = nil }
            } message: {
                Text(session.lastError ?? "")
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await vpn.refresh()
                tunnelInterfaceDetected = LocalDevVPN.isConnected
            }
            .onDisappear {
                if session.isRepairingRecovery { session.endRecoveryRepair() }
            }
            .onChange(of: vpn.status) { _, _ in tunnelInterfaceDetected = LocalDevVPN.isConnected }
            .onChange(of: diagnostics.checkedAt) { _, _ in
                tunnelInterfaceDetected = LocalDevVPN.isConnected
            }
            }
        }
        .locusSheetBackdrop()
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
        guard canEditConnection else { return false }
        guard automaticPort || TunnelConfig.isValidPort(portText) else {
            session.lastError = L10n.tr("Enter a service port from 1 to 65535.")
            return false
        }
        guard let target = TunnelConfig.normalizedTargetIP(tunnelIP) else {
            session.lastError = LocationEngineError.invalidIP.localizedDescription
            return false
        }
        guard target == TunnelConfig.targetIP || (!vpn.isConnected && !vpn.isTransitioning) else {
            session.lastError = L10n.tr("Disconnect the built-in VPN before changing its IP.")
            return false
        }
        if session.isRepairingRecovery,
           !session.updateRecoveryConfiguration(targetIP: target, pairing: pairing) { return false }
        if !automaticPort { _ = TunnelConfig.setPort(portText) }
        UserDefaults.standard.set(automaticPort, forKey: TunnelConfig.automaticPortKey)
        TunnelConfig.setTargetIP(target)
        tunnelIP = target
        tunnelInterfaceDetected = LocalDevVPN.isConnected
        return true
    }
}
