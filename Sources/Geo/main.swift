import Contacts
import CoreLocation
import Foundation
import MapKit

enum ParsedCommand {
    case geocode(GeocodeOptions)
    case geocodeCSV(GeocodeCSVOptions)
}

struct GeocodeOptions {
    let query: String
    let limit: Int
}

struct GeocodeCSVOptions {
    let inputFile: String
    let column: String
    let outputFile: String
    let includeJSON: Bool
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
        case "geocode-csv":
            self.command = try CLI.parseGeocodeCSV(arguments: Array(normalizedArguments.dropFirst()))
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

    static func parseGeocodeCSV(arguments: [String]) throws -> ParsedCommand {
        var inputFile: String?
        var column: String?
        var outputFile: String?
        var includeJSON = false
        var pacingMs: Int?
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                CLI.printUsageAndExit()
            case "-f", "--file":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                inputFile = arguments[index]
            case "-c", "--column":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                column = arguments[index]
            case "-o", "--output":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                outputFile = arguments[index]
            case "--include-json":
                includeJSON = true
            case "--pacing":
                index += 1
                guard index < arguments.count else {
                    throw CLIError.missingValue(argument)
                }
                guard let parsed = Int(arguments[index]), parsed >= 0 else {
                    throw CLIError.invalidPacing
                }
                pacingMs = parsed
            default:
                throw CLIError.unknownOption(argument)
            }
            index += 1
        }

        guard let inputFile else {
            throw CLIError.missingRequired("--file")
        }
        guard let column else {
            throw CLIError.missingRequired("--column")
        }

        let effectivePacing = pacingMs ?? Int(ProcessInfo.processInfo.environment["GEOKIT_CSV_PACING_MS"] ?? "").flatMap { Int($0) }.flatMap { $0 >= 0 ? $0 : nil } ?? 1100

        return .geocodeCSV(
            GeocodeCSVOptions(
                inputFile: inputFile,
                column: column,
                outputFile: outputFile ?? defaultOutputPath(for: inputFile),
                includeJSON: includeJSON,
                pacingMs: effectivePacing
            )
        )
    }

    static func defaultOutputPath(for inputFile: String) -> String {
        let url = URL(fileURLWithPath: inputFile)
        let withoutExtension = url.deletingPathExtension()
        let basePath = withoutExtension.path == url.path ? inputFile : withoutExtension.path
        return basePath + ".geocoded.csv"
    }

    static func printUsageAndExit(status: Int32 = 0) -> Never {
        let stream = status == 0 ? stdout : stderr
        fputs("""
usage:
  geokit [--limit N] <query>
  geokit geocode [--limit N] <query>
  geokit geocode-csv -f <file> -c <column> [-o <output>] [--include-json] [--pacing <ms>]

Examples:
  geokit "Cupertino, CA"
  geokit geocode --limit 3 "coffee near Apple Park"
  geokit geocode-csv -f locations.csv -c city
  geokit geocode-csv -f locations.csv -c city --include-json

Notes:
  - geocode emits pretty-printed JSON with Apple Maps result data.
  - geocode-csv adds lat, lon, city, state, country, country_code columns.
  - --include-json adds an apple_maps_json column containing full result JSON.
  - --pacing controls delay between API calls (default 1100ms).
  - GEOKIT_CSV_PACING_MS environment variable also controls pacing.

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
    case columnNotFound(String)
    case emptyCSV
    case malformedCSV(String)

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
        case .columnNotFound(let column):
            return "column not found: \(column)"
        case .emptyCSV:
            return "input CSV is empty"
        case .malformedCSV(let message):
            return "malformed CSV: \(message)"
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

struct CSVGeocodeData {
    let lat: String
    let lon: String
    let city: String
    let state: String
    let country: String
    let countryCode: String
    let resultJSON: String
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
            case .geocodeCSV(let options):
                try await geocodeCSV(options)
                print("wrote geocoded CSV to \(options.outputFile)")
            }
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }

    static func geocodeCSV(_ options: GeocodeCSVOptions) async throws {
        let content = try String(contentsOfFile: options.inputFile, encoding: .utf8)
        let rows = try parseCSV(content)
        guard let headerRow = rows.first else {
            throw CLIError.emptyCSV
        }

        let columnIndex = headerRow.firstIndex(of: options.column).map { Int($0) }
        guard let columnIndex else {
            throw CLIError.columnNotFound(options.column)
        }

        var outputHeaders = headerRow
        let latIndex = ensureColumn(named: "lat", in: &outputHeaders)
        let lonIndex = ensureColumn(named: "lon", in: &outputHeaders)
        let cityIndex = ensureColumn(named: "city", in: &outputHeaders)
        let stateIndex = ensureColumn(named: "state", in: &outputHeaders)
        let countryIndex = ensureColumn(named: "country", in: &outputHeaders)
        let countryCodeIndex = ensureColumn(named: "country_code", in: &outputHeaders)
        let jsonIndex = options.includeJSON ? ensureColumn(named: "apple_maps_json", in: &outputHeaders) : nil

        var outputRows: [[String]] = [outputHeaders]
        var cache: [String: CSVGeocodeData] = [:]

        for row in rows.dropFirst() {
            var outputRow = row
            if outputRow.count < outputHeaders.count {
                outputRow += Array(repeating: "", count: outputHeaders.count - outputRow.count)
            }

            let query = columnIndex < outputRow.count
                ? outputRow[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""

            let geocodeData: CSVGeocodeData
            if query.isEmpty {
                geocodeData = CSVGeocodeData(
                    lat: "",
                    lon: "",
                    city: "",
                    state: "",
                    country: "",
                    countryCode: "",
                    resultJSON: ""
                )
            } else if let cached = cache[query] {
                geocodeData = cached
            } else {
                try await Task.sleep(for: .milliseconds(options.pacingMs))
                let fresh = try await geocodeCSVRow(query: query)
                cache[query] = fresh
                geocodeData = fresh
            }

            outputRow[latIndex] = geocodeData.lat
            outputRow[lonIndex] = geocodeData.lon
            outputRow[cityIndex] = geocodeData.city
            outputRow[stateIndex] = geocodeData.state
            outputRow[countryIndex] = geocodeData.country
            outputRow[countryCodeIndex] = geocodeData.countryCode
            if let jsonIndex {
                outputRow[jsonIndex] = geocodeData.resultJSON
            }

            outputRows.append(outputRow)
        }

        let outputContent = writeCSV(rows: outputRows)
        try outputContent.write(toFile: options.outputFile, atomically: true, encoding: .utf8)
    }

    static func geocodeCSVRow(query: String) async throws -> CSVGeocodeData {
        let payload = try await search(query: query, limit: 1)
        guard let result = payload.results.first else {
            return CSVGeocodeData(
                lat: "",
                lon: "",
                city: "",
                state: "",
                country: "",
                countryCode: "",
                resultJSON: ""
            )
        }

        return CSVGeocodeData(
            lat: String(result.placemark.coordinate.latitude),
            lon: String(result.placemark.coordinate.longitude),
            city: result.placemark.locality ?? result.placemark.subLocality ?? "",
            state: result.placemark.administrativeArea ?? "",
            country: result.placemark.country ?? "",
            countryCode: result.placemark.isoCountryCode?.lowercased() ?? "",
            resultJSON: try encodeJSONString(result)
        )
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
        let addressRepresentations = item.addressRepresentations
        let formattedAddressLines = addressRepresentations?
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
            country: addressRepresentations?.regionName,
            isoCountryCode: nil,
            administrativeArea: nil,
            subAdministrativeArea: nil,
            locality: addressRepresentations?.cityName,
            subLocality: nil,
            thoroughfare: item.address?.shortAddress,
            subThoroughfare: nil,
            postalCode: nil,
            formattedAddressLines: formattedAddressLines,
            postalAddress: nil
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

    static func ensureColumn(named name: String, in headers: inout [String]) -> Int {
        if let existingIndex = headers.firstIndex(of: name) {
            return existingIndex
        }
        headers.append(name)
        return headers.count - 1
    }

    static func parseCSV(_ content: String) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = content.startIndex

        while index < content.endIndex {
            let character = content[index]

            if inQuotes {
                if character == "\"" {
                    let nextIndex = content.index(after: index)
                    if nextIndex < content.endIndex, content[nextIndex] == "\"" {
                        field.append("\"")
                        index = nextIndex
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                case "\r":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""

                    let nextIndex = content.index(after: index)
                    if nextIndex < content.endIndex, content[nextIndex] == "\n" {
                        index = nextIndex
                    }
                default:
                    field.append(character)
                }
            }

            index = content.index(after: index)
        }

        if inQuotes {
            throw CLIError.malformedCSV("unterminated quoted field")
        }

        if !row.isEmpty || !field.isEmpty {
            row.append(field)
            rows.append(row)
        }

        return rows
    }

    static func writeCSV(rows: [[String]]) -> String {
        rows
            .map { row in row.map(csvEscape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\n") || value.contains("\r") || value.contains("\"") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
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
