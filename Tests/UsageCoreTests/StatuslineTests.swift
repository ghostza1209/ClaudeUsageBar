import Foundation
import Testing
import UsageCore

private struct Fixture {
    let home: URL, support: URL, wrapper: StatuslineWrapper
    var settings: URL { home.appending(path: "settings.json") }

    /// `supportName` can carry the awkward characters of the real path: a space and a single quote.
    init(settings json: String? = nil, supportName: String = "Application Support") throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        home = root.appending(path: ".claude")
        support = root.appending(path: supportName).appending(path: "ClaudeUsageBar")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        wrapper = StatuslineWrapper(claudeHome: home, supportDir: support)
        if let json { try Data(json.utf8).write(to: settings) }
    }

    func settingsObject() throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
    }

    func supportFile(_ name: String) -> String? { try? String(contentsOf: support.appending(path: name), encoding: .utf8) }

    /// Runs the settings command the way Claude Code does (through a shell), feeding `stdin`.
    func runInstalledCommand(stdin: String) throws -> (stdout: String, stderr: String, status: Int32) {
        try run("/bin/sh", ["-c", wrapper.command], stdin: stdin)
    }
}

private func run(_ tool: String, _ arguments: [String], stdin: String) throws -> (stdout: String, stderr: String, status: Int32) {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = arguments
    let (input, output, errors) = (Pipe(), Pipe(), Pipe())
    (process.standardInput, process.standardOutput, process.standardError) = (input, output, errors)
    try process.run()
    input.fileHandleForWriting.write(Data(stdin.utf8))
    try input.fileHandleForWriting.close()
    let stdout = output.fileHandleForReading.readDataToEndOfFile()
    let stderr = errors.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self), process.terminationStatus)
}

private let withLimits = #"{"model":"opus","rate_limits":{"five_hour":{"used_percentage":42,"resets_at":1790000000}}}"#
private let withoutLimits = #"{"model":"opus"}"#
/// claude-hud's shape: a `bash -c '...'` with double quotes, `$(...)` and a `${VAR:-x}` expansion nested inside single quotes.
private let hudStyle = #"bash -c 'p="${HUD_DIR:-x}"; echo "hud[$p]: $(cat | tr -d "\n")"'"#

// MARK: install

@Test func installWithNoSettingsFileCreatesJustTheStatusLineAndAnEmptyChain() throws {
    let f = try Fixture()
    #expect(!f.wrapper.isInstalled())
    try f.wrapper.install()

    #expect(f.wrapper.isInstalled())
    let statusLine = try #require(f.settingsObject()["statusLine"] as? [String: Any])
    #expect(statusLine["command"] as? String == "'\(f.support.path)/statusline.sh'")
    #expect(statusLine["type"] as? String == "command")
    #expect(try f.settingsObject().keys.sorted() == ["statusLine"])
    #expect(f.supportFile("chain.sh") == "")
    #expect(f.supportFile("previous-statusline.json") == "null")
    let mode = try FileManager.default.attributesOfItem(atPath: f.support.appending(path: "statusline.sh").path)[.posixPermissions] as? Int
    #expect(mode == 0o755)
}

@Test func installChainsTheNestedQuoteCommandVerbatimAndKeepsOtherKeys() throws {
    let f = try Fixture(settings: """
        {"theme": "dark", "hooks": {"Stop": [{"command": "a/b"}]},
         "statusLine": {"type": "command", "command": \(String(decoding: try JSONSerialization.data(withJSONObject: hudStyle, options: .fragmentsAllowed), as: UTF8.self)), "padding": 2}}
        """)
    try f.wrapper.install()

    #expect(f.supportFile("chain.sh") == hudStyle)
    let settings = try f.settingsObject()
    #expect(settings["theme"] as? String == "dark")
    #expect(settings["hooks"] as? [String: [[String: String]]] == ["Stop": [["command": "a/b"]]])
    let statusLine = try #require(settings["statusLine"] as? [String: Any])
    #expect(statusLine["padding"] as? Int == 2)
    #expect(statusLine["command"] as? String == f.wrapper.command)
    let previous = try #require(f.supportFile("previous-statusline.json"))
    let previousObject = try #require(JSONSerialization.jsonObject(with: Data(previous.utf8)) as? [String: Any])
    #expect(previousObject["command"] as? String == hudStyle)
    #expect(previousObject["padding"] as? Int == 2)
    // no escaped slashes
    #expect(try String(contentsOf: f.settings, encoding: .utf8).contains(#""command" : "a/b""#))
}

