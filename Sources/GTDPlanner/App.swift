import SwiftUI

@main
struct GTDPlannerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("GTD Planner") {
            ModernContentView()
                .environment(model)
                .environment(model.preferences)
                .frame(minWidth: 1280, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1575, height: 980)
        .windowResizability(.contentMinSize)
        .commands {
            PlannerTaskCommands(model: model)
        }
        Settings {
            PlannerSettingsView()
                .environment(model)
                .environment(model.preferences)
        }
        .windowResizability(.contentSize)
    }
}
