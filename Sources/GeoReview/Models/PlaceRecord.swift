import CoreLocation
import Foundation

struct PlaceRecord: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let placeType: String?
    let url: String?
    let latitude: Double?
    let longitude: Double?
    let formattedAddress: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let countryCode: String?
    let geocodedAt: String?
    let eventCount: Int
    let metadata: String?
    let createdAt: String?
    let updatedAt: String?
    let reviewStatus: String?
    let reviewReason: String?
    let reviewQuery: String?
    let reviewUpdatedAt: String?
    let reviewDecisionAt: String?
    let reviewDecisionSource: String?
    let lastGeocodeStatus: String?
    let lastGeocodeQuery: String?
    let lastGeocodeResultSummary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case placeType = "place_type"
        case url
        case latitude
        case longitude
        case formattedAddress = "formatted_address"
        case city
        case state
        case postalCode = "postal_code"
        case country
        case countryCode = "country_code"
        case geocodedAt = "geocoded_at"
        case eventCount = "event_count"
        case metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case reviewStatus = "review_status"
        case reviewReason = "review_reason"
        case reviewQuery = "review_query"
        case reviewUpdatedAt = "review_updated_at"
        case reviewDecisionAt = "review_decision_at"
        case reviewDecisionSource = "review_decision_source"
        case lastGeocodeStatus = "last_geocode_status"
        case lastGeocodeQuery = "last_geocode_query"
        case lastGeocodeResultSummary = "last_geocode_result_summary"
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var locationLine: String {
        [city, state, country]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: ", ")
    }

    var effectiveReviewQuery: String {
        let trimmed = reviewQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? name : trimmed
    }

    var statusDisplay: String {
        switch reviewStatus {
        case "needs_review": return "Needs review"
        case "ok": return "Resolved"
        case "no_match": return "No match"
        case "not_a_place": return "Not a place"
        case nil, "": return "Unknown"
        default: return reviewStatus!.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
