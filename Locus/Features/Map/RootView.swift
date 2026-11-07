import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var host: PairOnDeviceService
    @ObservedObject private var diagnostics = TunnelDiagnostics.shared
    @State private var sheet: MapSheet?
    @State private var queuedSettings: ConnectionGuidePolicy.SettingsSection?
    @State private var bottomHeight: CGFloat = 0

    private enum MapSheet: Identifiable {
        case settings(ConnectionGuidePolicy.SettingsSection?), places, guide
        var id: String {
            switch self {
            case .settings: return "settings"
            case .places: return "places"
            case .guide: return "guide"
            }
        }
    }

    private var guide: ConnectionGuidePolicy.Guide {
        ConnectionGuideContext.guide(session: session, pairing: pairing, diagnostics: diagnostics,
                                     pairingWorkerRunning: host.isWorkerRunning)
    }

    private var showSettings: Binding<Bool> {
        Binding(get: { if case .settings? = sheet { return true }; return false },
                set: { if $0 { sheet = .settings(nil) } })
    }
    private var showPlaces: Binding<Bool> {
        Binding(get: { if case .places? = sheet { return true }; return false },
                set: { if $0 { sheet = .places } })
    }

    var body: some View {
        // Bottom chrome is a sibling overlay aligned to the bottom — no full-screen
        // Spacer layer that can steal / pass map taps through the tray.
        GeometryReader { geometry in
        ZStack(alignment: .bottom) {
            MapHomeView(bottomOverlayHeight: bottomHeight, onHelp: { sheet = .guide })

            MapBottomChrome(availableHeight: geometry.size.height,
                showSettings: showSettings, showPlaces: showPlaces)
            .frame(maxWidth: 540)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomHeight = $0 }
        }
        }
        .sheet(item: $sheet, onDismiss: {
            if let section = queuedSettings {
                queuedSettings = nil
                sheet = .settings(section)
            }
        }) { destination in
            switch destination {
            case let .settings(section): SettingsView(initialSection: section)
            case .places: PlacesView()
            case .guide:
                ConnectionGuideSheet(guide: guide, onOpenSettings: { section in
                    queuedSettings = section
                    sheet = nil
                }, onCheckConnection: {
                    Task {
                        guard guide.canCheckConnection else { return }
                        await diagnostics.check()
                    }
                }, onRestoreLocation: {
                    guard guide.canRestoreLocation else { return }
                    session.stop(pairing: pairing)
                })
            }
        }
        .alert("location", isPresented: Binding(
            get: { session.lastError != nil && sheet == nil && queuedSettings == nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button(L10n.tr("OK"), role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}
