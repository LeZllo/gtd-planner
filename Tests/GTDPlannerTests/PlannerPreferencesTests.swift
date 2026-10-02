import Foundation
import Observation
import SwiftUI
import Testing
@testable import GTDPlanner

@MainActor
struct PlannerPreferencesTests {
    @Test("An empty preferences suite has stable defaults and remains unwritten")
    func initialDefaults() throws {
        try withDefaults { defaults in
            let preferences = PlannerPreferences(defaults: defaults)

            #expect(preferences.appearance == .system)
            #expect(preferences.appearance.colorScheme == nil)
            #expect(preferences.defaultTodayViewMode == .schedule)
            #expect(preferences.defaultPomodoroMinutes == 25)
            #expect(preferences.defaultPomodoroDuration == 25 * 60)
            #expect(preferences.selectedSettingsTab == .general)
            #expect(defaults.object(forKey: PlannerPreferences.Key.appearance) == nil)
            #expect(defaults.object(forKey: PlannerPreferences.Key.defaultTodayViewMode) == nil)
            #expect(defaults.object(forKey: PlannerPreferences.Key.defaultPomodoroMinutes) == nil)
            #expect(defaults.object(forKey: PlannerPreferences.Key.selectedSettingsTab) == nil)
        }
    }

    @Test("Every preference persists and is restored by another instance")
    func valuesSurviveRecreation() throws {
        try withDefaults { defaults in
            let preferences = PlannerPreferences(defaults: defaults)
            preferences.appearance = .dark
            preferences.defaultTodayViewMode = .list
            preferences.defaultPomodoroMinutes = 42
            preferences.selectedSettingsTab = .data

            #expect(defaults.string(forKey: PlannerPreferences.Key.appearance) == "dark")
            #expect(defaults.string(forKey: PlannerPreferences.Key.defaultTodayViewMode) == "list")
            #expect(defaults.integer(forKey: PlannerPreferences.Key.defaultPomodoroMinutes) == 42)
            #expect(defaults.string(forKey: PlannerPreferences.Key.selectedSettingsTab) == "data")

            let restored = PlannerPreferences(defaults: defaults)
            #expect(restored.appearance == .dark)
            #expect(restored.defaultTodayViewMode == .list)
            #expect(restored.defaultPomodoroMinutes == 42)
            #expect(restored.defaultPomodoroDuration == 42 * 60)
            #expect(restored.selectedSettingsTab == .data)
        }
    }

    @Test("Appearance choices map to SwiftUI and all persist", arguments: PlannerAppearance.allCases)
    func appearanceRoundTrips(_ appearance: PlannerAppearance) throws {
        try withDefaults { defaults in
            let preferences = PlannerPreferences(defaults: defaults)
            preferences.appearance = appearance
            let restored = PlannerPreferences(defaults: defaults)
            #expect(restored.appearance == appearance)
            switch appearance {
            case .system: #expect(restored.appearance.colorScheme == nil)
            case .light: #expect(restored.appearance.colorScheme == .light)
            case .dark: #expect(restored.appearance.colorScheme == .dark)
            }
        }
    }

    @Test("Both default Today modes persist", arguments: TodayViewMode.allCases)
    func todayModeRoundTrips(_ mode: TodayViewMode) throws {
        try withDefaults { defaults in
            let preferences = PlannerPreferences(defaults: defaults)
            preferences.defaultTodayViewMode = mode
            #expect(PlannerPreferences(defaults: defaults).defaultTodayViewMode == mode)
        }
    }

    @Test("The last selected native Settings tab persists", arguments: PlannerSettingsTab.allCases)
    func selectedTabRoundTrips(_ tab: PlannerSettingsTab) throws {
        try withDefaults { defaults in
            let preferences = PlannerPreferences(defaults: defaults)
            preferences.selectedSettingsTab = tab
            #expect(PlannerPreferences(defaults: defaults).selectedSettingsTab == tab)
        }
    }

    @Test("All valid whole-minute Pomodoro durations persist", arguments: [1, 2, 25, 60, 179, 180])
    func validPomodoroDurationRoundTrips(_ minutes: Int) throws {
        try withDefaults { defaults in
            let preferences = PlannerPreferences(defaults: defaults)
            preferences.defaultPomodoroMinutes = minutes
            let restored = PlannerPreferences(defaults: defaults)
            #expect(restored.defaultPomodoroMinutes == minutes)
            #expect(restored.defaultPomodoroDuration == Double(minutes) * 60)
        }
    }

    @Test("Programmatic Pomodoro changes clamp and persist the normalized value",
          arguments: [Int.min, -100, 0, 181, 1_000, Int.max])
    func changedMinutesAreClamped(_ input: Int) throws {
        try withDefaults { defaults in
            let preferences = PlannerPreferences(defaults: defaults)
            let expected = min(180, max(1, input))
            preferences.defaultPomodoroMinutes = input

            #expect(preferences.defaultPomodoroMinutes == expected)
            #expect(defaults.integer(forKey: PlannerPreferences.Key.defaultPomodoroMinutes) == expected)
            #expect(PlannerPreferences(defaults: defaults).defaultPomodoroMinutes == expected)
        }
    }

