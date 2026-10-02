import AppKit
import SwiftUI
import Testing
@testable import GTDPlanner

@MainActor
struct ThemeConsistencyTests {
    @Test("Interactive theme keeps one dynamic system-blue source")
    func accentIsShared() {
        #expect(PlannerTheme.accent == Color(nsColor: NSColor.systemBlue))
        #expect(ModernPalette.accent == PlannerTheme.accent)
        #expect(ModernPalette.blue == PlannerTheme.accent)
    }

    @Test("Completion and selection aliases cannot drift to unrelated colors")
    func taskRolesUseTheAccent() {
        #expect(PlannerTheme.completion == PlannerTheme.accent)
        #expect(PlannerTheme.selection == PlannerTheme.accent)
        #expect(ModernPalette.completion == PlannerTheme.completion)
        #expect(ModernPalette.selection == PlannerTheme.selection)
    }

    @Test("Legacy and modern selection surfaces use the same theme")
    func selectionSurfacesStayConsistent() {
        let selectionSurface = PlannerTheme.selection.opacity(0.09)
        #expect(ModernPalette.sidebarSelection == selectionSurface)
        #expect(AppColors.sidebarSelected == selectionSurface)
        #expect(AppColors.sidebarSelection == selectionSurface)
        #expect(AppColors.sidebarSelectedInk == PlannerTheme.selection)
        #expect(AppColors.sidebarAccent == PlannerTheme.accent)
        #expect(AppColors.selection == PlannerTheme.selection)
        #expect(AppColors.mailSelected == selectionSurface)
    }

    @Test("Warning and non-completion green remain separate semantic colors")
    func semanticColorsAreNotFlattened() {
        #expect(ModernPalette.red == Color(nsColor: NSColor.systemRed))
        #expect(ModernPalette.green == Color(nsColor: NSColor.systemGreen))
        #expect(ModernPalette.red != PlannerTheme.completion)
        #expect(ModernPalette.green != PlannerTheme.completion)
    }

    @Test("Primary surfaces and labels share native adaptive appearance semantics")
    func adaptiveSurfaces() {
        #expect(ModernPalette.canvas == Color(nsColor: NSColor.windowBackgroundColor))
        #expect(ModernPalette.panel == Color(nsColor: NSColor.controlBackgroundColor))
        #expect(ModernPalette.rail == Color(nsColor: NSColor.underPageBackgroundColor))
        #expect(ModernPalette.railInk == Color(nsColor: NSColor.secondaryLabelColor))
        #expect(AppColors.selectionInk == Color(nsColor: NSColor.labelColor))
    }

}
