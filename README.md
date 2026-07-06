# geokit

geokit is a Swift package that provides a geocoding CLI for Apple Maps and a native macOS review application for curating place data. It is designed for workflows that need reliable place lookup and manual review of geocoded results.

## What this repository contains

- A CLI executable named `geokit` for geocoding individual queries and enriching SQLite data
- A macOS app executable named `geokit-review` for reviewing and correcting place records in a SQLite database
- A test target covering the core geocoding package behavior

## Requirements

- macOS
- Swift 6.2+
- Xcode Command Line Tools

## Installation

For local development:

```bash
swift build
```

To run the CLI:

```bash
swift run geokit -- --help
```

To install the CLI globally from this repository:

```bash
just install-geokit
```

## CLI usage

### Geocode a place

```bash
geokit "Paris, France"
```

Or explicitly:

```bash
geokit geocode "Paris, France"
geokit geocode --limit 3 "coffee near Apple Park"
```

The command emits pretty-printed JSON with Apple Maps result data, including:

- query metadata
- bounding region information
- result payloads
- `MKMapItem` fields such as name, phone number, URL, and category
- `MKPlacemark` details such as coordinates, address components, timezone, and region data

### Enrich a SQLite database

```bash
geokit enrich-db --limit 10
```

This command reads place records from a SQLite database, geocodes rows that are missing location data, and writes the results back. Use `--dry-run` to preview changes without writing them.

## Review app

The `geokit-review` executable launches a SwiftUI macOS app for browsing and curating place records from a SQLite database at `$HOME/.hominem/warehouse.db`.

```bash
swift run geokit-review
```

The app supports:

- browsing place records from the database
- filtering by review state
- text search across names, queries, and addresses
- map-based inspection with markers
- reviewing and editing place metadata
- retrying Apple Maps geocoding for selected rows
- saving accepted matches back to the database

## Development

Build and run from source:

```bash
swift build
swift run geokit -- geocode "New York"
swift run geokit-review
```

Run the test suite:

```bash
swift test
```

## Notes

- The CLI uses Apple Maps via `MKLocalSearch`
- The package targets macOS only
- SQLite enrichment uses a configurable pacing interval between lookups, which defaults to 1100 ms
- The review app is the preferred manual curation surface, while the CLI remains the automation-oriented entry point
