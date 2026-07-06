import Contacts
import CoreLocation
import Foundation

struct CoordinatePayload: Codable, Hashable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
}

struct PostalAddressPayload: Codable, Hashable {
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

struct PlacemarkPayload: Codable, Hashable {
    let title: String?
    let subtitle: String?
    let coordinate: CoordinatePayload
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

struct MapItemPayload: Codable, Hashable {
    let name: String?
    let displayTitle: String
    let isCurrentLocation: Bool
    let phoneNumber: String?
    let url: String?
    let pointOfInterestCategory: String?
    let placemark: PlacemarkPayload
}

struct GeocodePreviewResponse: Hashable {
    let query: String
    let requestedLimit: Int
    let resultCount: Int
    let results: [GeocodePreviewResult]
}

struct GeocodePreviewResult: Identifiable, Hashable {
    let id = UUID()
    let payload: MapItemPayload

    var name: String? { payload.name }
    var displayTitle: String { payload.displayTitle }
    var phoneNumber: String? { payload.phoneNumber }
    var url: String? { payload.url }
    var pointOfInterestCategory: String? { payload.pointOfInterestCategory }
    var locality: String? { payload.placemark.locality ?? payload.placemark.subLocality }
    var administrativeArea: String? { payload.placemark.administrativeArea }
    var country: String? { payload.placemark.country }
    var formattedAddress: String? { payload.placemark.formattedAddressLines?.joined(separator: ", ") }
    var latitude: Double { payload.placemark.coordinate.latitude }
    var longitude: Double { payload.placemark.coordinate.longitude }
    var postalCode: String? { payload.placemark.postalCode ?? payload.placemark.postalAddress?.postalCode }
    var countryCode: String? { payload.placemark.isoCountryCode ?? payload.placemark.postalAddress?.isoCountryCode }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
