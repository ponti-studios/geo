import Contacts
import CoreLocation
import Foundation
import MapKit

// MARK: - SQLite Runner (Process-based)

enum SQLiteRunner {
    static func run(dbPath: String, sql: String) throws -> Data {
        let sqlite3Path = "/usr/bin/sqlite3"
        guard FileManager.default.fileExists(atPath: sqlite3Path) else {
            throw SQLiteRunnerError.sqlite3NotFound
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlite3Path)
        process.arguments = ["-separator", "|", dbPath, sql]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

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

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            let message = String(data: stderrData.value, encoding: .utf8) ?? "sqlite3 exited with status \(process.terminationStatus)"
            throw SQLiteRunnerError.commandFailed(message)
        }

        return stdoutData.value
    }
}

enum SQLiteRunnerError: Error, LocalizedError {
    case sqlite3NotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .sqlite3NotFound: return "sqlite3 CLI not found at /usr/bin/sqlite3"
        case .commandFailed(let msg): return msg
        }
    }
}

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

// MARK: - CNPostalAddress Helpers

extension CNPostalAddress {
    var formattedAddressLines: [String] {
        var lines: [String] = []
        if !street.isEmpty { lines.append(street) }
        let cityStatePostal = [city, state, postalCode].filter { !$0.isEmpty }.joined(separator: ", ")
        if !cityStatePostal.isEmpty { lines.append(cityStatePostal) }
        if !country.isEmpty { lines.append(country) }
        return lines
    }
}

enum ParsedCommand {
    case geocode(GeocodeOptions)
    case enrichDB(EnrichDBOptions)
}

struct GeocodeOptions {
    let query: String
    let limit: Int
}

struct EnrichDBOptions {
    let dbPath: String
    let limit: Int?
    let dryRun: Bool
    let pacingMs: Int
}

struct CLI {
    let command: ParsedCommand

    init(arguments: [String]) throws {
        let normalizedArguments = arguments.first == "--" ? Array(arguments.dropFirst()) : arguments

        guard !normalizedArguments.isEmpty else {
            CLI.printUsageAndExit(status: 1)
        }

        switch normalizedArguments[0] {
        case "--help", "-h", "help":
            CLI.printUsageAndExit()
        case "geocode":
            self.command = try CLI.parseGeocode(arguments: Array(normalizedArguments.dropFirst()))
        case "enrich-db":
            self.command = try CLI.parseEnrichDB(arguments: Array(normalizedArguments.dropFirst()))
        default:
            self.command = try CLI.parseGeocode(arguments: normalizedArguments)
        }
    }

    static func parseGeocode(arguments: [String]) throws -> ParsedCommand {
        var limit = 1
        var parts: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                index += 1
                continue
            } else if argument == "--help" || argument == "-h" {
                CLI.printUsageAndExit()
            } else if argument == "--limit" || argument == "-l" {
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue("--limit")
                }
                guard let parsed = Int(arguments[index]), parsed > 0 else {
                    throw CLIError.invalidLimit
                }
                limit = parsed
            } else if argument.hasPrefix("-") {
                throw CLIError.unknownOption(argument)
            } else {
                parts.append(argument)
            }
            index += 1
        }

        let query = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            CLI.printUsageAndExit(status: 1)
        }

        return .geocode(GeocodeOptions(query: query, limit: limit))
    }

    static func parseEnrichDB(arguments: [String]) throws -> ParsedCommand {
        var dbPath = NSHomeDirectory() + "/.hominem/warehouse.db"
        var limit: Int?
        var dryRun = false
        var pacingMs: Int?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                CLI.printUsageAndExit()
            case "--db":
                index += 1
                guard index < arguments.count else { throw CLIError.missingValue(argument) }
                dbPath = arguments[index]
            case "--limit":
                index += 1
                guard index < arguments.count else { throw CLIError.missingValue(argument) }
                guard let parsed = Int(arguments[index]), parsed > 0 else { throw CLIError.invalidLimit }
                limit = parsed
            case "--dry-run":
                dryRun = true
            case "--pacing":
                index += 1
                guard index < arguments.count else { throw CLIError.missingValue(argument) }
                guard let parsed = Int(arguments[index]), parsed >= 0 else { throw CLIError.invalidPacing }
                pacingMs = parsed
            default:
                throw CLIError.unknownOption(argument)
            }
            index += 1
        }

        let effectivePacing = pacingMs ?? Int(ProcessInfo.processInfo.environment["GEOKIT_CSV_PACING_MS"] ?? "").flatMap { Int($0) }.flatMap { $0 >= 0 ? $0 : nil } ?? 1100

        return .enrichDB(EnrichDBOptions(dbPath: dbPath, limit: limit, dryRun: dryRun, pacingMs: effectivePacing))
    }

    static func printUsageAndExit(status: Int32 = 0) -> Never {
        let stream = status == 0 ? stdout : stderr
        fputs("""
usage:
  geokit [--limit N] <query>
  geokit geocode [--limit N] <query>
  geokit enrich-db [--db <path>] [--limit N] [--dry-run] [--pacing <ms>]

Examples:
  geokit "Cupertino, CA"
  geokit geocode --limit 3 "coffee near Apple Park"
  geokit enrich-db --limit 10
  geokit enrich-db --dry-run

Notes:
  - geocode emits pretty-printed JSON with Apple Maps result data.
  - enrich-db geocodes places in warehouse.db that are missing coordinates
    or formatted_address and writes the results back. Use --dry-run to preview.
  - --pacing controls delay between API calls (default 1100ms).

""", stream)
        exit(status)
    }
}

