# Install geokit CLI globally
install-geokit:
    swift build -c release --product geokit
    cp .build/release/geokit /usr/local/bin/geokit
