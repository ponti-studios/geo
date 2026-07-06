import XCTest
@testable import Geo

// MARK: - enrich-db Tests

final class EnrichDBTests: XCTestCase {
    var tempDBPath: String!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDBPath = tempDir.appendingPathComponent("test.db").path

        // Create places table
        let createSQL = """
        CREATE TABLE places (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          url TEXT,
          created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
          metadata TEXT,
          place_type TEXT,
          latitude REAL,
          longitude REAL,
          formatted_address TEXT,
          city TEXT,
          state TEXT,
          postal_code TEXT,
          country TEXT,
          country_code TEXT,
          geocoded_at TEXT,
          review_status TEXT,
          review_reason TEXT,
          review_query TEXT,
          review_updated_at TEXT,
          review_decision_at TEXT,
          review_decision_source TEXT,
          last_geocode_status TEXT,
          last_geocode_query TEXT,
          last_geocode_result_summary TEXT
        );
        """
        _ = try! SQLiteRunner.run(dbPath: tempDBPath, sql: createSQL)
    }

    override func tearDown() {
        if let path = tempDBPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        super.tearDown()
    }

    func insertPlace(id: Int? = nil, name: String, city: String? = nil, state: String? = nil, country: String? = nil, lat: Double? = nil, lon: Double? = nil, addr: String? = nil) throws {
        let latVal = lat.map { String($0) } ?? "NULL"
        let lonVal = lon.map { String($0) } ?? "NULL"
        let cityVal = city.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL"
        let stateVal = state.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL"
        let countryVal = country.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL"
        let addrVal = addr.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" } ?? "NULL"

        let sql: String
        if let id {
            sql = "INSERT INTO places (id, name, city, state, country, latitude, longitude, formatted_address) VALUES (\(id), '\(name.replacingOccurrences(of: "'", with: "''"))', \(cityVal), \(stateVal), \(countryVal), \(latVal), \(lonVal), \(addrVal));"
        } else {
            sql = "INSERT INTO places (name, city, state, country, latitude, longitude, formatted_address) VALUES ('\(name.replacingOccurrences(of: "'", with: "''"))', \(cityVal), \(stateVal), \(countryVal), \(latVal), \(lonVal), \(addrVal));"
        }
        _ = try SQLiteRunner.run(dbPath: tempDBPath, sql: sql)
    }

    func queryPlace(id: Int) throws -> [String: String] {
        let data = try SQLiteRunner.run(dbPath: tempDBPath, sql: "SELECT id, name, latitude, longitude, formatted_address, city, state, postal_code, country, country_code, geocoded_at FROM places WHERE id = \(id);")
        let output = String(data: data, encoding: .utf8) ?? ""
        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 11 else { return [:] }

        return [
            "id": parts[0],
            "name": parts[1],
            "latitude": parts[2],
            "longitude": parts[3],
            "formatted_address": parts[4],
            "city": parts[5],
            "state": parts[6],
            "postal_code": parts[7],
            "country": parts[8],
            "country_code": parts[9],
            "geocoded_at": parts[10]
        ]
    }

    // MARK: - parseEnrichDB tests

    func testParseEnrichDBDefaults() throws {
        let command = try CLI.parseEnrichDB(arguments: [])
        switch command {
        case .enrichDB(let options):
            XCTAssertTrue(options.dbPath.hasSuffix("/.hominem/warehouse.db"))
            XCTAssertNil(options.limit)
            XCTAssertFalse(options.dryRun)
            XCTAssertEqual(options.pacingMs, 1100)
        default:
            XCTFail("expected enrichDB command")
        }
    }

    func testParseEnrichDBWithOptions() throws {
        let command = try CLI.parseEnrichDB(arguments: ["--db", "/tmp/test.db", "--limit", "5", "--dry-run", "--pacing", "500"])
        switch command {
        case .enrichDB(let options):
            XCTAssertEqual(options.dbPath, "/tmp/test.db")
            XCTAssertEqual(options.limit, 5)
            XCTAssertTrue(options.dryRun)
            XCTAssertEqual(options.pacingMs, 500)
        default:
            XCTFail("expected enrichDB command")
        }
    }

    func testParseEnrichDBRejectsInvalidLimit() {
        XCTAssertThrowsError(try CLI.parseEnrichDB(arguments: ["--limit", "0"])) { error in
            guard case CLIError.invalidLimit = error else {
                return XCTFail("expected invalidLimit, got \(error)")
            }
        }
    }

    func testParseEnrichDBRejectsUnknownOption() {
        XCTAssertThrowsError(try CLI.parseEnrichDB(arguments: ["--bogus"])) { error in
            guard case CLIError.unknownOption("--bogus") = error else {
                return XCTFail("expected unknownOption, got \(error)")
            }
        }
    }

    // MARK: - readPlacesFromDB tests

    func testReadPlacesFromDBReturnsEmptyWhenNoRowsNeedGeocoding() throws {
        try insertPlace(name: "Already Geocoded", lat: 40.0, lon: -74.0, addr: "123 Main St")

        let rows = try Geo.readPlacesFromDB(dbPath: tempDBPath, limit: nil)
        XCTAssertEqual(rows.count, 0, "Should not return places that already have coordinates and address")
    }

    func testReadPlacesFromDBReturnsPlacesMissingCoordinates() throws {
        try insertPlace(name: "Needs Geocode", city: "New York")
        try insertPlace(name: "Already Done", lat: 40.0, lon: -74.0, addr: "123 Main St")
        try insertPlace(name: "Missing Address", lat: 34.0, lon: -118.0)

        let rows = try Geo.readPlacesFromDB(dbPath: tempDBPath, limit: nil)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].name, "Needs Geocode")
        XCTAssertEqual(rows[1].name, "Missing Address")
    }

    func testReadPlacesFromDBRespectsLimit() throws {
        for i in 1...5 {
            try insertPlace(name: "Place \(i)")
        }

        let rows = try Geo.readPlacesFromDB(dbPath: tempDBPath, limit: 3)
        XCTAssertEqual(rows.count, 3)
    }

    func testReadPlacesFromDBSkipsEmptyNames() throws {
        try insertPlace(name: "")
        try insertPlace(name: "Valid Place")

        let rows = try Geo.readPlacesFromDB(dbPath: tempDBPath, limit: nil)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "Valid Place")
    }

    // MARK: - updatePlaceInDB tests

    func testUpdatePlaceInDBWritesAllFields() throws {
        try insertPlace(id: 1, name: "Test Place")

        try Geo.updatePlaceInDB(
            dbPath: tempDBPath,
            id: 1,
            latitude: 40.7128,
            longitude: -74.0060,
            formattedAddress: "1 Test St, New York, NY 10001, United States",
            city: "New York",
            state: "NY",
            postalCode: "10001",
            country: "United States",
            countryCode: "us"
        )

        let row = try queryPlace(id: 1)
        XCTAssertEqual(Double(row["latitude"] ?? ""), 40.7128)
        XCTAssertEqual(Double(row["longitude"] ?? ""), -74.006)
        XCTAssertEqual(row["city"], "New York")
        XCTAssertEqual(row["state"], "NY")
        XCTAssertEqual(row["postal_code"], "10001")
        XCTAssertEqual(row["country"], "United States")
        XCTAssertEqual(row["country_code"], "us")
        XCTAssertNotNil(row["geocoded_at"])
        XCTAssertTrue(row["formatted_address"]?.contains("1 Test St") ?? false)
    }

    func testUpdatePlaceInDBEscapesSingleQuotes() throws {
        try insertPlace(id: 1, name: "O'Brien's Pub")

        try Geo.updatePlaceInDB(
            dbPath: tempDBPath,
            id: 1,
            latitude: 51.5074,
            longitude: -0.1278,
            formattedAddress: "O'Brien's Pub, London",
            city: "London",
            state: "",
            postalCode: "",
            country: "United Kingdom",
            countryCode: "gb"
        )

        let row = try queryPlace(id: 1)
        XCTAssertEqual(Double(row["latitude"] ?? ""), 51.5074)
        XCTAssertEqual(row["country"], "United Kingdom")
    }
}

final class GeoTests: XCTestCase {
    func testParseGeocodeSupportsLimitAndJoinedQuery() throws {
        let command = try CLI.parseGeocode(arguments: ["--limit", "3", "coffee", "near", "Apple", "Park"])

        switch command {
        case .geocode(let options):
            XCTAssertEqual(options.limit, 3)
            XCTAssertEqual(options.query, "coffee near Apple Park")
        default:
            XCTFail("expected geocode command")
        }
    }
}
