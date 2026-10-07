import Foundation

public struct StatuslineError: Error, LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

/// The statusline wrapper: a `/bin/sh` script in `supportDir` that `~/.claude/settings.json` points `statusLine.command` at.
/// It captures Claude Code's stdin for the Plan limits and chains to the previous statusline command.
public struct StatuslineWrapper: Sendable {
    /// The capture file (ticket 20 reads it; its mtime is the captured-at time).
    public static let captureFileName = "statusline-input.json"

    private static let script = """
        #!/bin/sh
        # Claude Usage Bar: captures Claude Code's statusline stdin, then chains to the previous statusline command.
        dir=$(dirname "$0")
        input=$(cat)
        # A capture failure (full or unwritable disk, ...) must never break the chained output.
        {
            case $input in
            *'"rate_limits"'*)
                printf '%s\\n' "$input" > "$dir/.capture.$$" && mv -f "$dir/.capture.$$" "$dir/\(captureFileName)" || rm -f "$dir/.capture.$$"
                ;;
            esac
        } 2>/dev/null
        if [ -s "$dir/chain.sh" ]; then
            printf '%s\\n' "$input" | /bin/sh "$dir/chain.sh"
        fi

        """

    public let claudeHome: URL
    public let supportDir: URL

    public init(claudeHome: URL, supportDir: URL) {
        (self.claudeHome, self.supportDir) = (claudeHome, supportDir)
    }

    public var captureURL: URL { supportDir.appending(path: Self.captureFileName) }
    private var settingsURL: URL { claudeHome.appending(path: "settings.json") }
    private var scriptURL: URL { supportDir.appending(path: "statusline.sh") }
    private var chainURL: URL { supportDir.appending(path: "chain.sh") }
    private var previousURL: URL { supportDir.appending(path: "previous-statusline.json") }

    /// The single-quoted absolute path of `statusline.sh`; a `'` in the path is written `'\\''`.
    public var command: String {
        "'" + scriptURL.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// True iff `statusLine.command` exactly equals `command`. An unreadable settings.json counts as not installed.
    public func isInstalled() -> Bool {
        guard let settings = try? readSettings() else { return false }
        return (settings["statusLine"] as? [String: Any])?["command"] as? String == command
    }

    /// Chains to the current `statusLine.command` and points it at the wrapper. A no-op while already installed
    /// (chaining to ourselves would loop). An unparseable settings.json throws before anything is written.
    public func install() throws {
        var settings = try readSettings()
        let previous = settings["statusLine"]
        var statusLine = previous as? [String: Any] ?? [:]
        if statusLine["command"] as? String == command { return }
        let chain = statusLine["command"] as? String ?? ""

        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine

        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        try Data(chain.utf8).write(to: chainURL, options: .atomic)
        try JSONSerialization.data(withJSONObject: previous ?? NSNull(), options: .fragmentsAllowed)
            .write(to: previousURL, options: .atomic)
        try Data(Self.script.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try writeSettings(settings)
    }

    /// Restores the previous `statusLine` (or removes the key) only while the command is still ours, then deletes the
    /// wrapper files. An unparseable settings.json throws and deletes nothing, so the statusline keeps working.
    public func uninstall() throws {
        var settings = try readSettings()
        if (settings["statusLine"] as? [String: Any])?["command"] as? String == command {
            let previous = try? JSONSerialization.jsonObject(
                with: Data(contentsOf: previousURL), options: .fragmentsAllowed)
            settings["statusLine"] = previous is NSNull ? nil : previous
            try writeSettings(settings)
        }
        for url in [scriptURL, chainURL, previousURL, captureURL] { try? FileManager.default.removeItem(at: url) }
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StatuslineError(message: "settings.json is not a valid JSON object, so it was left untouched")
        }
        return settings
    }

    /// Resolves a symlinked settings.json first, so a dotfiles setup keeps its link.
    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .withoutEscapingSlashes])
        try FileManager.default.createDirectory(at: claudeHome, withIntermediateDirectories: true)
        try data.write(to: settingsURL.resolvingSymlinksInPath(), options: .atomic)
    }
}
