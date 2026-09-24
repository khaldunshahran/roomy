import SwiftUI

/// Reminder opt-in shown after the paywall is declined.
struct ReminderOptInView: View {
    @EnvironmentObject var appState: AppState

    @State private var isWorking = false

    private var saved: String { FormatHelpers.bytes(appState.lastResultBytesSaved) }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("No worries, your \(saved) is yours to keep.")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text("Want a heads-up when there's more space to reclaim? You pick the moment. We'll never spam you, that's a promise.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                optionButton(title: "Sundays at 8pm, weekly — recommended", frequency: .weekly)
                optionButton(title: "First of the month, monthly", frequency: .monthly)

                Button("No thanks, I'll be back") {
                    appState.route = .main
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("No thanks, I'll be back")
                .disabled(isWorking)
            }

            Text("While your phone rests, Roomy quietly checks for new space to save. We only ping you when there's something worth knowing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }

    private func optionButton(title: String, frequency: ReminderScheduler.Frequency) -> some View {
        Button {
            Task { await choose(frequency) }
        } label: {
            HStack {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Spacer()
                if isWorking {
                    SwiftUI.ProgressView()
                        .accessibilityHidden(true)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel(title)
    }

    private func choose(_ frequency: ReminderScheduler.Frequency) async {
        isWorking = true
        defer { isWorking = false }
        _ = await ReminderScheduler.requestAuthorization()
        ReminderScheduler.save(
            ReminderScheduler.Schedule(
                isEnabled: true,
                frequency: frequency,
                weekday: 1,
                hour: 20,
                minute: 0
            )
        )
        await ReminderScheduler.applySchedule()
        appState.route = .main
    }
}