enum CLIError: Error, CustomStringConvertible {
    case invalidLimit
    case invalidPacing
    case missingValue(String)
    case unknownOption(String)
    case missingRequired(String)

    var description: String {
        switch self {
        case .invalidLimit:
            return "--limit must be a positive integer"
        case .invalidPacing:
            return "--pacing must be a non-negative integer (milliseconds)"
        case .missingValue(let option):
            return "missing value for \(option)"
        case .unknownOption(let option):
            return "unknown option: \(option)"
        case .missingRequired(let option):
            return "missing required option: \(option)"
        }
    }
}

struct SearchResponsePayload: Codable {
    let query: String
    let requestedLimit: Int
    let resultCount: Int
    let boundingRegion: BoundingRegionPayload
    let results: [MapItemPayload]
}

struct MapItemPayload: Codable {
    let name: String?
    let displayTitle: String
    let isCurrentLocation: Bool
    let phoneNumber: String?
    let url: String?
    let pointOfInterestCategory: String?
    let placemark: PlacemarkPayload
}

struct PlacemarkPayload: Codable {
    let title: String?
    let subtitle: String?
    let coordinate: CoordinatePayload
    let location: LocationPayload?
    let timeZoneIdentifier: String?
    let region: RegionPayload?
    let areasOfInterest: [String]?
    let inlandWater: String?
    let ocean: String?
    let name: String?
    let country: String?
    let isoCountryCode: String?
    let administrativeArea: String?
    let subAdministrativeArea: String?
    let locality: String?
    let subLocality: String?
    let thoroughfare: String?
    let subThoroughfare: String?
    let postalCode: String?
    let formattedAddressLines: [String]?
    let postalAddress: PostalAddressPayload?
}

struct CoordinatePayload: Codable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct LocationPayload: Codable {
    let coordinate: CoordinatePayload
    let altitude: Double
    let horizontalAccuracy: Double
    let verticalAccuracy: Double
    let timestamp: String

    init(_ location: CLLocation) {
        self.coordinate = CoordinatePayload(location.coordinate)
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.verticalAccuracy = location.verticalAccuracy
        self.timestamp = ISO8601DateFormatter().string(from: location.timestamp)
    }
}

struct BoundingRegionPayload: Codable {
    let center: CoordinatePayload
    let span: SpanPayload

    init(_ region: MKCoordinateRegion) {
        self.center = CoordinatePayload(region.center)
        self.span = SpanPayload(region.span)
    }
}

struct SpanPayload: Codable {
    let latitudeDelta: Double
    let longitudeDelta: Double

    init(_ span: MKCoordinateSpan) {
        self.latitudeDelta = span.latitudeDelta
        self.longitudeDelta = span.longitudeDelta
    }
}

struct RegionPayload: Codable {
    let type: String
    let identifier: String
    let center: CoordinatePayload?
    let radius: Double?

    init(_ region: CLRegion) {
        self.type = String(describing: Swift.type(of: region))
        self.identifier = region.identifier

        if let circularRegion = region as? CLCircularRegion {
            self.center = CoordinatePayload(circularRegion.center)
            self.radius = circularRegion.radius
        } else {
            self.center = nil
            self.radius = nil
        }
    }
}