@Test func installWhileInstalledDoesNotChainToItself() throws {
    let f = try Fixture(settings: #"{"statusLine": {"type": "command", "command": "echo old"}}"#)
    try f.wrapper.install()
    try f.wrapper.install()

    #expect(f.supportFile("chain.sh") == "echo old")
    #expect(try f.runInstalledCommand(stdin: withoutLimits).stdout == "old\n")
}

@Test func reinstallAfterAnotherToolOverwroteTheCommandChainsTheNewOne() throws {
    let f = try Fixture(settings: #"{"statusLine": {"type": "command", "command": "echo old"}}"#)
    try f.wrapper.install()
    try Data(#"{"statusLine": {"type": "command", "command": "echo newer"}}"#.utf8).write(to: f.settings)
    #expect(!f.wrapper.isInstalled())
    try f.wrapper.install()

    #expect(f.wrapper.isInstalled())
    #expect(try f.runInstalledCommand(stdin: withoutLimits).stdout == "newer\n")
}

// MARK: detection

@Test func detectionIsAnExactMatchOfTheCommand() throws {
    let f = try Fixture()
    for command in ["echo hi", f.wrapper.command + " ", "\(f.support.path)/statusline.sh"] {
        let json = try JSONSerialization.data(withJSONObject: ["statusLine": ["command": command]])
        try json.write(to: f.settings)
        #expect(!f.wrapper.isInstalled(), "\(command)")
    }
    let json = try JSONSerialization.data(withJSONObject: ["statusLine": ["command": f.wrapper.command]])
    try json.write(to: f.settings)
    #expect(f.wrapper.isInstalled())
}

@Test func detectionIsFalseWhenSettingsIsMissingOrBroken() throws {
    let f = try Fixture()
    #expect(!f.wrapper.isInstalled())
    try Data("{nope".utf8).write(to: f.settings)
    #expect(!f.wrapper.isInstalled())
}

// MARK: uninstall

@Test func uninstallRestoresTheWholePreviousObjectAndDeletesTheFiles() throws {
    let f = try Fixture(settings: #"{"theme": "dark", "statusLine": {"type": "command", "command": "echo old", "padding": 3}}"#)
    try f.wrapper.install()
    try Data(withLimits.utf8).write(to: f.wrapper.captureURL)
    try f.wrapper.uninstall()

    let settings = try f.settingsObject()
    #expect(settings["theme"] as? String == "dark")
    let statusLine = try #require(settings["statusLine"] as? [String: Any])
    #expect(statusLine["command"] as? String == "echo old")
    #expect(statusLine["padding"] as? Int == 3)
    #expect(statusLine.count == 3)
    #expect(!f.wrapper.isInstalled())
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.support.path) == [])
}

@Test func uninstallWithNoPreviousStatusLineRemovesTheKey() throws {
    let f = try Fixture(settings: #"{"theme": "dark"}"#)
    try f.wrapper.install()
    try f.wrapper.uninstall()

    #expect(try f.settingsObject().keys.sorted() == ["theme"])
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.support.path) == [])
}

@Test func uninstallLeavesAUserChangedCommandAloneButDeletesTheFiles() throws {
    let f = try Fixture(settings: #"{"statusLine": {"type": "command", "command": "echo old"}}"#)
    try f.wrapper.install()
    let changed = #"{"statusLine":{"type":"command","command":"echo mine"}}"#
    try Data(changed.utf8).write(to: f.settings)
    try f.wrapper.uninstall()

    #expect(try String(contentsOf: f.settings, encoding: .utf8) == changed)
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.support.path) == [])
}

