import Foundation

struct ReviewAppConfig {
    let dbPath: String

    static func load() throws -> ReviewAppConfig {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let hominemDirectory = homeDirectory.appendingPathComponent(".hominem", isDirectory: true)
        let dbURL = hominemDirectory.appendingPathComponent("warehouse.db", isDirectory: false)

        try FileManager.default.createDirectory(at: hominemDirectory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: dbURL.path) {
            FileManager.default.createFile(atPath: dbURL.path, contents: nil)
        }

        GeoReviewLogger.log("Using database at \(dbURL.path)")
        return ReviewAppConfig(dbPath: dbURL.path)
    }
}

enum GeoReviewLogger {
    static var logFileURL: URL {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let hominemDirectory = homeDirectory.appendingPathComponent(".hominem", isDirectory: true)
        try? FileManager.default.createDirectory(at: hominemDirectory, withIntermediateDirectories: true)
        return hominemDirectory.appendingPathComponent("geokit-review.log", isDirectory: false)
    }

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        fputs(line, stderr)

        let data = Data(line.utf8)
        if FileManager.default.fileExists(atPath: logFileURL.path), let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }
}
