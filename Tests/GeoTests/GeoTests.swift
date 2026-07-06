import XCTest
@testable import Geo

final class GeoTests: XCTestCase {
    func testDefaultOutputPathAppendsGeocodedSuffix() {
        XCTAssertEqual(CLI.defaultOutputPath(for: "/tmp/input.csv"), "/tmp/input.geocoded.csv")
        XCTAssertEqual(CLI.defaultOutputPath(for: "/tmp/locations"), "/tmp/locations.geocoded.csv")
    }

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

    func testParseGeocodeCSVUsesDefaultOutputAndIncludeJSON() throws {
        let command = try CLI.parseGeocodeCSV(arguments: ["-f", "/tmp/input.csv", "-c", "Name", "--include-json"])

        switch command {
        case .geocodeCSV(let options):
            XCTAssertEqual(options.inputFile, "/tmp/input.csv")
            XCTAssertEqual(options.column, "Name")
            XCTAssertEqual(options.outputFile, "/tmp/input.geocoded.csv")
            XCTAssertTrue(options.includeJSON)
        default:
            XCTFail("expected geocode-csv command")
        }
    }

    func testParseGeocodeCSVRejectsUnknownOption() {
        XCTAssertThrowsError(try CLI.parseGeocodeCSV(arguments: ["--bogus"])) { error in
            guard case CLIError.unknownOption("--bogus") = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testEnsureColumnReusesExistingColumn() {
        var headers = ["name", "lat", "lon"]

        let latIndex = Geo.ensureColumn(named: "lat", in: &headers)
        let cityIndex = Geo.ensureColumn(named: "city", in: &headers)

        XCTAssertEqual(latIndex, 1)
        XCTAssertEqual(cityIndex, 3)
        XCTAssertEqual(headers, ["name", "lat", "lon", "city"])
    }

    func testParseCSVHandlesQuotedFieldsEscapedQuotesAndNewlines() throws {
        let csv = "Name,Notes\n\"Apple Park\",\"Line 1\nLine 2\"\n\"Cafe \"\"Central\"\"\",\"Has, comma\"\n"
        let rows = try Geo.parseCSV(csv)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["Name", "Notes"])
        XCTAssertEqual(rows[1], ["Apple Park", "Line 1\nLine 2"])
        XCTAssertEqual(rows[2], ["Cafe \"Central\"", "Has, comma"])
    }

    func testParseCSVRejectsUnterminatedQuotedField() {
        XCTAssertThrowsError(try Geo.parseCSV("Name\n\"unfinished")) { error in
            guard case CLIError.malformedCSV(let message) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(message.contains("unterminated quoted field"))
        }
    }

    func testWriteCSVEscapesSpecialCharacters() {
        let output = Geo.writeCSV(rows: [
            ["Name", "Notes"],
            ["Cafe \"Central\"", "Has, comma"],
            ["Apple Park", "Line 1\nLine 2"]
        ])

        XCTAssertEqual(
            output,
            "Name,Notes\n\"Cafe \"\"Central\"\"\",\"Has, comma\"\nApple Park,\"Line 1\nLine 2\"\n"
        )
    }

    func testGeocodeCSVAddsColumnsAndPreservesExistingDataForBlankQueries() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let inputURL = tempDirectory.appendingPathComponent("input.csv")
        let outputURL = tempDirectory.appendingPathComponent("output.csv")

        try "Name,Notes\n,Test place\n\"   \",Still blank\n".write(to: inputURL, atomically: true, encoding: .utf8)

        try await Geo.geocodeCSV(
            GeocodeCSVOptions(
                inputFile: inputURL.path,
                column: "Name",
                outputFile: outputURL.path,
                includeJSON: true,
                pacingMs: 0
            )
        )

        let output = try String(contentsOf: outputURL, encoding: .utf8)
        let rows = try Geo.parseCSV(output)

        XCTAssertEqual(rows[0], ["Name", "Notes", "lat", "lon", "city", "state", "country", "country_code", "apple_maps_json"])
        XCTAssertEqual(rows[1], ["", "Test place", "", "", "", "", "", "", ""])
        XCTAssertEqual(rows[2], ["   ", "Still blank", "", "", "", "", "", "", ""])
    }
}
