import Foundation

/// Parsed records plus per-file read state, saved as one JSON file so later launches read only appended bytes.
/// Stores no prices: records are priced at display time.
public struct UsageCache: Codable, Sendable {
    private static let schemaVersion = 1
    private var version = schemaVersion
    private var files: [String: LogFile] = [:]
    /// `store`, kept between passes so a pass only inserts its new records; rebuilt when records are dropped.
    private var merged: RecordStore?
    private enum CodingKeys: CodingKey { case version, files }

    private struct LogFile: Codable, Sendable {
        var device: Int32, inode: UInt64, size: Int, offset: Int
        /// Deduped within the file. Kept per file so a rewritten file can drop exactly its own records.
        var records: [UsageRecord] = []
    }

    public init() {}

    /// The cache at `url`; empty (a full rescan) if it is missing, unreadable or from another schema version.
    public static func load(from url: URL) -> UsageCache {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(UsageCache.self, from: data),
              cache.version == schemaVersion
        else { return UsageCache() }
        return cache
    }

    public func save(to url: URL) throws {
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// Records deduped across all files, deleted ones included.
    public var store: RecordStore { merged ?? mergeFiles() }

    private func mergeFiles() -> RecordStore {
        var store = RecordStore()
        for file in files.values {
            for record in file.records { store.insert(record) }
        }
        return store
    }

    /// Reads what was appended to each log since the last pass, up to its last newline (a half-written line waits),
    /// and prunes records older than today − 62 days. A log whose inode changed or that shrank below its offset is
    /// reparsed from 0; a deleted log keeps its records. `dirs` limits the pass to the `.jsonl` files directly inside
    /// those directories (what FSEvents reports); nil walks `<claudeHome>/projects`, newest mtime first.
    /// `progress(done, total, partial)` reports the files handled so far and the records found so far, at most every
    /// 250 ms and after the last file. Returns the number of bytes read.
    @discardableResult
    public mutating func update(
        claudeHome: URL, dirs: [String]? = nil, now: Date, calendar: Calendar,
        progress: ((_ done: Int, _ total: Int, _ partial: RecordStore) -> Void)? = nil
    ) -> Int {
        let cutoff = calendar.date(byAdding: .day, value: -62, to: calendar.startOfDay(for: now))!
        let paths: [String]
        if let dirs {
            paths = dirs.flatMap { dir in
                ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).map { (dir as NSString).appendingPathComponent($0) }
            }
        } else {
            // FSEvents reports real paths; resolve symlinks so both kinds of pass key a file the same way.
            let root = claudeHome.appending(path: "projects").resolvingSymlinksInPath().path
            paths = (FileManager.default.subpaths(atPath: root) ?? []).map { (root as NSString).appendingPathComponent($0) }
        }
        let logs = paths.filter { $0.hasSuffix(".jsonl") }
            .compactMap { path -> (path: String, info: stat)? in
                var info = stat()
                return stat(path, &info) == 0 && info.st_mtimespec.tv_sec >= Int(cutoff.timeIntervalSince1970) ? (path, info) : nil
            }
            .sorted { $0.info.st_mtimespec.tv_sec > $1.info.st_mtimespec.tv_sec }

        var bytesRead = 0
        var dropped = false
        // New records go straight into `merged`, so `progress` sees cached records plus what this pass found.
        if merged == nil { merged = mergeFiles() }
        var lastProgress = ContinuousClock.now
        for (index, (path, info)) in logs.enumerated() {
            let size = Int(info.st_size)
            var file = files[path] ?? LogFile(device: info.st_dev, inode: info.st_ino, size: 0, offset: 0)
            if file.device != info.st_dev || file.inode != info.st_ino || size < file.offset {
                dropped = dropped || !file.records.isEmpty
                file = LogFile(device: info.st_dev, inode: info.st_ino, size: 0, offset: 0)
            }
            if size != file.size, let handle = FileHandle(forReadingAtPath: path) {
                // Without the pool every file's bytes stay alive (autoreleased) until the whole pass ends.
                let appended = autoreleasepool {
                    (try? handle.seek(toOffset: UInt64(file.offset))).flatMap { try? handle.readToEnd() } ?? Data()
                }
                try? handle.close()
                bytesRead += appended.count
                if let lastNewline = appended.lastIndex(of: 0x0A) {
                    let parsed = parseUsageLines(appended[...lastNewline])
                    for record in parsed { merged!.insert(record) }
                    var deduped = RecordStore()
                    for record in file.records + parsed { deduped.insert(record) }
                    file.records = Array(deduped.records)
                    file.offset += lastNewline + 1
                }
                file.size = size
            }
            files[path] = file
            if let progress, index + 1 == logs.count || lastProgress.duration(to: .now) > .milliseconds(250) {
                progress(index + 1, logs.count, merged!)
                lastProgress = .now
            }
        }

        for path in files.keys {
            let count = files[path]!.records.count
            files[path]!.records.removeAll { $0.timestamp < cutoff }
            dropped = dropped || files[path]!.records.count != count
        }
        if dropped { merged = mergeFiles() }
        if dirs == nil {
            let onDisk = Set(logs.map(\.path))
            files = files.filter { onDisk.contains($0.key) || !$0.value.records.isEmpty }
        }
        return bytesRead
    }
}
