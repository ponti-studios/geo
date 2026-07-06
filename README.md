# geokit

Canonical upstream for the `geokit` CLI and `geokit-review` macOS review app.
`/Users/charlesponti/Developer/toolbox` consumes this repo through an explicit
sync workflow so the standalone geospatial tool can evolve independently.

Swift CLI for Apple Maps geocoding and CSV enrichment using `MapKit`.

## Requirements

- macOS
- Swift 6+

## Install

Preferred distribution is via the Ponti Studios Homebrew tap.

For local development:

```bash
swift run geokit -- --help
```

To install a global binary from this repo:

```bash
just install-geokit
```

## Commands

### `geocode` - Lookup a place name

```bash
geokit geocode [--limit N] <query>
```

You can also omit the subcommand and run:

```bash
geokit <query>
```

**Examples:**

```bash
geokit "Mahopac, New York"
geokit geocode "Paris, France"
geokit geocode "1600 Amphitheatre Parkway, Mountain View, CA"
geokit geocode "Empire State Building"
geokit geocode "Japan"
geokit geocode "90210"
geokit geocode --limit 3 "coffee near Apple Park"
```

**Output:**

`geocode` emits pretty-printed JSON so you can inspect Apple Maps result data, including:

- query metadata
- bounding region
- all returned result payloads
- `MKMapItem` fields like `name`, `phoneNumber`, `url`, `pointOfInterestCategory`
- detailed `MKPlacemark` fields like coordinates, address components, timezone, areas of interest, and postal address data when available

---

### `geokit-review` - Native macOS review UI for `place_review_candidates`

A separate executable target, `geokit-review`, opens a SwiftUI macOS app for browsing and curating places directly from `~/.hominem/db.sqlite`.

```bash
swift run geokit-review
```

`geokit-review` always uses `$HOME/.hominem/db.sqlite` and creates the file if it does not already exist.

Current capabilities:

- reads directly from `places`
- filters by review state (`needs_review`, `ok`, `no_match`, `not_a_place`, `unknown`)
- supports text search across names, queries, and addresses
- shows filtered places on a MapKit map with markers
- displays an editorial place detail view
- lets you edit and save `places.review_query`
- retries Apple Maps geocoding for the selected place
- renders Apple Maps matches as selection cards
- `Use This Place` writes the selected result back to `places`
- accepted matches are logged in `place_geocode_attempts`

This is now the main manual review and curation surface, while the `geokit` CLI remains the automation/batch tool.

---

### `geocode-csv` - Geocode a CSV column

```bash
geokit geocode-csv -f <file> -c <column> [-o <output>] [--include-json]
```

**Options:**

| Option | Description | Default |
|--------|-------------|---------|
| `-f, --file <FILE>` | Input CSV file (required) | - |
| `-c, --column <COLUMN>` | Column to geocode (required) | - |
| `-o, --output <OUTPUT>` | Output CSV file | `<input>.geocoded.csv` |
| `--include-json` | Add an `apple_maps_json` column with the full first result payload | off |

**Examples:**

```bash
geokit geocode-csv -f locations.csv -c city
geokit geocode-csv -f locations.csv -c city -o geocoded_locations.csv
geokit geocode-csv -f /data/addresses.csv -c address -o /output/geocoded.csv
geokit geocode-csv -f stores.csv -c "Store Location"
geokit geocode-csv -f customers.csv -c "Full Address"
geokit geocode-csv -f locations.csv -c city --include-json
```

**Input CSV Format:**

```csv
name,city,state
Store A,"New York, NY",NY
Store B,"Los Angeles, CA",CA
```

**Output CSV adds columns:** `lat,lon,city,state,country,country_code`

Optional: `apple_maps_json`

---

## Build & Run

```bash
# Build
swift build

# Run from source
swift run geokit -- geocode "New York"
swift run geokit-review

# Run binary directly
.build/debug/geokit geocode "New York"
.build/debug/geokit-review

# Install globally
just install-geokit
```

---

## Testing Checklist

### geocode command
- [ ] City lookup (e.g., "Paris, France")
- [ ] Address lookup (e.g., "1600 Amphitheatre Parkway")
- [ ] Landmark lookup (e.g., "Empire State Building")
- [ ] Country lookup (e.g., "Japan")
- [ ] Postal code lookup (e.g., "90210")
- [ ] International locations (non-English characters)
- [ ] Invalid/non-existent locations
- [ ] Multi-result lookup with `--limit`

### geocode-csv command
- [ ] Basic CSV with city column
- [ ] CSV with address column
- [ ] Custom output file path
- [ ] Default output file naming
- [ ] CSV with quoted fields
- [ ] Missing column error
- [ ] Missing file error
- [ ] Large CSV file (100+ rows)
- [ ] `--include-json` output column

---

## API Notes

- **Provider:** Apple Maps via `MKLocalSearch`
- **Platform:** macOS only
- **CSV pacing:** 1.1s delay between uncached lookups
- **Result caching:** duplicate CSV queries are cached within a run

---

## Release

Release assets are published from tags like `geokit-v0.1.0`.

## Downstream Sync

To sync this repo back into `toolbox`:

```bash
cd /Users/charlesponti/Developer/toolbox
just sync-geokit-from-geo
```

---

## Technical Notes

- Built as a Swift Package executable
- Uses `MapKit`, `CoreLocation`, and `Contacts`
- `geocode` emits rich JSON payloads for capability inspection
- `geocode-csv` uses the first Apple Maps result for enrichment
- CSV parsing and writing are implemented in-process for portability within the Swift CLI
