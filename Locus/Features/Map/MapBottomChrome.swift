import SwiftUI

/// Measure the visible stack so short content stays beside the bottom edge,
/// while long content can scroll within a bounded part of the map on any size.
struct MapBottomChrome: View {
    @EnvironmentObject private var session: SpoofSession
    @State private var contentHeight: CGFloat = 0
    @State private var fullActionsHeight: CGFloat = 0
    @State private var pinnedActionsHeight: CGFloat = 0
    let availableHeight: CGFloat
    @Binding var showSettings: Bool
    @Binding var showPlaces: Bool

    var body: some View {
        VStack(spacing: pinnedActionsHeight > 0 ? 10 : 0) {
            scrollingInformation
            pinnedActions
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(pinnedActionsHeight - height) > 0.5 { pinnedActionsHeight = height }
                }
        }
        .background(alignment: .bottom) {
            // This pure view only measures its ideal size at the current width.
            // It cannot receive input or appear as a duplicate VoiceOver action.
            MapActionControls()
                .fixedSize(horizontal: false, vertical: true)
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(fullActionsHeight - height) > 0.5 { fullActionsHeight = height }
                }
        }
    }

    private var scrollingInformation: some View {
        ScrollView {
            VStack(spacing: 10) {
                BottomControlsView(showSettings: $showSettings, showPlaces: $showPlaces)
                if usesCompactActions { MapActionControls(includesStop: false) }
            }
            .padding(.vertical, 4)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                // Ignore subpixel oscillation from material and text layout.
                if abs(contentHeight - height) > 0.5 { contentHeight = height }
            }
        }
        .scrollIndicators(.visible)
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(contentHeight > 0 && contentHeight <= informationHeightLimit)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .frame(height: min(contentHeight > 0 ? contentHeight : informationHeightLimit, informationHeightLimit))
    }

    @ViewBuilder
    private var pinnedActions: some View {
        if usesCompactActions {
            if session.canStop {
                MapStopControl()
            } else {
                Color.clear.frame(height: 0).accessibilityHidden(true)
            }
        } else {
            MapActionControls()
        }
    }

    private var usesCompactActions: Bool {
        fullActionsHeight > max(0, maximumHeight - 74)
    }

    private var informationHeightLimit: CGFloat {
        max(0, maximumHeight - pinnedActionsHeight - (pinnedActionsHeight > 0 ? 10 : 0))
    }

    private var maximumHeight: CGFloat {
        max(0, availableHeight * 0.5 - 16)
    }
}
