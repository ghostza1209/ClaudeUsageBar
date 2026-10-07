import AppKit
import SwiftUI
import UsageCore

@main
struct ClaudeUsageBarApp: App {
    @State private var usage = Usage()

    var body: some Scene {
        MenuBarExtra {
            Popover()
        } label: {
            Image(systemName: "sparkle")
            if let title = usage.title { Text(title) }
        }
        .menuBarExtraStyle(.window)
        Settings {
            Text("Settings").frame(width: 360, height: 200)
        }
    }
}

/// Menu bar title: nil (icon only) while the cold scan runs.
@MainActor @Observable final class Usage {
    var title: String?

    init() {
        Task {
            let store = await Task.detached(priority: .background) {
                scanUsageLogs(claudeHome: FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude"))
            }.value
            title = menuBarTitle(store, prices: .bundled, now: .now, calendar: .current)
        }
    }
}

struct Popover: View {
    @State private var tab = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox {
                Text("No Plan limits yet.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text("Plan limits").font(.caption.bold())
            }
            Picker("", selection: $tab) {
                Text("Usage").tag(0)
                Text("Processes").tag(1)
                Text("Git").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            Text(["Usage", "Processes", "Git"][tab] + " coming soon.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
            Divider()
            HStack {
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })
            }
        }
        .padding(12)
        .frame(width: 380)
    }
}
