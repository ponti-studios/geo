import SwiftUI

func attemptColor(_ status: String) -> Color {
    switch status {
    case "ok": return .green
    case "not_a_place": return .purple
    case "no_match": return .red
    case "review_required": return .orange
    default: return .gray
    }
}

func statusColor(_ reviewStatus: String?) -> Color {
    switch reviewStatus {
    case "needs_review": return Color.orange
    case "ok": return Color.green
    case "no_match": return Color.red
    case "not_a_place": return Color.purple
    default: return Color.gray
    }
}
