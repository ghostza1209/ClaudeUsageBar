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
    @AppStorage(Usage.gaugeColorKey) private var gaugeColor = GaugeColor.claude
    @AppStorage(Usage.gaugeWindowKey) private var gaugeWindow = GaugeWindow.weekly
    @AppStorage(Usage.tourDoneKey) private var tourDone = false
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var updatingPrices = false
    @State private var priceError: String?
    @State private var checkingUpdate = false
    @State private var updateCheck: Result<String?, UpdateCheckError>?

    var body: some View {
        VStack(spacing: 6) {
            Card("Menu bar") {
                row("gauge.with.dots.needle.67percent", "Show", "Which Plan limit the gauge tracks.") {
                    Picker("", selection: $gaugeWindow) {
                        ForEach(GaugeWindow.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                row("paintpalette", "Colour", gaugeColor.title) {
                    HStack(spacing: 8) {
                        ForEach(GaugeColor.allCases, id: \.self) { choice in
                            Button { gaugeColor = choice } label: {
                                Circle().fill(choice.swiftColor).frame(width: 14, height: 14)
                                    .overlay { Circle().strokeBorder(.primary, lineWidth: gaugeColor == choice ? 1.5 : 0).padding(-3) }
                            }
                            .buttonStyle(.plain).help(choice.title).accessibilityLabel(choice.title)
                        }
                    }
                }
            }
            Card("General") {
                row("power", "Launch at login", "Start Claude Usage Bar when you log in.") {
                    Toggle("", isOn: Binding(get: { loginStatus == .enabled }, set: setLaunchAtLogin)).labelsHidden().toggleStyle(.switch)
                }
                if loginStatus == .requiresApproval {
                    note("Approve ClaudeUsageBar in System Settings > General > Login Items.", .orange)
                }
                if let loginError { note(loginError, .red) }
                row("calendar", "Billing cycle starts on", "The Billing cycle card counts from this day. Short months use their last day.") {
                    stepper("Day \(billingCycleStartDay)", $billingCycleStartDay, 1...31, step: 1)
                }
                row("questionmark.circle", "Product tour", "Walk through the app again.") {
                    Button("Show again") { tourDone = false }
                }
            }
            Card("Plan-limit alerts") {
                row("bell", "Notifications", "Alert when a Plan limit crosses a threshold.") {
                    Toggle("", isOn: $notificationsEnabled).labelsHidden().toggleStyle(.switch)
                }
                // Each range keeps warning < critical, so an invalid pair cannot be stored.
                row("exclamationmark.triangle", "Warning at", nil, tint: .orange) {
                    stepper("\(warning)%", $warning, 50...(critical - 5), step: 5)
                }
                row("exclamationmark.octagon", "Critical at", nil, tint: .red) {
                    stepper("\(critical)%", $critical, (warning + 5)...100, step: 5)
                }
                note("These thresholds also colour the Plan-limits rings.")
            }
            Card("Plan-limits source") {
                row(usage.wrapperInstalled ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                    usage.wrapperInstalled ? "Connected to Claude Code" : "Not connected",
                    "A small statusline script passes your Plan limits from Claude Code to this app. Your existing statusline keeps working.",
                    tint: usage.wrapperInstalled ? .green : .orange) {
                    if usage.wrapperInstalled {
                        Button("Uninstall") { usage.uninstallWrapper() }
                    } else {
                        Button("Install") { usage.installWrapper() }.buttonStyle(.borderedProminent)
                    }
                }
                if let error = usage.wrapperError { note(error, .red) }
            }
            Card("Prices") {
                row("dollarsign.circle", "Model prices", priceAgeText(fetchedAt: usage.pricesFetchedAt, now: .now)) {
                    HStack(spacing: 6) {
                        if updatingPrices { ProgressView().controlSize(.small) }
                        Button("Refresh prices", action: updatePrices).disabled(updatingPrices)
                    }
                }
                if let priceError { note("Refresh failed: \(priceError)", .red) }
            }
            Card("App version") {
                row("app.badge", "Version \(Usage.appVersion ?? "unknown")", nil) {
                    HStack(spacing: 6) {
                        if checkingUpdate { ProgressView().controlSize(.small) }
                        if let version = usage.updateAvailable {
                            Button(usage.updating ? "Updating…" : usage.updateFailed ? "Retry install" : "Install \(version)") {
                                usage.installUpdate()
                            }
                                .buttonStyle(.borderedProminent).disabled(usage.updating)
                        } else {
                            Button("Check for updates", action: checkForUpdate).disabled(checkingUpdate)
                        }
                    }
                }
                if let version = usage.updateAvailable {
                    note("Version \(version) is available.")
                } else if case .success = updateCheck {
                    note("You're up to date.")
                } else if case .failure(let error) = updateCheck {
                    note("Check failed: \(error.message)", .red)
                }
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

    /// Icon, title and an optional one-line explanation on the left; the control on the right.
    private func row(_ icon: String, _ title: String, _ detail: String?, tint: Color = .secondary,
                     @ViewBuilder control: () -> some View) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint).frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            control()
        }
    }

    private func stepper(_ value: String, _ binding: Binding<Int>, _ range: ClosedRange<Int>, step: Int) -> some View {
        HStack(spacing: 6) {
            Text(value).monospacedDigit()
            Stepper("", value: binding, in: range, step: step).labelsHidden()
        }
    }

    private func note(_ text: String, _ style: Color = .secondary) -> some View {
        Text(text).font(.caption).foregroundStyle(style).padding(.leading, 24)
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

    private func checkForUpdate() {
        checkingUpdate = true
        Task {
            updateCheck = await usage.checkForUpdate()
            checkingUpdate = false
        }
    }
}
