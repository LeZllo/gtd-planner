import SwiftUI

/// Glass belongs to navigation and controls. Content panes retain opaque,
/// adaptive surfaces so dense task text does not sit on translucent layers.
enum PlannerChromeRules {
    static func usesOpaqueSurface(reduceTransparency: Bool, increasedContrast: Bool) -> Bool {
        reduceTransparency || increasedContrast
    }
    static func allowsInteractiveGlass(reduceMotion: Bool) -> Bool { !reduceMotion }
}

private struct PlannerControlSurface<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    var tint: Color?
    var interactive: Bool
    var selected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if PlannerChromeRules.usesOpaqueSurface(reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased) {
            content
                .background(ModernPalette.panel, in: shape)
                .overlay {
                    shape.stroke(selected ? ModernPalette.selection : ModernPalette.line,
                                 lineWidth: selected ? 2 : (contrast == .increased ? 1.5 : 1))
                }
        } else if let tint {
            content.glassEffect(
                .regular.tint(tint).interactive(interactive && PlannerChromeRules.allowsInteractiveGlass(reduceMotion: reduceMotion)),
                in: shape
            )
        } else {
            content.glassEffect(
                .regular.interactive(interactive && PlannerChromeRules.allowsInteractiveGlass(reduceMotion: reduceMotion)),
                in: shape
            )
        }
    }
}

extension View {
    func plannerControlSurface<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false, selected: Bool = false) -> some View {
        modifier(PlannerControlSurface(shape: shape, tint: tint, interactive: interactive, selected: selected))
    }
}
