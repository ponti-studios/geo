import SwiftUI

struct PlaceDetailView: View {
    @EnvironmentObject private var store: ReviewStore
    let place: PlaceRecord

    @State private var editedQuery = ""
    @State private var previewResponse: GeocodePreviewResponse?
    @State private var isGeocoding = false
    @State private var geocodeError: String?
    @State private var showMetadata = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                querySection
                resultsSection
                attemptsSection
                debugSection
            }
            .padding(28)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear(perform: resetState)
        .onChange(of: place.id) { resetState() }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    StatusChip(title: place.statusDisplay, color: statusColor(place.reviewStatus))
                    Text(place.name)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .lineSpacing(2)
                    Text([place.locationLine.isEmpty ? nil : place.locationLine, place.formattedAddress]
                        .compactMap { value in
                            guard let value, !value.isEmpty else { return nil }
                            return value
                        }
                        .joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 24)
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 10) {
                        Button {
                            store.recenterMap(on: place)
                        } label: {
                            Image(systemName: "scope")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.clearSelection()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("place #\(place.id)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if place.eventCount > 0 {
                        Text("\(place.eventCount) event\(place.eventCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 16)], alignment: .leading, spacing: 14) {
                FactBlock(label: "Review reason", value: place.reviewReason ?? "—")
                FactBlock(label: "Last geocode", value: place.lastGeocodeStatus ?? "—")
                FactBlock(label: "Coordinates", value: place.coordinate.map { "\($0.latitude), \($0.longitude)" } ?? "—")
                FactBlock(label: "Decision source", value: place.reviewDecisionSource ?? "—")
            }
        }
    }

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review Query")
                .font(.system(size: 20, weight: .semibold, design: .serif))

            TextEditor(text: $editedQuery)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .frame(minHeight: 92)
                .padding(8)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 10) {
                Button("Reset") { resetState() }
                    .buttonStyle(.bordered)
                Button("Use Current Name") { editedQuery = place.name }
                    .buttonStyle(.bordered)
                Button("Save Query") {
                    store.saveReviewQuery(placeID: place.id, reviewQuery: editedQuery)
                }
                .buttonStyle(.bordered)
                .disabled(store.isSaving)
                Button(isGeocoding ? "Geocoding…" : "Retry Geocode") {
                    retryGeocode()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGeocoding || editedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSaving)
                Spacer()
                Button("Not a Place") {
                    store.markNotAPlace(placeID: place.id, query: editedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? place.effectiveReviewQuery : editedQuery)
                }
                .buttonStyle(.bordered)
                .disabled(store.isSaving)
            }
        }
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Candidate Matches")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                    Text("A quiet editorial layout for choosing the correct Apple Maps place.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isGeocoding {
                    ProgressView()
                }
            }

            if let geocodeError, !geocodeError.isEmpty {
                Text(geocodeError)
                    .foregroundStyle(.red)
            }

            if let previewResponse {
                Text("Query: \(previewResponse.query) · \(previewResponse.resultCount) result\(previewResponse.resultCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if previewResponse.results.isEmpty {
                    EmptyResultsView()
                } else {
                    VStack(spacing: 18) {
                        ForEach(previewResponse.results) { result in
                            GeocodeResultCard(
                                result: result,
                                isSaving: store.isSaving,
                                onUse: {
                                    store.acceptResult(placeID: place.id, query: editedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? place.effectiveReviewQuery : editedQuery, result: result)
                                }
                            )
                        }
                    }
                }
            } else {
                Text(place.lastGeocodeResultSummary ?? "Run Retry Geocode to preview Apple Maps matches for this place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var attemptsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Review History")
                    .font(.system(size: 20, weight: .semibold, design: .serif))
                Spacer()
                Text("\(store.selectedAttempts.count) attempt\(store.selectedAttempts.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.selectedAttempts.isEmpty {
                Text("No attempts recorded yet for this place.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 12) {
                    ForEach(store.selectedAttempts.prefix(8)) { attempt in
                        AttemptRowView(attempt: attempt)
                    }
                }
            }
        }
    }

    private var debugSection: some View {
        DisclosureGroup(isExpanded: $showMetadata) {
            VStack(alignment: .leading, spacing: 14) {
                if let summary = place.lastGeocodeResultSummary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Last geocode result")
                            .font(.headline)
                        CodeBlock(text: summary)
                    }
                }
                if let metadata = place.metadata, !metadata.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Metadata")
                            .font(.headline)
                        CodeBlock(text: metadata)
                    }
                }
            }
            .padding(.top, 12)
        } label: {
            Text("Technical detail")
                .font(.headline)
        }
    }

    private func resetState() {
        editedQuery = place.effectiveReviewQuery
        previewResponse = nil
        geocodeError = nil
        isGeocoding = false
    }

    private func retryGeocode() {
        let query = editedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            geocodeError = "review query cannot be blank"
            return
        }

        isGeocoding = true
        geocodeError = nil
        previewResponse = nil
        GeoReviewLogger.log("Retry geocode for place #\(place.id): \(query)")

        Task {
            do {
                let response = try await AppleMapsGeocoder.preview(query: query, limit: 5)
                await MainActor.run {
                    previewResponse = response
                    isGeocoding = false
                }
                GeoReviewLogger.log("Geocode returned \(response.resultCount) result(s) for place #\(place.id)")
            } catch {
                await MainActor.run {
                    geocodeError = error.localizedDescription
                    isGeocoding = false
                }
                GeoReviewLogger.log("Geocode failed for place #\(place.id): \(error.localizedDescription)")
            }
        }
    }
}
