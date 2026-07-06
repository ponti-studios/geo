import SwiftUI

struct GeocodeResultCard: View {
    let result: GeocodePreviewResult
    let isSaving: Bool
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.94, green: 0.93, blue: 0.90), Color(red: 0.87, green: 0.90, blue: 0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 128)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let category = result.pointOfInterestCategory, !category.isEmpty {
                            StatusChip(title: category.replacingOccurrences(of: ".", with: " "), color: .blue)
                        }
                        Spacer()
                        Text(result.name ?? result.displayTitle)
                            .font(.system(size: 26, weight: .semibold, design: .serif))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                    .padding(18)
                }

            VStack(alignment: .leading, spacing: 10) {
                if let formattedAddress = result.formattedAddress, !formattedAddress.isEmpty {
                    Text(formattedAddress)
                        .font(.body)
                }

                let localityLine = [result.locality, result.administrativeArea, result.country]
                    .compactMap { value in
                        guard let value, !value.isEmpty else { return nil }
                        return value
                    }
                    .joined(separator: ", ")
                if !localityLine.isEmpty {
                    Text(localityLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("\(result.latitude), \(result.longitude)")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)

                if let phoneNumber = result.phoneNumber, !phoneNumber.isEmpty {
                    Text(phoneNumber)
                        .font(.caption)
                }
            }

            HStack {
                if let url = result.url, let destination = URL(string: url) {
                    Link("Open Website", destination: destination)
                        .font(.caption)
                }
                Spacer()
                Button("Use This Place", action: onUse)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving)
            }
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 16, x: 0, y: 6)
    }
}
