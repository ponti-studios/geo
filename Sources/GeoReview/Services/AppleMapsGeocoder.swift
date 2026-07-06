import MapKit

enum AppleMapsGeocoder {
    static func preview(query: String, limit: Int = 5) async throws -> GeocodePreviewResponse {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        let response = try await MKLocalSearch(request: request).start()
        let results = Array(response.mapItems.prefix(limit)).map(mapItemToPreview)

        return GeocodePreviewResponse(
            query: trimmed,
            requestedLimit: limit,
            resultCount: results.count,
            results: results
        )
    }

    static func mapItemToPreview(_ item: MKMapItem) -> GeocodePreviewResult {
        GeocodePreviewResult(payload: mapItemPayload(from: item))
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
            return ([name] + addressParts).joined(separator: ", ")
        }

        if !addressParts.isEmpty {
            return addressParts.joined(separator: ", ")
        }

        return "Unnamed location"
    }
}