// MARK: unparseable settings.json

@Test(arguments: ["{nope", "", "[1, 2]"])
func anUnparseableSettingsFileIsNeverWritten(contents: String) throws {
    let f = try Fixture(settings: contents)
    #expect(throws: StatuslineError.self) { try f.wrapper.install() }
    #expect(try String(contentsOf: f.settings, encoding: .utf8) == contents)
    #expect(!FileManager.default.fileExists(atPath: f.support.path))
}

@Test func uninstallWithAnUnparseableSettingsFileThrowsAndKeepsTheWrapperWorking() throws {
    let f = try Fixture(settings: #"{"statusLine": {"command": "echo old"}}"#)
    try f.wrapper.install()
    try Data("{nope".utf8).write(to: f.settings)
    #expect(throws: StatuslineError.self) { try f.wrapper.uninstall() }
    #expect(f.supportFile("statusline.sh") != nil)
    #expect(try String(contentsOf: f.settings, encoding: .utf8) == "{nope")
}

// MARK: the wrapper script, run with /bin/sh against real stdin

@Test func theWrapperCapturesStdinOnlyWithRateLimitsAndAlwaysChains() throws {
    let f = try Fixture(settings: #"{"statusLine": {"type": "command", "command": "cat"}}"#)
    try f.wrapper.install()

    let first = try f.runInstalledCommand(stdin: withLimits)
    #expect(first.stdout == withLimits + "\n")
    #expect(f.supportFile("statusline-input.json") == withLimits + "\n")

    let second = try f.runInstalledCommand(stdin: withoutLimits)
    #expect(second.stdout == withoutLimits + "\n")
    #expect(f.supportFile("statusline-input.json") == withLimits + "\n")  // untouched
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.support.path).sorted()
        == ["chain.sh", "previous-statusline.json", "statusline-input.json", "statusline.sh"])  // no temp left behind
}

@Test func theWrapperChainsAClaudeHudStyleNestedQuoteCommandIntact() throws {
    let f = try Fixture(settings: #"{"statusLine": {"type": "command", "command": \#(String(decoding: try JSONSerialization.data(withJSONObject: hudStyle, options: .fragmentsAllowed), as: UTF8.self))}}"#)
    try f.wrapper.install()

    let result = try f.runInstalledCommand(stdin: withLimits)
    #expect(result.stdout == "hud[x]: " + withLimits + "\n")
    #expect(result.status == 0)
}

@Test func aCaptureFailureStillChainsAndStaysQuiet() throws {
    let f = try Fixture(settings: #"{"statusLine": {"type": "command", "command": "cat"}}"#)
    try f.wrapper.install()
    // a read-only support dir: the capture's temp file cannot be created
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: f.support.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.support.path) }

    let result = try f.runInstalledCommand(stdin: withLimits)
    #expect(result.stdout == withLimits + "\n")
    #expect(result.stderr == "")
    #expect(result.status == 0)
}

@Test func withNoPreviousStatusLineTheWrapperPrintsNothingButStillCaptures() throws {
    let f = try Fixture()
    try f.wrapper.install()

    let result = try f.runInstalledCommand(stdin: withLimits)
    #expect(result.stdout == "")
    #expect(result.status == 0)
    #expect(f.supportFile("statusline-input.json") == withLimits + "\n")
}

@Test func theCommandSurvivesAQuoteAndASpaceInThePath() throws {
    let f = try Fixture(settings: #"{"statusLine": {"type": "command", "command": "cat"}}"#, supportName: "Bob's Application Support")
    try f.wrapper.install()

    #expect(f.wrapper.command.contains(#"Bob'\''s Application Support"#))
    #expect(try f.runInstalledCommand(stdin: withLimits).stdout == withLimits + "\n")
    #expect(f.supportFile("statusline-input.json") == withLimits + "\n")
    #expect(f.wrapper.isInstalled())
}
