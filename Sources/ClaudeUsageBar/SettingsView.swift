import ServiceManagement
import SwiftUI
import UsageCore

/// One grouped form, four sections. Launch at login and the statusline state are read from their real source
/// (`SMAppService.mainApp.status`, `Usage.wrapperInstalled`) whenever the window becomes key and after each action.
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
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { loginStatus == .enabled }, set: setLaunchAtLogin))
                if loginStatus == .requiresApproval {
                    note("Approve ClaudeUsageBar in System Settings > General > Login Items.")
                }
                if let loginError { note(loginError, .red) }
                Picker("Billing-cycle start day", selection: $billingCycleStartDay) {
                    ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                }
                note("Months shorter than this use their last day.")
            }
            Section("Notifications") {
                Toggle("Plan-limit notifications", isOn: $notificationsEnabled)
                // Each picker only offers values that keep warning < critical, so an invalid pair cannot be stored.
                Picker("Warning at", selection: $warning) {
                    ForEach(Array(stride(from: 50, through: critical - 5, by: 5)), id: \.self) { Text("\($0)%").tag($0) }
                }
                Picker("Critical at", selection: $critical) {
                    ForEach(Array(stride(from: warning + 5, through: 100, by: 5)), id: \.self) { Text("\($0)%").tag($0) }
                }
                note("The thresholds also colour the Plan-limits rings.")
            }
            Section("Statusline") {
                LabeledContent("Wrapper", value: usage.wrapperInstalled ? "Installed" : "Not installed")
                HStack {
                    Button("Install") { usage.installWrapper() }.disabled(usage.wrapperInstalled)
                    Button("Uninstall") { usage.uninstallWrapper() }
                }
                if let error = usage.wrapperError { note(error, .red) }
            }
            Section("Prices") {
                LabeledContent("Price table", value: priceAgeText(fetchedAt: usage.pricesFetchedAt, now: .now))
                HStack {
                    Button("Update now", action: updatePrices).disabled(updatingPrices)
                    if updatingPrices { ProgressView().controlSize(.small) }
                }
                if let priceError { note("Update failed: \(priceError)", .red) }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: notificationsEnabled) {
            if notificationsEnabled { Task { await usage.notifier.requestAuthorization() } }
        }
        .background(KeyWindowObserver { isKey in
            guard isKey else { return }
            usage.refreshWrapper()
            loginStatus = SMAppService.mainApp.status
        })
    }

    private func note(_ text: String, _ style: Color = .secondary) -> some View {
        Text(text).font(.caption).foregroundStyle(style)
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
