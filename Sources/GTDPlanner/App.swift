import SwiftUI

@main
struct GTDPlannerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup("GTD Planner") {
            ModernContentView()
                .environment(model)
                .frame(minWidth: 1280, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1575, height: 980)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建任务") { model.showNewTask = true }
                    .keyboardShortcut("n", modifiers: [.command])
            }
        }
        Settings {
            SettingsView().environment(model)
        }
    }
}
