import Foundation

enum ReviewFilter: String, CaseIterable, Identifiable {
    case needsReview = "needs_review"
    case all = "all"
    case ok = "ok"
    case noMatch = "no_match"
    case notAPlace = "not_a_place"
    case unknown = "unknown"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsReview: return "Needs Review"
        case .all: return "All"
        case .ok: return "Resolved"
        case .noMatch: return "No Match"
        case .notAPlace: return "Not a Place"
        case .unknown: return "Unknown"
        }
    }
}
