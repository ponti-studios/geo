import Foundation
import SwiftData

@Model
final class Place {
    var legacyPlaceID: Int?
    var name: String
    var url: String?
    var placeType: String?
    var latitude: Double?
    var longitude: Double?
    var formattedAddress: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var country: String?
    var countryCode: String?
    var geocodedAt: Date?
    var createdAt: Date?
    var updatedAt: Date?
    var rawMetadataJSON: String?

    @Relationship(deleteRule: .cascade, inverse: \PlaceReview.place)
    var review: PlaceReview?

    @Relationship(deleteRule: .cascade, inverse: \PlaceGeocodeAttempt.place)
    var attempts: [PlaceGeocodeAttempt] = []

    init(
        legacyPlaceID: Int? = nil,
        name: String,
        url: String? = nil,
        placeType: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        formattedAddress: String? = nil,
        city: String? = nil,
        state: String? = nil,
        postalCode: String? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        geocodedAt: Date? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        rawMetadataJSON: String? = nil,
        review: PlaceReview? = nil,
        attempts: [PlaceGeocodeAttempt] = []
    ) {
        self.legacyPlaceID = legacyPlaceID
        self.name = name
        self.url = url
        self.placeType = placeType
        self.latitude = latitude
        self.longitude = longitude
        self.formattedAddress = formattedAddress
        self.city = city
        self.state = state
        self.postalCode = postalCode
        self.country = country
        self.countryCode = countryCode
        self.geocodedAt = geocodedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.rawMetadataJSON = rawMetadataJSON
        self.review = review
        self.attempts = attempts
    }
}

@Model
final class PlaceReview {
    var status: String
    var reason: String?
    var query: String?
    var updatedAt: Date?
    var decisionAt: Date?
    var decisionSource: String?
    var lastGeocodeStatus: String?
    var lastGeocodeQuery: String?
    var lastGeocodeResultSummary: String?
    var expectedCountry: String?
    var suggestedQueries: String?
    var legacyCandidateMetadataJSON: String?

    var place: Place?

    init(
        status: String = "unknown",
        reason: String? = nil,
        query: String? = nil,
        updatedAt: Date? = nil,
        decisionAt: Date? = nil,
        decisionSource: String? = nil,
        lastGeocodeStatus: String? = nil,
        lastGeocodeQuery: String? = nil,
        lastGeocodeResultSummary: String? = nil,
        expectedCountry: String? = nil,
        suggestedQueries: String? = nil,
        legacyCandidateMetadataJSON: String? = nil,
        place: Place? = nil
    ) {
        self.status = status
        self.reason = reason
        self.query = query
        self.updatedAt = updatedAt
        self.decisionAt = decisionAt
        self.decisionSource = decisionSource
        self.lastGeocodeStatus = lastGeocodeStatus
        self.lastGeocodeQuery = lastGeocodeQuery
        self.lastGeocodeResultSummary = lastGeocodeResultSummary
        self.expectedCountry = expectedCountry
        self.suggestedQueries = suggestedQueries
        self.legacyCandidateMetadataJSON = legacyCandidateMetadataJSON
        self.place = place
    }
}

@Model
final class PlaceGeocodeAttempt {
    var legacyAttemptID: Int?
    var query: String
    var provider: String
    var status: String
    var resultSummary: String?
    var responseJSON: String?
    var createdAt: Date

    var place: Place?

    init(
        legacyAttemptID: Int? = nil,
        query: String,
        provider: String,
        status: String,
        resultSummary: String? = nil,
        responseJSON: String? = nil,
        createdAt: Date = Date(),
        place: Place? = nil
    ) {
        self.legacyAttemptID = legacyAttemptID
        self.query = query
        self.provider = provider
        self.status = status
        self.resultSummary = resultSummary
        self.responseJSON = responseJSON
        self.createdAt = createdAt
        self.place = place
    }
}