struct PostalAddressPayload: Codable {
    let street: String
    let subLocality: String
    let city: String
    let subAdministrativeArea: String
    let state: String
    let postalCode: String
    let country: String
    let isoCountryCode: String

    init(_ address: CNPostalAddress) {
        self.street = address.street
        self.subLocality = address.subLocality
        self.city = address.city
        self.subAdministrativeArea = address.subAdministrativeArea
        self.state = address.state
        self.postalCode = address.postalCode
        self.country = address.country
        self.isoCountryCode = address.isoCountryCode
    }
}

@main
struct Geo {
    static func main() async {
        do {
            let cli = try CLI(arguments: Array(CommandLine.arguments.dropFirst()))

            switch cli.command {
            case .geocode(let options):
                let payload = try await search(query: options.query, limit: options.limit)
                try printJSON(payload)
            case .enrichDB(let options):
                try await enrichDB(options)
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    // MARK: - enrich-db

    static func enrichDB(_ options: EnrichDBOptions) async throws {
        let rows = try readPlacesFromDB(dbPath: options.dbPath, limit: options.limit)
        guard !rows.isEmpty else {
            print("No places found that need geocoding.")
            return
        }

        print("Found \(rows.count) place(s) to geocode\(options.dryRun ? " (dry-run)" : "").")

        var updated = 0
        var failed = 0

        for (index, row) in rows.enumerated() {
            let query = [row.name, row.city, row.state, row.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

            fputs("  [\(index + 1)/\(rows.count)] \"\(query)\" ... ", stderr)

            do {
                let payload = try await search(query: query, limit: 1)
                guard let result = payload.results.first else {
                    fputs("no results\n", stderr)
                    failed += 1
                    continue
                }

                let pm = result.placemark
                let addr = pm.formattedAddressLines?.joined(separator: ", ") ?? ""

                if options.dryRun {
                    fputs("would update: lat=\(pm.coordinate.latitude) lon=\(pm.coordinate.longitude) addr=\"\(addr)\"\n", stderr)
                    updated += 1
                } else {
                    try updatePlaceInDB(
                        dbPath: options.dbPath,
                        id: row.id,
                        latitude: pm.coordinate.latitude,
                        longitude: pm.coordinate.longitude,
                        formattedAddress: addr,
                        city: pm.locality ?? pm.subLocality ?? "",
                        state: pm.administrativeArea ?? "",
                        postalCode: pm.postalCode ?? "",
                        country: pm.country ?? "",
                        countryCode: pm.isoCountryCode?.lowercased() ?? ""
                    )
                    fputs("updated\n", stderr)
                    updated += 1
                }
            } catch {
                fputs("error: \(error.localizedDescription)\n", stderr)
                failed += 1
            }

            if index < rows.count - 1 {
                try await Task.sleep(for: .milliseconds(options.pacingMs))
            }
        }

        print("\n\(options.dryRun ? "Would update" : "Updated") \(updated) place(s)\(failed > 0 ? ", \(failed) failed" : "").")
    }

    struct PlaceRow {
        let id: Int
        let name: String
        let city: String?
        let state: String?
        let country: String?
    }

    static func readPlacesFromDB(dbPath: String, limit: Int?) throws -> [PlaceRow] {
        let limitClause = limit.map { "LIMIT \($0)" } ?? ""
        let sql = """
        SELECT id, name, city, state, country
        FROM places
        WHERE name IS NOT NULL AND name != ''
          AND (latitude IS NULL OR formatted_address IS NULL OR formatted_address = '')
        ORDER BY id ASC
        \(limitClause);
        """

        let data = try SQLiteRunner.run(dbPath: dbPath, sql: sql)
        guard !data.isEmpty else { return [] }

        let output = String(data: data, encoding: .utf8) ?? ""
        let lines = output.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.compactMap { line in
            let parts = line.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 5, let id = Int(parts[0]) else { return nil }
            return PlaceRow(
                id: id,
                name: String(parts[1]),
                city: parts[2].isEmpty ? nil : String(parts[2]),
                state: parts[3].isEmpty ? nil : String(parts[3]),
                country: parts[4].isEmpty ? nil : String(parts[4])
            )
        }
    }

    static func updatePlaceInDB(
        dbPath: String,
        id: Int,
        latitude: Double,
        longitude: Double,
        formattedAddress: String,
        city: String,
        state: String,
        postalCode: String,
        country: String,
        countryCode: String
    ) throws {
        let escapedAddr = formattedAddress.replacingOccurrences(of: "'", with: "''")
        let escapedCity = city.replacingOccurrences(of: "'", with: "''")
        let escapedState = state.replacingOccurrences(of: "'", with: "''")
        let escapedPostal = postalCode.replacingOccurrences(of: "'", with: "''")
        let escapedCountry = country.replacingOccurrences(of: "'", with: "''")
        let escapedCC = countryCode.replacingOccurrences(of: "'", with: "''")

        let sql = """
        UPDATE places
        SET latitude = \(latitude),
            longitude = \(longitude),
            formatted_address = '\(escapedAddr)',
            city = '\(escapedCity)',
            state = '\(escapedState)',
            postal_code = '\(escapedPostal)',
            country = '\(escapedCountry)',
            country_code = '\(escapedCC)',
            geocoded_at = datetime('now')
        WHERE id = \(id);
        """

        _ = try SQLiteRunner.run(dbPath: dbPath, sql: sql)
    }

    static func search(query: String, limit: Int) async throws -> SearchResponsePayload {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]

        let response = try await MKLocalSearch(request: request).start()
        let results = Array(response.mapItems.prefix(limit)).map { mapItemPayload(from: $0) }

        return SearchResponsePayload(
            query: query,
            requestedLimit: limit,
            resultCount: results.count,
            boundingRegion: BoundingRegionPayload(response.boundingRegion),
            results: results
        )
    }

    static func mapItemPayload(from item: MKMapItem) -> MapItemPayload {
        MapItemPayload(
            name: item.name,
            displayTitle: displayTitle(for: item),
            isCurrentLocation: item.isCurrentLocation,
            phoneNumber: item.phoneNumber,
            url: item.url?.absoluteString,
            pointOfInterestCategory: item.pointOfInterestCategory?.rawValue,
            placemark: placemarkPayload(from: item)
        )
    }

    static func placemarkPayload(from item: MKMapItem) -> PlacemarkPayload {
        let postalAddress = item.placemark.postalAddress
        let addressRepresentations = item.addressRepresentations
        let formattedAddressLines = postalAddress?.formattedAddressLines
            ?? addressRepresentations?
                .fullAddress(includingRegion: true, singleLine: false)?
                .split(whereSeparator: \.isNewline)
                .map(String.init)

        return PlacemarkPayload(
            title: displayTitle(for: item),
            subtitle: item.address?.shortAddress,
            coordinate: CoordinatePayload(item.location.coordinate),
            location: LocationPayload(item.location),
            timeZoneIdentifier: item.timeZone?.identifier,
            region: nil,
            areasOfInterest: nil,
            inlandWater: nil,
            ocean: nil,
            name: item.name,
            country: postalAddress?.country ?? addressRepresentations?.regionName,
            isoCountryCode: postalAddress?.isoCountryCode,
            administrativeArea: postalAddress?.state,
            subAdministrativeArea: postalAddress?.subAdministrativeArea,
            locality: postalAddress?.city ?? addressRepresentations?.cityName,
            subLocality: postalAddress?.subLocality,
            thoroughfare: item.address?.shortAddress,
            subThoroughfare: nil,
            postalCode: postalAddress?.postalCode,
            formattedAddressLines: formattedAddressLines,
            postalAddress: postalAddress.map(PostalAddressPayload.init)
        )
    }

    static func displayTitle(for item: MKMapItem) -> String {
        let rawAddressParts: [String?] = [
            item.address?.shortAddress,
            item.addressRepresentations.flatMap { $0.cityWithContext(.full) }
        ]
        let addressParts = rawAddressParts.compactMap { $0 }.filter { !$0.isEmpty }

        if let name = item.name, !name.isEmpty {
            if addressParts.isEmpty {
                return name
            }
            return ([name] + addressParts).joined(separator: ", ")
        }

        if !addressParts.isEmpty {
            return addressParts.joined(separator: ", ")
        }

        return "Unnamed location"
    }

    static func printJSON<T: Encodable>(_ value: T) throws {
        print(try encodeJSONString(value))
    }

    static func encodeJSONString<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let json = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "geokit", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed to encode JSON output"])
        }
        return json
    }
}
