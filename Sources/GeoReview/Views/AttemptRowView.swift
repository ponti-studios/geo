import SwiftUI

struct AttemptRowView: View {
    let attempt: PlaceGeocodeAttemptRecord
    @State private var showResponse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(attempt.query)
                        .font(.body)
                        .lineLimit(2)
                    Text(attempt.createdAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusChip(title: attempt.status.replacingOccurrences(of: "_", with: " "), color: attemptColor(attempt.status))
            }

            if let summary = attempt.resultSummary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let responseJSON = attempt.responseJSON, !responseJSON.isEmpty {
                DisclosureGroup(isExpanded: $showResponse) {
                    CodeBlock(text: responseJSON)
                        .padding(.top, 8)
                } label: {
                    Text("Response JSON")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
