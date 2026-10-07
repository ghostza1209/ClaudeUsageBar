import ServiceManagement
import SwiftUI
import UsageCore

/// Shown inside the popover in place of the tabs. Launch at login and the statusline state are read from their real
/// source (`SMAppService.mainApp.status`, `Usage.wrapperInstalled`) whenever the view appears and after each action.
/// Steppers, not pop-up menus: a menu would resign the popover's key status and close it.
struct SettingsView: View {
    let usage: Usage
    @AppStorage(Usage.billingCycleStartDayKey) private var billingCycleStartDay = 1
    @AppStorage(Usage.notificationsEnabledKey) private var notificationsEnabled = true
    @AppStorage(Usage.warningThresholdKey) private var warning = 80
    @AppStorage(Usage.criticalThresholdKey) private var critical = 95
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var updatingPrices = false
    @State private var priceError: String?

    var body: some View {
        VStack(spacing: 6) {
            Card("General") {
                LabeledContent("Launch at login") {
                    Toggle("", isOn: Binding(get: { loginStatus == .enabled }, set: setLaunchAtLogin)).labelsHidden()
                }
                if loginStatus == .requiresApproval {
                    note("Approve ClaudeUsageBar in System Settings > General > Login Items.")
                }
                if let loginError { note(loginError, .red) }
                stepper("Billing-cycle start day", "\(billingCycleStartDay)", $billingCycleStartDay, 1...31, step: 1)
                note("Months shorter than this use their last day.")
            }
            Card("Notifications") {
                LabeledContent("Plan-limit notifications") {
                    Toggle("", isOn: $notificationsEnabled).labelsHidden()
                }
                // Each range keeps warning < critical, so an invalid pair cannot be stored.
                stepper("Warning at", "\(warning)%", $warning, 50...(critical - 5), step: 5)
                stepper("Critical at", "\(critical)%", $critical, (warning + 5)...100, step: 5)
                note("The thresholds also colour the Plan-limits rings.")
            }
            Card("Statusline") {
                HStack {
                    Text(usage.wrapperInstalled ? "Wrapper installed" : "Wrapper not installed")
                    Spacer()
                    Button("Install") { usage.installWrapper() }.disabled(usage.wrapperInstalled)
                    Button("Uninstall") { usage.uninstallWrapper() }
                }
                if let error = usage.wrapperError { note(error, .red) }
            }
            Card("Prices") {
                HStack {
                    Text(priceAgeText(fetchedAt: usage.pricesFetchedAt, now: .now))
                    Spacer()
                    if updatingPrices { ProgressView().controlSize(.small) }
                    Button("Update now", action: updatePrices).disabled(updatingPrices)
                }
                if let priceError { note("Update failed: \(priceError)", .red) }
            }
        }
        .controlSize(.small)
        .font(.callout)
        .onChange(of: notificationsEnabled) {
            if notificationsEnabled { Task { await usage.notifier.requestAuthorization() } }
        }
        .onAppear {
            usage.refreshWrapper()
            loginStatus = SMAppService.mainApp.status
        }
    }

    private func stepper(_ title: String, _ value: String, _ binding: Binding<Int>, _ range: ClosedRange<Int>, step: Int) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(value).monospacedDigit()
                Stepper("", value: binding, in: range, step: step).labelsHidden()
            }
        }
    }

    private func note(_ text: String, _ style: Color = .secondary) -> some View {
        Text(text).font(.caption2).foregroundStyle(style)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        loginStatus = SMAppService.mainApp.status
    }

    private func updatePrices() {
        updatingPrices = true
        Task {
            if case .failure(let error) = await usage.updatePrices() { priceError = error.message } else { priceError = nil }
            updatingPrices = false
        }
    }
}
