import Foundation

/// Thread-safe Data accumulator for concurrent pipe reads.
private final class LockedData: @unchecked Sendable {
    private var _value = Data()
    private let lock = NSLock()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func append(_ data: Data) {
        lock.lock()
        _value.append(data)
        lock.unlock()
    }
}

enum SQLiteCLIError: Error, LocalizedError {
    case sqlite3NotFound
    case commandFailed(String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .sqlite3NotFound:
            return "sqlite3 CLI not found at /usr/bin/sqlite3"
        case .commandFailed(let message):
            return message
        case .invalidJSON(let payload):
            return "failed to decode sqlite JSON output: \(payload.prefix(500))"
        }
    }
}

private actor SQLiteTableExistsCache {
  private var values: [String: Bool] = [:]

  func get(_ key: String) -> Bool? {
    values[key]
  }

  func set(_ key: String, value: Bool) {
    values[key] = value
  }
}

enum SQLiteCLI {
  private static let tableExistsCache = SQLiteTableExistsCache()

  static func fetchPlaces(dbPath: String) async throws -> [PlaceRecord] {
    guard try await tableExists(dbPath: dbPath, name: "places") else {
            GeoReviewLogger.log("places table not found; returning empty list")
            return []
        }

        GeoReviewLogger.log("Loading places from SQLite")
        let sql = """
        SELECT
          p.id,
          p.name,
          p.place_type,
          p.url,
          p.latitude,
          p.longitude,
          p.formatted_address,
          p.city,
          p.state,
          p.postal_code,
          p.country,
          p.country_code,
          p.geocoded_at,
          NULL AS metadata,
          p.created_at,
          p.updated_at,
          p.review_status,
          p.review_reason,
          p.review_query,
          p.review_updated_at,
          p.review_decision_at,
          p.review_decision_source,
          p.last_geocode_status,
          p.last_geocode_query,
          NULL AS last_geocode_result_summary,
          (
            SELECT COUNT(*)
            FROM calendar_events ce
            WHERE ce.place_id = p.id
          ) AS event_count
        FROM places p
        ORDER BY
          CASE p.review_status
            WHEN 'needs_review' THEN 0
            WHEN 'no_match' THEN 1
            WHEN 'not_a_place' THEN 2
            WHEN NULL THEN 3
            ELSE 4
          END,
          event_count DESC,
          p.id ASC;
        """

        let data = try run(arguments: ["-json", dbPath, sql])
        guard !data.isEmpty else { return [] }

        do {
            let decoded = try JSONDecoder().decode([PlaceRecord].self, from: data)
            GeoReviewLogger.log("Loaded \(decoded.count) place summaries")
            return decoded
        } catch {
            let payload = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw SQLiteCLIError.invalidJSON(payload)
        }
    }

    static func fetchPlaceDetail(dbPath: String, placeID: Int) throws -> PlaceRecord? {
        let sql = """
        SELECT
          p.id,
          p.name,
          p.place_type,
          p.url,
          p.latitude,
          p.longitude,
          p.formatted_address,
          p.city,
          p.state,
          p.postal_code,
          p.country,
          p.country_code,
          p.geocoded_at,
          p.metadata,
          p.created_at,
          p.updated_at,
          p.review_status,
          p.review_reason,
          p.review_query,
          p.review_updated_at,
          p.review_decision_at,
          p.review_decision_source,
          p.last_geocode_status,
          p.last_geocode_query,
          p.last_geocode_result_summary,
          (
            SELECT COUNT(*)
            FROM calendar_events ce
            WHERE ce.place_id = p.id
          ) AS event_count
        FROM places p
        WHERE p.id = \(placeID)
        LIMIT 1;
        """

        let data = try run(arguments: ["-json", dbPath, sql])
        guard !data.isEmpty else { return nil }

        do {
            return try JSONDecoder().decode([PlaceRecord].self, from: data).first
        } catch {
            let payload = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw SQLiteCLIError.invalidJSON(payload)
        }
    }

