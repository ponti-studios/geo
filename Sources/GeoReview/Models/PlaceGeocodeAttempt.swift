import Foundation

struct PlaceGeocodeAttemptRecord: Identifiable, Codable, Hashable {
    let id: Int
    let placeId: Int
    let query: String
    let provider: String
    let status: String
    let resultSummary: String?
    let responseJSON: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case placeId = "place_id"
        case query
        case provider
        case status
        case resultSummary = "result_summary"
        case responseJSON = "response_json"
        case createdAt = "created_at"
    }
}
