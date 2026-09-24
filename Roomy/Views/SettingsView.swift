import SwiftUI

/// App settings: default quality, location handling, reminders, purchase, about.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("roomy.defaultPreset") private var defaultPresetRaw: String = QualityPreset.smart.rawValue
    @AppStorage("roomy.keepLocation") private var keepLocation: Bool = false

    @State private var schedule: ReminderScheduler.Schedule = ReminderScheduler.load()
    @State private var refreshSeed = UUID()

    var body: some View {
        Form {
            Section("Compression") {
                Picker("Default quality", selection: presetBinding) {
                    ForEach(QualityPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                Toggle("Keep location data in compressed copies", isOn: $keepLocation)
                Text("When off, location is removed from copies. Dates are always kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Reminders") {
                Toggle("Space check reminders", isOn: remindersBinding)

                if schedule.isEnabled {
                    Picker("Frequency", selection: frequencyBinding) {
                        ForEach(ReminderScheduler.Frequency.allCases, id: \.self) { frequency in
                            Text(frequency == .weekly ? "Weekly" : "Monthly").tag(frequency)
                        }
                    }

                    Picker("Day", selection: dayBinding) {
                        ForEach(1...7, id: \.self) { weekday in
                            Text(weekdayName(weekday)).tag(weekday)
                        }
                    }

                    DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                }

                Text(ReminderScheduler.lastEstimateText() ?? "Estimates update when you open the app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Purchase") {
                HStack {
                    Text("Roomy Forever")
                    Spacer()
                    Text(appState.store.isUnlocked ? "Unlocked ✓" : "Not unlocked")
                        .foregroundStyle(appState.store.isUnlocked ? .green : .secondary)
                }
                Button("Restore Purchases") {
                    Task { await appState.store.restore() }
                }
                .accessibilityLabel("Restore Purchases")
                if let error = appState.store.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("About") {
                if let privacyURL = URL(string: Config.privacyPolicyURLString) {
                    Link("Privacy Policy", destination: privacyURL)
                }
                if let supportURL = URL(string: "mailto:\(Config.supportEmail)") {
                    Link("Contact Support", destination: supportURL)
                }
                Text("Version 1.0 (1)")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            appState.preset = QualityPreset(rawValue: defaultPresetRaw) ?? .smart
        }
        .onReceive(appState.store.objectWillChange) { _ in refreshSeed = UUID() }
    }

    private var presetBinding: Binding<QualityPreset> {
        Binding(
            get: { appState.preset },
            set: { newValue in
                appState.preset = newValue
                defaultPresetRaw = newValue.rawValue
            }
        )
    }

    private var remindersBinding: Binding<Bool> {
        Binding(
            get: { schedule.isEnabled },
            set: { newValue in
                schedule.isEnabled = newValue
                persistSchedule()
            }
        )
    }

    private var frequencyBinding: Binding<ReminderScheduler.Frequency> {
        Binding(
            get: { schedule.frequency },
            set: { newValue in
                schedule.frequency = newValue
                persistSchedule()
            }
        )
    }

    private var dayBinding: Binding<Int> {
        Binding(
            get: { schedule.weekday },
            set: { newValue in
                schedule.weekday = newValue
                persistSchedule()
            }
        )
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = schedule.hour
                components.minute = schedule.minute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                schedule.hour = parts.hour ?? 20
                schedule.minute = parts.minute ?? 0
                persistSchedule()
            }
        )
    }

    private func persistSchedule() {
        ReminderScheduler.save(schedule)
        Task { await ReminderScheduler.applySchedule() }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols // Sunday-first: index 0 == Sunday == weekday 1
        guard weekday >= 1, weekday <= symbols.count else { return "" }
        return symbols[weekday - 1]
    }
}