    static func fetchPlaceSummary(dbPath: String, placeID: Int) throws -> PlaceRecord? {
        let sql = """
        SELECT
          p.id,
          p.name,
          p.place_type,
          p.url,
          p.latitude,
          p.longitude,
          p.formatted_address,
          p.city,
          p.state,
          p.postal_code,
          p.country,
          p.country_code,
          p.geocoded_at,
          NULL AS metadata,
          p.created_at,
          p.updated_at,
          p.review_status,
          p.review_reason,
          p.review_query,
          p.review_updated_at,
          p.review_decision_at,
          p.review_decision_source,
          p.last_geocode_status,
          p.last_geocode_query,
          NULL AS last_geocode_result_summary,
          (
            SELECT COUNT(*)
            FROM calendar_events ce
            WHERE ce.place_id = p.id
          ) AS event_count
        FROM places p
        WHERE p.id = \(placeID)
        LIMIT 1;
        """

        let data = try run(arguments: ["-json", dbPath, sql])
        guard !data.isEmpty else { return nil }

        do {
            return try JSONDecoder().decode([PlaceRecord].self, from: data).first
        } catch {
            let payload = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw SQLiteCLIError.invalidJSON(payload)
        }
    }

    static func fetchAttempts(dbPath: String, placeID: Int) async throws -> [PlaceGeocodeAttemptRecord] {
      guard try await tableExists(dbPath: dbPath, name: "place_geocode_attempts") else {
            return []
        }

        let sql = """
        SELECT id, place_id, query, provider, status, result_summary, response_json, created_at
        FROM place_geocode_attempts
        WHERE place_id = \(placeID)
        ORDER BY created_at DESC, id DESC;
        """

        let data = try run(arguments: ["-json", dbPath, sql])
        guard !data.isEmpty else { return [] }

        do {
            return try JSONDecoder().decode([PlaceGeocodeAttemptRecord].self, from: data)
        } catch {
            let payload = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw SQLiteCLIError.invalidJSON(payload)
        }
    }

    static func updateReviewQuery(dbPath: String, placeID: Int, reviewQuery: String) throws {
        let escaped = sqlLiteral(reviewQuery)
        let sql = """
        UPDATE places
        SET review_query = '\(escaped)',
            review_updated_at = CURRENT_TIMESTAMP,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = \(placeID);
        """
        _ = try run(arguments: [dbPath, sql])
    }

    static func acceptResult(dbPath: String, placeID: Int, query: String, result: GeocodePreviewResult) throws {
        let queryLiteral = sqlLiteral(query)
        let payloadJSON = try encodeJSONString(result.payload)
        let payloadLiteral = sqlLiteral(payloadJSON)
        let displayTitleLiteral = sqlLiteral(result.displayTitle)
        let nameLiteral = sqlLiteral((result.name?.isEmpty == false ? result.name! : result.displayTitle))
        let formattedAddressLiteral = sqlLiteral(result.formattedAddress ?? result.displayTitle)
        let cityLiteral = sqlLiteral(result.locality ?? "")
        let stateLiteral = sqlLiteral(result.administrativeArea ?? "")
        let postalCodeLiteral = sqlLiteral(result.postalCode ?? "")
        let countryLiteral = sqlLiteral(result.country ?? "")
        let countryCodeLiteral = sqlLiteral((result.countryCode ?? "").lowercased())

        let sql = """
        BEGIN;
        INSERT INTO place_geocode_attempts (
          place_id,
          query,
          provider,
          status,
          result_summary,
          response_json
        ) VALUES (
          \(placeID),
          '\(queryLiteral)',
          'apple_maps',
          'ok',
          '\(displayTitleLiteral)',
          '\(payloadLiteral)'
        );

        UPDATE places
        SET
          name = '\(nameLiteral)',
          latitude = \(result.latitude),
          longitude = \(result.longitude),
          formatted_address = '\(formattedAddressLiteral)',
          city = CASE WHEN '\(cityLiteral)' = '' THEN NULL ELSE '\(cityLiteral)' END,
          state = CASE WHEN '\(stateLiteral)' = '' THEN NULL ELSE '\(stateLiteral)' END,
          postal_code = CASE WHEN '\(postalCodeLiteral)' = '' THEN NULL ELSE '\(postalCodeLiteral)' END,
          country = CASE WHEN '\(countryLiteral)' = '' THEN NULL ELSE '\(countryLiteral)' END,
          country_code = CASE WHEN '\(countryCodeLiteral)' = '' THEN NULL ELSE '\(countryCodeLiteral)' END,
          geocoded_at = CURRENT_TIMESTAMP,
          updated_at = CURRENT_TIMESTAMP,
          review_status = 'ok',
          review_reason = NULL,
          review_query = '\(queryLiteral)',
          review_updated_at = CURRENT_TIMESTAMP,
          review_decision_at = CURRENT_TIMESTAMP,
          review_decision_source = 'manual_ui',
          last_geocode_status = 'ok',
          last_geocode_query = '\(queryLiteral)',
          last_geocode_result_summary = '\(displayTitleLiteral)',
          metadata = json_set(
            CASE
              WHEN metadata IS NOT NULL AND json_valid(metadata) THEN metadata
              ELSE '{}'
            END,
            '$.geocoding.status', 'ok',
            '$.geocoding.provider', 'apple_maps',
            '$.geocoding.search_query', '\(queryLiteral)',
            '$.geocoding.apple_maps.selected_query', '\(queryLiteral)',
            '$.geocoding.apple_maps.selected_at', CURRENT_TIMESTAMP,
            '$.geocoding.apple_maps.selected_result', json('\(payloadLiteral)'),
            '$.review.last_decision', 'accepted',
            '$.review.last_decision_at', CURRENT_TIMESTAMP,
            '$.review.last_decision_source', 'manual_ui'
          )
        WHERE id = \(placeID);
        COMMIT;
        """

        _ = try run(arguments: [dbPath, sql])
    }

