import MapKit
import SwiftUI

/// Map pin with Liquid Glass “Remove Pin” menu and long-press drag.
struct MapDropPin: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @GestureState private var gestureActive = false
    @State private var dragStarted = false
    var selected: Bool
    var isDragging: Bool
    var onSelect: () -> Void
    var onRemove: () -> Void
    var onDragBegan: () -> Void
    var onDragMoved: (CGPoint) -> Void
    var onDragEnded: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if selected && !isDragging {
                Button(action: onRemove) {
                    Label(L10n.tr("Remove Pin"), systemImage: "trash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(LocusTheme.danger)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                }
                .locusActionStyle(tint: LocusTheme.danger)
                .contentShape(Capsule())
                .transition(reduceMotion ? .opacity : .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }

            Image(systemName: "mappin.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, LocusTheme.accentSecondary)
                .font(.system(size: isDragging ? 44 : 36))
                .frame(minWidth: 44, minHeight: 44)
                .shadow(color: LocusTheme.ink.opacity(0.18), radius: isDragging ? 8 : 4, y: 2)
                .scaleEffect(isDragging && !reduceMotion ? 1.12 : 1)
        }
        // Keep the pin tip on the coordinate while the menu sits above.
        .padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .gesture(dragGesture)
        .onChange(of: gestureActive) { _, active in
            // GestureState resets even when cancellation skips onEnded.
            if !active { finishDragging() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { finishDragging() }
        }
        .onDisappear { finishDragging() }
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78), value: selected)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isDragging)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(selected ? L10n.tr("Selected pin") : L10n.tr("Map pin"))
        .accessibilityHint(L10n.tr("Tap to show remove. Touch and hold to drag."))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect() }
        .accessibilityAction(named: L10n.tr("Remove Pin")) { onRemove() }
    }

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                guard scenePhase == .active else { return }
                switch value {
                case .first(true):
                    break
                case .second(true, let drag):
                    if let drag {
                        if !dragStarted {
                            dragStarted = true
                            onDragBegan()
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        }
                        onDragMoved(drag.location)
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                finishDragging()
            }
    }

    private func finishDragging() {
        guard dragStarted else { return }
        dragStarted = false
        onDragEnded()
    }
}
