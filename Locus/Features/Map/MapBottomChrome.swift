import SwiftUI

/// Large type keeps controls reachable without covering the whole map. The
/// ordinary layout has no expanding container that could swallow map touches.
struct MapBottomChrome: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let availableHeight: CGFloat
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            ScrollView {
                BottomControlsView(showSettings: $showSettings, showPlaces: $showPlaces)
                    .padding(.vertical, 4)
            }
            .scrollIndicators(.visible)
            .frame(height: max(180, availableHeight * 0.52))
        } else {
            BottomControlsView(showSettings: $showSettings, showPlaces: $showPlaces)
        }
    }
}
