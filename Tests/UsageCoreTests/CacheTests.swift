import Foundation
import Testing
import UsageCore

private func ids(_ cache: UsageCache) -> [String] {
    cache.store.records.map(\.messageId).sorted()
}

private func append(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
    try handle.close()
}

@Test func halfWrittenLineWaitsForItsNewline() throws {
    let home = try tree(["-w/s.jsonl": [line(id: "a")]])
    let log = home.appending(path: "projects/-w/s.jsonl")
    let b = line(id: "b")
    try append(String(b.prefix(40)), to: log)
    var cache = UsageCache()
    cache.update(claudeHome: home, now: now, calendar: bangkok)
    #expect(ids(cache) == ["a"])

    try append(String(b.dropFirst(40)) + "\n", to: log)
    cache.update(claudeHome: home, now: now, calendar: bangkok)
    #expect(ids(cache) == ["a", "b"])
}

@Test func fileTruncatedInPlaceIsReparsed() throws {
    let home = try tree(["-w/s.jsonl": [line(id: "a"), line(id: "a2")]])
    let log = home.appending(path: "projects/-w/s.jsonl")
    var cache = UsageCache()
    cache.update(claudeHome: home, now: now, calendar: bangkok)

    let handle = try FileHandle(forWritingTo: log)  // same inode, now shorter than the read offset
    try handle.truncate(atOffset: 0)
    try handle.write(contentsOf: Data((line(id: "b") + "\n").utf8))
    try handle.close()
    cache.update(claudeHome: home, now: now, calendar: bangkok)
    #expect(ids(cache) == ["b"])
}

@Test func replacedFileIsReparsed() throws {
    let home = try tree(["-w/s.jsonl": [line(id: "a")]])
    var cache = UsageCache()
    cache.update(claudeHome: home, now: now, calendar: bangkok)

    // New inode, and longer than the old offset, so only the inode tells it apart from an append.
    try Data([line(id: "b"), line(id: "c")].map { $0 + "\n" }.joined().utf8)
        .write(to: home.appending(path: "projects/-w/s.jsonl"), options: .atomic)
    cache.update(claudeHome: home, now: now, calendar: bangkok)
    #expect(ids(cache) == ["b", "c"])
}

@Test func deletedFileKeepsItsRecords() throws {
    let home = try tree(["-w/s.jsonl": [line(id: "a")], "-w/t.jsonl": [line(id: "b")]])
    var cache = UsageCache()
    cache.update(claudeHome: home, now: now, calendar: bangkok)
    try FileManager.default.removeItem(at: home.appending(path: "projects/-w/s.jsonl"))
    cache.update(claudeHome: home, now: now, calendar: bangkok)
    #expect(ids(cache) == ["a", "b"])
}

@Test func relaunchOverUnchangedTreeReadsNoBytes() throws {
    let real = try tree(["-w/s.jsonl": [line(id: "a")], "-w/s/subagents/agent-x.jsonl": [line(id: "b")]])
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)  // a symlinked ~/.claude
    try FileManager.default.createSymbolicLink(at: home, withDestinationURL: real)
    let url = real.appending(path: "cache.json")
    var cache = UsageCache()
    #expect(cache.update(claudeHome: home, now: now, calendar: bangkok) > 0)
    try cache.save(to: url)

    var relaunched = UsageCache.load(from: url)
    #expect(relaunched.update(claudeHome: home, now: now, calendar: bangkok) == 0)
    #expect(ids(relaunched) == ["a", "b"])
    // FSEvents reports real directory paths with a trailing slash; they must key the same files.
    let dir = real.appending(path: "projects/-w").resolvingSymlinksInPath().path + "/"
    #expect(relaunched.update(claudeHome: home, dirs: [dir], now: now, calendar: bangkok) == 0)

    try append(line(id: "c") + "\n", to: home.appending(path: "projects/-w/s.jsonl"))
    #expect(relaunched.update(claudeHome: home, dirs: [dir], now: now, calendar: bangkok) == line(id: "c").utf8.count + 1)
    #expect(ids(relaunched) == ["a", "b", "c"])
}

@Test func otherSchemaVersionForcesFullRescan() throws {
    let home = try tree(["-w/s.jsonl": [line(id: "a")]])
    let url = home.appending(path: "cache.json")
    var cache = UsageCache()
    cache.update(claudeHome: home, now: now, calendar: bangkok)
    try cache.save(to: url)
    let json = try String(contentsOf: url, encoding: .utf8)
    try #require(json.contains(#""version":1"#))
    try Data(json.replacingOccurrences(of: #""version":1"#, with: #""version":0"#).utf8).write(to: url)

    var stale = UsageCache.load(from: url)
    #expect(stale.update(claudeHome: home, now: now, calendar: bangkok) == line(id: "a").utf8.count + 1)
}

@Test func historyStopsAt62Days() throws {
    // Cutoff for 2026-10-07 in Bangkok is 2026-08-06 00:00 local = 2026-08-05T17:00:00Z.
    let home = try tree([
        "-w/old.jsonl": [line(id: "today-in-old-file")],
        "-w/new.jsonl": [
            line(id: "pruned", at: "2026-08-05T16:59:59.000Z"),
            line(id: "kept", at: "2026-08-05T17:00:00.000Z"),
        ],
    ])
    try FileManager.default.setAttributes(
        [.modificationDate: Date(timeIntervalSince1970: 1_785_949_199)],  // 2026-08-05T16:59:59Z
        ofItemAtPath: home.appending(path: "projects/-w/old.jsonl").path)
    var cache = UsageCache()
    cache.update(claudeHome: home, now: now, calendar: bangkok)
    #expect(ids(cache) == ["kept"])
    // A day later it ages out too.
    cache.update(claudeHome: home, now: now.addingTimeInterval(86_400), calendar: bangkok)
    #expect(ids(cache) == [])
}

@Test func progressReportsFilesDoneAndPartialRecords() throws {
    let home = try tree(["-w/a.jsonl": [line(id: "a")], "-w/b.jsonl": [line(id: "b")], "-w/c.jsonl": [line(id: "c"), line(id: "d")]])
    var cache = UsageCache()
    var calls: [(done: Int, total: Int, records: Int)] = []
    cache.update(claudeHome: home, now: now, calendar: bangkok) { calls.append(($0, $1, $2.records.count)) }
    // Calls are throttled, but the last file is always reported, with every record found.
    #expect(calls.last! == (3, 3, 4))
    #expect(calls.allSatisfy { $0.total == 3 })
}
