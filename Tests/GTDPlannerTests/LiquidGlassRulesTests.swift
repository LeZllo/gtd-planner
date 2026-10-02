import Testing
@testable import GTDPlanner

struct LiquidGlassRulesTests {
    @Test("Navigation glass becomes opaque when transparency is reduced")
    func reduceTransparency() {
        #expect(PlannerChromeRules.usesOpaqueSurface(reduceTransparency: true, increasedContrast: false))
        #expect(!PlannerChromeRules.usesOpaqueSurface(reduceTransparency: false, increasedContrast: false))
    }

    @Test("Increased contrast chooses a solid navigation surface")
    func increasedContrast() {
        #expect(PlannerChromeRules.usesOpaqueSurface(reduceTransparency: false, increasedContrast: true))
        #expect(PlannerChromeRules.usesOpaqueSurface(reduceTransparency: true, increasedContrast: true))
    }

    @Test("Reduced motion disables interactive glass movement")
    func reducedMotion() {
        #expect(!PlannerChromeRules.allowsInteractiveGlass(reduceMotion: true))
        #expect(PlannerChromeRules.allowsInteractiveGlass(reduceMotion: false))
    }
}
