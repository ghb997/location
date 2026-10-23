import SwiftUI

enum PreviewScenario: String {
    case idle
    case activeRoute = "active-route"
    case largeType = "large-type"
    case reducedTransparency = "reduced-transparency"

    static var requested: PreviewScenario {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--scenario"), arguments.indices.contains(index + 1) else { return .idle }
        return PreviewScenario(rawValue: arguments[index + 1]) ?? .idle
    }
}

@main
struct LocationDesignPreviewApp: App {
    private let scenario = PreviewScenario.requested
    @StateObject private var session = SpoofSession(scenario: .requested)
    @StateObject private var pairing = PairingStore()

    var body: some Scene {
        WindowGroup {
            ComponentPreview(scenario: scenario)
                .environmentObject(session)
                .environmentObject(pairing)
                .environment(\.dynamicTypeSize, scenario == .largeType ? .accessibility2 : .large)
                .preferredColorScheme(.light)
                .tint(LocusTheme.accent)
        }
    }
}

private struct ComponentPreview: View {
    let scenario: PreviewScenario
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var showSettings = false
    @State private var showPlaces = false

    var body: some View {
        GeometryReader { geometry in
        ZStack(alignment: .bottom) {
            ZStack(alignment: .top) {
                SyntheticMap(hasRoute: scenario != .idle)
                LocusGlassContainer(spacing: 12) {
                    VStack(spacing: 10) {
                        StatusBarView()
                        MapSearchBar(searchText: $searchText, searchFocused: $searchFocused) { _ in }
                        MapToolbar(
                            drawMode: false, hasPin: true,
                            onMapStyle: {}, onRoutes: {}, onDraw: {},
                            onFavorite: {}, onLocate: {}
                        )
                    }
                }
                .frame(maxWidth: 640)
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
                .safeAreaPadding(.top, 8)
            }
            MapBottomChrome(availableHeight: geometry.size.height,
                showSettings: $showSettings, showPlaces: $showPlaces)
                .frame(maxWidth: 540)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        }
        .background(LocusTheme.canvas.ignoresSafeArea())
        .foregroundStyle(LocusTheme.ink)
        .task { recordObservedEnvironment() }
        .onChange(of: reduceTransparency) { _, _ in recordObservedEnvironment() }
        .onChange(of: reduceMotion) { _, _ in recordObservedEnvironment() }
    }

    private func recordObservedEnvironment() {
        let values: [String: Any] = [
            "scenario": scenario.rawValue,
            "reduceTransparency": reduceTransparency,
            "reduceMotion": reduceMotion,
            "colorScheme": colorScheme == .light ? "light" : "dark",
            "dynamicTypeSize": String(describing: dynamicTypeSize),
            "isAccessibilitySize": dynamicTypeSize.isAccessibilitySize,
            "language": Bundle.main.preferredLocalizations.first ?? "unknown"
        ]
        do {
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            let data = try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("preview-environment-\(scenario.rawValue).json"), options: .atomic)
        } catch {
            print("Unable to write preview environment evidence: \(error)")
        }
    }
}

/// Deterministic, fictional map artwork exposes material/refraction behavior
/// without requiring MapKit network tiles or representing a real location fix.
private struct SyntheticMap: View {
    let hasRoute: Bool

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.93, green: 0.95, blue: 0.92)))
                for row in 0..<8 {
                    for column in 0..<5 {
                        let rect = CGRect(x: CGFloat(column) * size.width / 4.3 - 24,
                                          y: CGFloat(row) * size.height / 7.3 - 8,
                                          width: size.width / 5.5, height: size.height / 10)
                        let color = (row + column) % 4 == 0
                            ? Color(red: 0.77, green: 0.88, blue: 0.72)
                            : Color(red: 0.87, green: 0.90, blue: 0.85)
                        context.fill(Path(roundedRect: rect, cornerRadius: 12), with: .color(color))
                    }
                }
                var river = Path()
                river.move(to: CGPoint(x: size.width * 0.76, y: -30))
                river.addCurve(to: CGPoint(x: size.width * 0.78, y: size.height + 30),
                               control1: CGPoint(x: size.width * 0.35, y: size.height * 0.32),
                               control2: CGPoint(x: size.width * 1.02, y: size.height * 0.63))
                context.stroke(river, with: .color(Color(red: 0.66, green: 0.83, blue: 0.91)), style: StrokeStyle(lineWidth: size.width * 0.16, lineCap: .round))
                for index in 0..<7 {
                    var road = Path()
                    let y = CGFloat(index) * size.height / 6.2
                    road.move(to: CGPoint(x: -20, y: y))
                    road.addLine(to: CGPoint(x: size.width + 20, y: y + size.height * 0.08))
                    context.stroke(road, with: .color(.white), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                }
                for index in 0..<4 {
                    var road = Path()
                    let x = CGFloat(index) * size.width / 3.4 + 18
                    road.move(to: CGPoint(x: x, y: -20))
                    road.addLine(to: CGPoint(x: x - size.width * 0.16, y: size.height + 20))
                    context.stroke(road, with: .color(.white), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                }
                if hasRoute {
                    var route = Path()
                    route.move(to: CGPoint(x: size.width * 0.20, y: size.height * 0.65))
                    route.addLine(to: CGPoint(x: size.width * 0.27, y: size.height * 0.46))
                    route.addLine(to: CGPoint(x: size.width * 0.53, y: size.height * 0.49))
                    context.stroke(route, with: .color(.white), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    context.stroke(route, with: .color(LocusTheme.accent), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                context.draw(Text("示例公园").font(.caption.weight(.medium)).foregroundColor(Color(red: 0.24, green: 0.43, blue: 0.29)),
                             at: CGPoint(x: size.width * 0.22, y: size.height * 0.37))
                context.draw(Text("示例大道").font(.caption).foregroundColor(Color(red: 0.42, green: 0.49, blue: 0.48)),
                             at: CGPoint(x: size.width * 0.78, y: size.height * 0.44))
            }
            .ignoresSafeArea()

            MapDropPin(selected: false, isDragging: false, onSelect: {}, onRemove: {},
                       onDragBegan: {}, onDragMoved: { _ in }, onDragEnded: {})
                .position(x: geometry.size.width * 0.53, y: geometry.size.height * 0.49)

            Text("UI 组件预览 · 合成地图")
                .font(.caption2.weight(.medium))
                .foregroundStyle(LocusTheme.ink.opacity(0.70))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.white.opacity(0.85), in: Capsule())
                .position(x: geometry.size.width * 0.5, y: geometry.size.height * 0.56)
        }
    }
}
