import SwiftUI

struct JoystickPad: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var diameter: CGFloat = 132
    var onChange: (CGVector) -> Void

    @GestureState private var isDragging = false
    @State private var dragOffset: CGSize = .zero
    private var scale: CGFloat { diameter / 132 }
    private var radius: CGFloat { 52 * scale }

    var body: some View {
        ZStack {
            Circle()
                .stroke(LocusTheme.accent.opacity(0.2), lineWidth: 1)
                .frame(width: radius * 2, height: radius * 2)
                .accessibilityHidden(true)

            Image(systemName: "plus")
                .font(.system(size: 46 * scale, weight: .ultraLight))
                .foregroundStyle(LocusTheme.accent.opacity(0.28))
                .accessibilityHidden(true)

            Circle()
                .fill(LinearGradient(colors: [.white, LocusTheme.canvas], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44 * scale, height: 44 * scale)
                .overlay(Circle().stroke(LocusTheme.accent.opacity(0.3), lineWidth: 1))
                .overlay {
                    Circle().fill(LocusTheme.accent).frame(width: 10 * scale, height: 10 * scale)
                }
                .shadow(color: LocusTheme.accent.opacity(0.16), radius: 8 * scale, y: 3 * scale)
                .offset(dragOffset)
        }
        .frame(width: diameter, height: diameter)
        // Keep every control in the glass foreground. A glass-only sibling can
        // be composited above the ring and thumb by GlassEffectContainer.
        .locusGlass(.regular, in: Circle())
        // The complete pad owns its drag, including inside the information scroll view.
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .updating($isDragging) { _, dragging, _ in dragging = true }
                .onChanged { value in
                    guard scenePhase == .active else { return }
                    let limited = clamp(value.translation, radius: radius)
                    dragOffset = limited
                    onChange(CGVector(dx: limited.width / radius, dy: limited.height / radius))
                }
                .onEnded { _ in resetJoystick() }
        )
        .accessibilityLabel(L10n.tr("Movement joystick"))
        .accessibilityHint(L10n.tr("Drag to move. Release to hold position."))
        .onChange(of: isDragging) { _, dragging in
            // GestureState also resets when the system cancels without onEnded.
            if !dragging { resetJoystick() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { resetJoystick() }
        }
        .onChange(of: diameter) { _, _ in resetJoystick() }
        .onDisappear { resetJoystick() }
    }

    private func resetJoystick() {
        onChange(.zero)
        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7)) {
            dragOffset = .zero
        }
    }

    private func clamp(_ translation: CGSize, radius: CGFloat) -> CGSize {
        let length = sqrt(translation.width * translation.width + translation.height * translation.height)
        guard length > radius else { return translation }
        let scale = radius / length
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }
}
