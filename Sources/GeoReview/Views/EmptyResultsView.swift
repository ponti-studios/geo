import SwiftUI

struct EmptyResultsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Apple Maps match")
                .font(.system(size: 22, weight: .semibold, design: .serif))
            Text("Try a simpler query, add a city or country, or mark the record as not a place if it represents a call, note, or URL.")
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
