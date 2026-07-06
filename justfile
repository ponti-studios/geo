# Install geokit CLI globally
install:
    swift build -c release --product geokit
    cp .build/release/geokit /usr/local/bin/geokit

geokit:
  swift run geokit-review