import MapKit
import SwiftUI

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @AppStorage(CoordinateSettings.mapKey) private var mapCoordinateSystem = "wgs84"

    @StateObject private var search = PlaceSearchCompleter()
    @State private var routeGeometry: RouteDisplayGeometry?
    @State private var geometryRevision = ""
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeStart: CLLocationCoordinate2D?
    @State private var routeEnd: CLLocationCoordinate2D?
    @State private var importedTracks: [RouteTrack] = []
    @State private var selectedSegmentIndex = 0
    @State private var importSystem: CoordinateSystem = .wgs84
    @State private var draftRevision = 0
    @State private var routeSelection = MapRouteSelection()
    @State private var routeRequest: Task<Void, Never>?
    @State private var searchRequest: Task<Void, Never>?
    @State private var importRequest: Task<Void, Never>?
    @State private var importLoader = LatestOperation<[RouteTrack]>()
    @State private var isRouting = false
    @State private var showRouteSheet = false
    @State private var showGPXImporter = false
    @State private var importAfterDismiss = false
    @State private var draftSource: CoordinateSource = .manual
    @State private var drawnPath: [CLLocationCoordinate2D] = []
    @State private var drawMode = false
    @State private var pinSelected = false
    @State private var isDraggingPin = false
    @State private var suppressNextMapTap = false
    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?
    @State private var namedPinCoordinate: CLLocationCoordinate2D?

    private var mapStyle: MapStyle {
        switch session.mapStyleIndex {
        case 1: return .hybrid(elevation: .realistic)
        case 2: return .imagery(elevation: .realistic)
        default: return .standard(elevation: .realistic)
        }
    }

    private var displayedRoute: RouteTrack? {
        routeSelection.displayedTrack(draft: session.draftTrack, current: session.currentRoute)
    }

    private var displayedRouteSource: MapRouteSelection.Source? {
        routeSelection.resolvedSource(draft: session.draftTrack, current: session.currentRoute)
    }

    private var routeGeometryKey: String {
        "\(displayedRoute?.id.uuidString ?? "none")-\(session.routeDraftRevision)-\(mapCoordinateSystem)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keep Map inside the safe layout bounds so MapProxy.convert matches
            // finger position. Ignoring the safe area makes the tiles full-bleed but
            // shifts convert() upward by ~status-bar height.
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    if let pin = session.pin {
                        Annotation("", coordinate: displayed(pin), anchor: .bottom) {
                            MapDropPin(
                                selected: pinSelected,
                                isDragging: isDraggingPin,
                                onSelect: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pinSelected.toggle()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onRemove: {
                                    beginTargetChange()
                                    suppressNextMapTap = true
                                    withAnimation {
                                        session.selectTarget(nil)
                                        pinSelected = false
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        suppressNextMapTap = false
                                    }
                                },
                                onDragBegan: {
                                    searchFocused = false
                                    suppressNextMapTap = true
                                    pinSelected = false
                                    isDraggingPin = true
                                },
                                onDragMoved: { globalPoint in
                                    if let coord = proxy.convert(globalPoint, from: .global) {
                                        setPinFromMap(coord)
                                    }
                                },
                                onDragEnded: {
                                    isDraggingPin = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        suppressNextMapTap = false
                                    }
                                }
                            )
                        }
                    }
                    if let sim = session.simulated {
                        Annotation(L10n.tr("Spoof"), coordinate: displayed(sim)) {
                            ZStack {
                                Circle().fill(LocusTheme.accent.opacity(0.25)).frame(width: 44, height: 44)
                                Circle().fill(LocusTheme.accent).frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(.white, lineWidth: 2))
                            }
                        }
                    }
                    if geometryRevision == routeGeometryKey, let routeGeometry {
                        ForEach(routeGeometry.segments) { segment in
                            if segment.coordinates.count > 1 {
                                MapPolyline(coordinates: segment.coordinates)
                                    .stroke(LocusTheme.accent, lineWidth: 5)
                            }
                        }
                    }
                    if drawnPath.count > 1 {
                        MapPolyline(coordinates: drawnPath.map(displayed))
                            .stroke(LocusTheme.accentSecondary, style: StrokeStyle(lineWidth: 4, dash: [6, 4]))
                    }
                }
                .mapStyle(mapStyle)
                .mapControlVisibility(.hidden)
                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    placePin(at: point, proxy: proxy)
                }
            }
            .background(LocusTheme.canvas.ignoresSafeArea())

            topChrome
        }
        .task(id: routeGeometryKey) {
            let key = routeGeometryKey
            guard let track = displayedRoute else { routeGeometry = nil; return }
            let system = CoordinateSystem(rawValue: mapCoordinateSystem) ?? .wgs84
            let preparation = Task.detached(priority: .userInitiated) {
                try RouteDisplayGeometry(track: track) {
                    try CoordinateTransform.convert($0, from: .wgs84, to: system)
                }
            }
            do {
                let prepared = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: { preparation.cancel() }
                guard !Task.isCancelled, key == routeGeometryKey else { return }
                routeGeometry = prepared
                geometryRevision = key
            } catch is CancellationError {} catch {
                guard !Task.isCancelled, key == routeGeometryKey else { return }
                session.lastError = error.localizedDescription
            }
        }
        .onAppear {
            session.startLocationUpdates()
            importPendingGPX()
        }
        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil { pinSelected = false }
        }
        .onChange(of: routeStart.map(RoutePoint.init)) { _, _ in cancelDraftPreparation() }
        .onChange(of: routeEnd.map(RoutePoint.init)) { _, _ in cancelDraftPreparation() }
        .onChange(of: session.pendingGPXURL) { _, _ in
            importPendingGPX()
        }
        .fileImporter(isPresented: $showGPXImporter, allowedContentTypes: [.xml, .data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importGPX(url, system: importSystem) }
            case .failure(let error):
                session.lastError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showRouteSheet, onDismiss: {
            if importAfterDismiss { importAfterDismiss = false; showGPXImporter = true }
        }) {
            RoutePlannerSheet(
                start: $routeStart,
                end: $routeEnd,
                isRouting: $isRouting,
                selectedSegmentIndex: $selectedSegmentIndex,
                importSystem: $importSystem,
                tracks: importedTracks,
                onSelectTrack: selectTrack,
                onBuild: buildRoadRoute,
                onPlay: playRoute,
                onPreviewDraft: { showRouteOnMap(.draft) },
                onShowCurrentRoute: { showRouteOnMap(.current) },
                onImportGPX: { importAfterDismiss = true; showRouteSheet = false },
                onExportGPX: exportGPX,
                onUseDrawn: useDrawnPath
            )
            .presentationDetents([.medium, .large])
            .locusSheetBackdrop()
        }
    }

    private func placePin(at point: CGPoint, proxy: MapProxy) {
        guard let coord = proxy.convert(point, from: .local) else { return }
        beginTargetChange()
        let normalized: CLLocationCoordinate2D
        do { normalized = try CoordinateSettings.mapInput(coord) }
        catch { session.lastError = error.localizedDescription; return }
        if drawMode {
            drawnPath.append(normalized)
        } else {
            session.selectTarget(normalized, source: .mapSelection)
            pinPlaceName = nil
            pinSelected = false
        }
    }

    private var topChrome: some View {
        LocusGlassContainer(spacing: 12) {
        VStack(spacing: 10) {
            StatusBarView()

            MapSearchBar(searchText: $searchText, searchFocused: $searchFocused) { search.query = $0 }

            if !searchText.isEmpty && !search.results.isEmpty {
                MapSearchResults(items: search.results, onSelect: select)
            }

            MapToolbar(
                drawMode: drawMode, hasPin: session.pin != nil,
                onMapStyle: { session.mapStyleIndex = (session.mapStyleIndex + 1) % 3 },
                onRoutes: { showRouteSheet = true },
                onDraw: toggleDrawing, onFavorite: saveFavorite,
                onLocate: { searchFocused = false; goToCurrentLocation() }
            )

            if let track = displayedRoute, let source = displayedRouteSource {
                RouteMapPreviewBadge(
                    name: track.name,
                    source: source,
                    canSwitch: session.draftTrack != nil && session.currentRoute != nil,
                    onSwitch: { showRouteOnMap(source == .draft ? .current : .draft) }
                )
            }
        }
        }
        .frame(maxWidth: 640)
        .padding(.horizontal, 16)
        .padding(.bottom, 2)
        .safeAreaPadding(.top, 8)
    }

    /// Centers on the spoofed fix while spoofing, otherwise the real GPS —
    /// never the leftover teleport pin (`.automatic` would frame that marker).
    private func goToCurrentLocation() {
        beginTargetChange()
        session.requestLatestLocation()
        let meters: CLLocationDistance = 900
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let sim = session.simulated {
                position = .region(MKCoordinateRegion(
                    center: displayed(sim),
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else if let real = session.realCoordinate {
                position = .region(MKCoordinateRegion(
                    center: displayed(real),
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else {
                position = .userLocation(
                    followsHeading: false,
                    fallback: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    ))
                )
            }
        }
    }

    private func toggleDrawing() {
        drawMode.toggle()
        if !drawMode { drawnPath.removeAll() }
    }

    private func saveFavorite() {
        guard let pin = session.pin else { return }
        let named = namedPinCoordinate.map { $0.latitude == pin.latitude && $0.longitude == pin.longitude } == true
        session.addFavorite(name: session.suggestedFavoriteName(for: pin, fallback: named ? pinPlaceName : nil), coordinate: pin)
    }

    private func select(completion: MKLocalSearchCompletion) {
        let revision = beginTargetChange()
        let serviceSystem = CoordinateSystem(rawValue: UserDefaults.standard.string(forKey: CoordinateSettings.serviceKey) ?? "wgs84") ?? .wgs84
        searchRequest = Task {
            let operation = PlaceSearchRequest(completion: completion)
            do {
                let response = try await operation.response()
                guard !Task.isCancelled, session.acceptsTargetChange(revision),
                      let item = response.mapItems.first else { return }
                let coordinate = try CoordinateTransform.normalize(item.placemark.coordinate, from: serviceSystem)
                let title = item.name ?? completion.title
                session.selectTarget(coordinate, source: .appleSearch, replacing: revision)
                pinPlaceName = title
                namedPinCoordinate = coordinate
                position = .region(MKCoordinateRegion(center: displayed(coordinate), latitudinalMeters: 1200, longitudinalMeters: 1200))
                searchText = ""
                search.query = ""
                searchFocused = false
                session.pushNamedRecent(name: title, coordinate: coordinate)
            } catch {
                guard !Task.isCancelled, session.acceptsTargetChange(revision) else { return }
                session.lastError = L10n.tr("Place search failed. Check the network and try again.")
            }
        }
    }

    private func buildRoadRoute() {
        guard let start = routeStart ?? session.simulated ?? session.pin,
              let end = routeEnd else {
            session.lastError = L10n.tr("Set a route start and end.")
            return
        }
        cancelDraftPreparation()
        let revision = draftRevision
        let targetRevision = beginTargetChange()
        isRouting = true
        routeRequest = Task {
            do {
                let coordinates = try await RouteBuilder.roadRoute(from: start, to: end, mode: session.travelMode)
                guard !Task.isCancelled, revision == draftRevision else { return }
                installTracks([RouteTrack(name: L10n.tr("Road route"), kind: .route,
                    segments: [RouteSegment(points: coordinates.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude) })])], source: .appleRoute, targetRevision: targetRevision)
                isRouting = false
            } catch {
                guard !Task.isCancelled, revision == draftRevision else { return }
                isRouting = false
                session.lastError = error.localizedDescription
            }
        }
    }

    private func playRoute() {
        guard let track = session.draftTrack, !track.segments.isEmpty else {
            session.lastError = L10n.tr("Build or draw a route first.")
            return
        }
        let index = min(max(0, selectedSegmentIndex), track.segments.count - 1)
        let playback = RouteTrack(name: track.name, kind: track.kind,
                                  segments: Array(track.segments.dropFirst(index)))
        showRouteSheet = false
        session.followRoute(playback, pairing: pairing)
        if session.currentRoute?.id == playback.id {
            beginTargetChange()
            routeSelection.show(.current)
        }
    }

    private func useDrawnPath() {
        guard drawnPath.count >= 2 else {
            session.lastError = L10n.tr("Draw at least two points first.")
            return
        }
        cancelDraftPreparation()
        let targetRevision = beginTargetChange()
        installTracks([RouteTrack(name: L10n.tr("Drawn route"), kind: .track,
            segments: [RouteSegment(points: drawnPath.map { RoutePoint(latitude: $0.latitude, longitude: $0.longitude) })])], source: .mapSelection, targetRevision: targetRevision)
        drawnPath.removeAll()
        drawMode = false
    }

    private func installTracks(_ tracks: [RouteTrack], source: CoordinateSource, targetRevision: UInt64) {
        importedTracks = tracks
        draftSource = source
        session.draftTrack = RouteDocument(tracks: tracks).preferredTrack
        selectedSegmentIndex = 0
        // A search or map selection made after import/build began owns the pin.
        routeSelection.show(.draft)
        guard session.acceptsTargetChange(targetRevision) else { return }
        setDraftTarget()
    }

    private func selectTrack(_ id: UUID) {
        guard let track = importedTracks.first(where: { $0.id == id }) else { return }
        cancelDraftPreparation()
        session.draftTrack = track
        selectedSegmentIndex = 0
        routeSelection.previewDraft()
        setDraftTarget()
    }

    private func setDraftTarget() {
        searchRequest?.cancel()
        searchRequest = nil
        pinPlaceName = nil
        namedPinCoordinate = nil
        guard let track = session.draftTrack else { return }
        if let first = (track.segments.first(where: { $0.canPlay })
            ?? track.segments.first(where: { !$0.points.isEmpty }))?.points.first?.coordinate {
            session.selectTarget(first, source: draftSource)
            position = .region(MKCoordinateRegion(center: displayed(first), latitudinalMeters: 2000, longitudinalMeters: 2000))
        }
    }

    private func importGPX(_ url: URL, system: CoordinateSystem) {
        cancelDraftPreparation()
        let revision = draftRevision
        let targetRevision = beginTargetChange()
        isRouting = true
        importRequest = Task {
            do {
                let document = try await importLoader.perform {
                    let parsed = try GPXCodec.parseDocument(url)
                    var tracks = parsed.tracks
                    if system == .gcj02 {
                        for trackIndex in tracks.indices {
                            for segmentIndex in tracks[trackIndex].segments.indices {
                                let original = tracks[trackIndex].segments[segmentIndex].points
                                tracks[trackIndex].segments[segmentIndex].points = try original.map {
                                    try Task.checkCancellation()
                                    let coordinate = try CoordinateTransform.normalize($0.coordinate, from: system)
                                    return RoutePoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
                                }
                            }
                        }
                    }
                    return tracks
                }
                guard !Task.isCancelled, revision == draftRevision else { return }
                installTracks(document, source: .gpx, targetRevision: targetRevision)
                isRouting = false
                showRouteSheet = true
            } catch {
                guard !Task.isCancelled, revision == draftRevision else { return }
                isRouting = false
                session.lastError = error.localizedDescription
            }
        }
    }

    private func importPendingGPX() {
        guard let url = session.pendingGPXURL else { return }
        session.pendingGPXURL = nil
        importGPX(url, system: .wgs84)
    }

    private func displayed(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        _ = mapCoordinateSystem
        return (try? CoordinateSettings.mapOutput(coordinate)) ?? coordinate
    }

    private func setPinFromMap(_ coordinate: CLLocationCoordinate2D) {
        beginTargetChange()
        let normalized: CLLocationCoordinate2D
        do { normalized = try CoordinateSettings.mapInput(coordinate) }
        catch { session.lastError = error.localizedDescription; return }
        session.selectTarget(normalized, source: .mapSelection)
        pinPlaceName = nil
    }

    @discardableResult
    private func beginTargetChange() -> UInt64 {
        searchRequest?.cancel()
        searchRequest = nil
        return session.beginTargetChange()
    }

    private func cancelDraftPreparation() {
        draftRevision += 1
        routeRequest?.cancel()
        routeRequest = nil
        importRequest?.cancel()
        importRequest = nil
        importLoader.cancel()
        isRouting = false
    }

    private func showRouteOnMap(_ source: MapRouteSelection.Source) {
        beginTargetChange()
        routeSelection.show(source)
        searchFocused = false
        guard let first = displayedRoute?.segments.first(where: { !$0.points.isEmpty })?.points.first else { return }
        position = .region(MKCoordinateRegion(center: displayed(first.coordinate), latitudinalMeters: 2000, longitudinalMeters: 2000))
    }

    private func exportGPX() {
        guard let track = session.draftTrack else {
            session.lastError = L10n.tr("Nothing to export.")
            return
        }
        let gpx = GPXCodec.export(track)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("location-Route.gpx")
        do {
            try Data(gpx.utf8).write(to: url, options: .atomic)
            let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let root = scene.keyWindow?.rootViewController {
                var presenter = root
                while let presented = presenter.presentedViewController { presenter = presented }
                if let popover = av.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 1, height: 1)
                    popover.permittedArrowDirections = []
                }
                presenter.present(av, animated: true)
            }
        } catch {
            session.lastError = error.localizedDescription
        }
    }
}

private struct RouteMapPreviewBadge: View {
    let name: String
    let source: MapRouteSelection.Source
    let canSwitch: Bool
    let onSwitch: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(source == .draft ? L10n.tr("Route preview") : L10n.tr("Current route"))
                    .font(.caption).foregroundStyle(.secondary)
                Text(name).font(.subheadline).lineLimit(2)
            }
            Spacer(minLength: 0)
            if canSwitch {
                Button(action: onSwitch) {
                    Image(systemName: "arrow.triangle.swap")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel(source == .draft ? L10n.tr("Show current route") : L10n.tr("Preview selected route"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .locusGlass(in: RoundedRectangle(cornerRadius: 20))
    }
}

private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}
