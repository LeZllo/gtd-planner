import SwiftUI
import AppKit

/// Shared interaction colors across every task projection.
/// Keep identity colors (projects/tags), priority warnings and timer phases
/// separate: a blue checkmark means the same thing in every workspace.
enum PlannerTheme {
    static let accent = Color(nsColor: NSColor.systemBlue)
    static let completion = accent
    static let selection = accent
}
