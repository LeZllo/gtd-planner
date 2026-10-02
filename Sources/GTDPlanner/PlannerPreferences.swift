import CoreFoundation
import Foundation
import Observation
import SwiftUI

enum PlannerAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum PlannerSettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case appearance
    case data
    case about

    var id: String { rawValue }
}

/// Device-local preferences, separate from the user's task database and JSON
/// backups. Share one instance between AppModel and every application window.
/// A suite can be injected so tests never read or change the real app domain.
@MainActor
@Observable
final class PlannerPreferences {
    enum Key {
        static let appearance = "planner.preferences.appearance"
        static let defaultTodayViewMode = "planner.preferences.defaultTodayViewMode"
        static let defaultPomodoroMinutes = "planner.preferences.defaultPomodoroMinutes"
        static let selectedSettingsTab = "planner.preferences.selectedSettingsTab"
    }

    static let pomodoroMinutesRange = 1...180
    static let standardPomodoroMinutes = 25

    @ObservationIgnored private let defaults: UserDefaults

    var appearance: PlannerAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }

    var defaultTodayViewMode: TodayViewMode {
        didSet { defaults.set(defaultTodayViewMode.rawValue, forKey: Key.defaultTodayViewMode) }
    }

    private var storedPomodoroMinutes: Int

    var defaultPomodoroMinutes: Int {
        get { storedPomodoroMinutes }
        set {
            let normalized = Self.clampMinutes(newValue)
            // Observe the normalized storage value. A computed setter also
            // avoids self-assignment in an @Observable didSet expansion.
            storedPomodoroMinutes = normalized
            defaults.set(normalized, forKey: Key.defaultPomodoroMinutes)
        }
    }

    var selectedSettingsTab: PlannerSettingsTab {
        didSet { defaults.set(selectedSettingsTab.rawValue, forKey: Key.selectedSettingsTab) }
    }

    var defaultPomodoroDuration: TimeInterval {
        TimeInterval(defaultPomodoroMinutes) * 60
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Key.appearance)
            .flatMap(PlannerAppearance.init(rawValue:)) ?? .system
        defaultTodayViewMode = defaults.string(forKey: Key.defaultTodayViewMode)
            .flatMap(TodayViewMode.init(rawValue:)) ?? .schedule
        storedPomodoroMinutes = Self.readMinutes(from: defaults)
        selectedSettingsTab = defaults.string(forKey: Key.selectedSettingsTab)
            .flatMap(PlannerSettingsTab.init(rawValue:)) ?? .general
        // Reading preferences must not write to UserDefaults. In particular,
        // existing model tests can construct an AppModel without changing the
        // real app domain. Only user changes persist these four owned keys.
    }

    private static func clampMinutes(_ value: Int) -> Int {
        min(pomodoroMinutesRange.upperBound, max(pomodoroMinutesRange.lowerBound, value))
    }

    private static func readMinutes(from defaults: UserDefaults) -> Int {
        guard let number = defaults.object(forKey: Key.defaultPomodoroMinutes) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return standardPomodoroMinutes
        }
        let value = number.doubleValue
        guard value.isFinite, value.rounded() == value else { return standardPomodoroMinutes }
        // Clamp before converting to Int so even malformed huge numeric
        // values cannot overflow at initialization.
        return Int(min(Double(pomodoroMinutesRange.upperBound), max(Double(pomodoroMinutesRange.lowerBound), value)))
    }
}