    static func markNotAPlace(dbPath: String, placeID: Int, query: String) throws {
        let queryLiteral = sqlLiteral(query)
        let summaryLiteral = sqlLiteral("Marked not a place in manual review UI")
        let sql = """
        BEGIN;
        INSERT INTO place_geocode_attempts (
          place_id,
          query,
          provider,
          status,
          result_summary,
          response_json
        ) VALUES (
          \(placeID),
          '\(queryLiteral)',
          'apple_maps',
          'not_a_place',
          '\(summaryLiteral)',
          NULL
        );

        UPDATE places
        SET
          updated_at = CURRENT_TIMESTAMP,
          review_status = 'not_a_place',
          review_reason = 'manual_not_a_place',
          review_query = '\(queryLiteral)',
          review_updated_at = CURRENT_TIMESTAMP,
          review_decision_at = CURRENT_TIMESTAMP,
          review_decision_source = 'manual_ui',
          last_geocode_status = 'not_a_place',
          last_geocode_query = '\(queryLiteral)',
          last_geocode_result_summary = '\(summaryLiteral)',
          metadata = json_set(
            CASE
              WHEN metadata IS NOT NULL AND json_valid(metadata) THEN metadata
              ELSE '{}'
            END,
            '$.review.last_decision', 'not_a_place',
            '$.review.last_decision_at', CURRENT_TIMESTAMP,
            '$.review.last_decision_source', 'manual_ui'
          )
        WHERE id = \(placeID);
        COMMIT;
        """

        _ = try run(arguments: [dbPath, sql])
    }

    static func tableExists(dbPath: String, name: String) async throws -> Bool {
      let key = "\(dbPath)::\(name)"
      if let cached = await tableExistsCache.get(key) {
        return cached
      }

        let escaped = sqlLiteral(name)
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = '\(escaped)' LIMIT 1;"
        let data = try run(arguments: [dbPath, sql])
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let exists = output == "1"
      await tableExistsCache.set(key, value: exists)
      return exists
    }

    private static func run(arguments: [String]) throws -> Data {
        let sqlite3Path = "/usr/bin/sqlite3"
        guard FileManager.default.fileExists(atPath: sqlite3Path) else {
            throw SQLiteCLIError.sqlite3NotFound
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlite3Path)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Read stdout and stderr concurrently to avoid pipe-buffer deadlock
        // when the query produces >64KB of output.
        let stdoutData = LockedData()
        let stderrData = LockedData()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                stdoutData.append(chunk)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                stderrPipe.fileHandleForReading.readabilityHandler = nil
            } else {
                stderrData.append(chunk)
            }
        }

        try process.run()
        process.waitUntilExit()

        // Clear handlers after process exits
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            let message = String(data: stderrData.value, encoding: .utf8) ?? "sqlite3 exited with status \(process.terminationStatus)"
            throw SQLiteCLIError.commandFailed(message)
        }

        return stdoutData.value
    }

    private static func sqlLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw SQLiteCLIError.commandFailed("failed to encode JSON payload")
        }
        return json
    }
}