    @Test("Out-of-range stored durations clamp on load",
          arguments: [Int.min, -100, 0, 181, 1_000, Int.max])
    func storedMinutesAreClamped(_ input: Int) throws {
        try withDefaults { defaults in
            defaults.set(input, forKey: PlannerPreferences.Key.defaultPomodoroMinutes)
            let preferences = PlannerPreferences(defaults: defaults)
            #expect(preferences.defaultPomodoroMinutes == min(180, max(1, input)))
        }
    }

    @Test("Huge stored numeric values cannot overflow Int conversion")
    func hugeStoredNumberIsSafe() throws {
        try withDefaults { defaults in
            defaults.set(Double.greatestFiniteMagnitude,
                         forKey: PlannerPreferences.Key.defaultPomodoroMinutes)
            #expect(PlannerPreferences(defaults: defaults).defaultPomodoroMinutes == 180)
            defaults.set(-Double.greatestFiniteMagnitude,
                         forKey: PlannerPreferences.Key.defaultPomodoroMinutes)
            #expect(PlannerPreferences(defaults: defaults).defaultPomodoroMinutes == 1)
        }
    }

    @Test("Unknown raw enum values fall back without rewriting stored data")
    func invalidRawValuesUseDefaults() throws {
        try withDefaults { defaults in
            defaults.set("sepia", forKey: PlannerPreferences.Key.appearance)
            defaults.set("board", forKey: PlannerPreferences.Key.defaultTodayViewMode)
            defaults.set("account", forKey: PlannerPreferences.Key.selectedSettingsTab)

            let preferences = PlannerPreferences(defaults: defaults)
            #expect(preferences.appearance == .system)
            #expect(preferences.defaultTodayViewMode == .schedule)
            #expect(preferences.selectedSettingsTab == .general)
            #expect(defaults.string(forKey: PlannerPreferences.Key.appearance) == "sepia")
            #expect(defaults.string(forKey: PlannerPreferences.Key.defaultTodayViewMode) == "board")
            #expect(defaults.string(forKey: PlannerPreferences.Key.selectedSettingsTab) == "account")
        }
    }

    @Test("Malformed numeric preferences fall back instead of coercing other types")
    func malformedStoredMinutesUseDefaults() throws {
        try withDefaults { defaults in
            let invalidValues: [Any] = [
                "45", "invalid", true, false, 12.5, [25], ["minutes": 25],
                Double.nan, Double.infinity, -Double.infinity
            ]
            for value in invalidValues {
                defaults.set(value, forKey: PlannerPreferences.Key.defaultPomodoroMinutes)
                #expect(PlannerPreferences(defaults: defaults).defaultPomodoroMinutes == 25)
            }
        }
    }

    @Test("Wrongly typed enum preferences safely use defaults")
    func nonStringRawValuesUseDefaults() throws {
        try withDefaults { defaults in
            defaults.set(["dark"], forKey: PlannerPreferences.Key.appearance)
            defaults.set(12, forKey: PlannerPreferences.Key.defaultTodayViewMode)
            defaults.set(true, forKey: PlannerPreferences.Key.selectedSettingsTab)
            let preferences = PlannerPreferences(defaults: defaults)
            #expect(preferences.appearance == .system)
            #expect(preferences.defaultTodayViewMode == .schedule)
            #expect(preferences.selectedSettingsTab == .general)
        }
    }

    @Test("Independent suites do not leak settings or replace unrelated defaults")
    func suitesRemainIsolated() throws {
        try withDefaults { first in
            try withDefaults { second in
                first.set("keep me", forKey: "unrelated.setting")
                let preferences = PlannerPreferences(defaults: first)
                preferences.appearance = .dark
                preferences.defaultPomodoroMinutes = 80

                let other = PlannerPreferences(defaults: second)
                #expect(other.appearance == .system)
                #expect(other.defaultPomodoroMinutes == 25)
                #expect(first.string(forKey: "unrelated.setting") == "keep me")
                #expect(second.object(forKey: PlannerPreferences.Key.appearance) == nil)
            }
        }
    }

    @Test("Duration projections participate in Observation")
    func preferenceChangesInvalidateObservers() async throws {
        let suiteName = "GTDPlannerTests.Preferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PlannerPreferences(defaults: defaults)

        await confirmation { invalidated in
            withObservationTracking {
                _ = preferences.defaultPomodoroDuration
            } onChange: {
                invalidated()
            }
            preferences.defaultPomodoroMinutes = 45
        }
        #expect(preferences.defaultPomodoroDuration == 45 * 60)
    }

    /// Every test gets a unique domain, including parameterized runs. Never
    /// use .standard or an application bundle ID to seed or clear test data.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "GTDPlannerTests.Preferences.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }
}
