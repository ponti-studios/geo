import Foundation
import MapKit
import SwiftUI

@MainActor
final class ReviewStore: ObservableObject {
    @Published var dbPath: String
    @Published var places: [PlaceRecord] = []
    @Published var visiblePlaces: [PlaceRecord] = []
    @Published var visibleMapItems: [MapMarkerItem] = []
    @Published var visibleStatsLine = "0 shown"
    @Published var selectedPlaceID: Int?
    @Published var hoveredPlaceID: Int?
    @Published var selectedPlaceDetail: PlaceRecord?
    @Published var selectedAttempts: [PlaceGeocodeAttemptRecord] = []
    @Published var searchText = ""
    @Published var debouncedSearchText = ""
    @Published var reviewFilter: ReviewFilter = .all
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var errorMessage: String?
    @Published var successMessage: String?
    @Published var mapPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 55, longitudeDelta: 80)
        )
    )
    @Published var mapRegionRevision = 0

    private var searchDebounceTask: Task<Void, Never>?

    init(dbPath: String) {
        self.dbPath = dbPath
    }

    var selectedPlace: PlaceRecord? {
        guard let selectedPlaceID else { return nil }
        if let selectedPlaceDetail, selectedPlaceDetail.id == selectedPlaceID {
            return selectedPlaceDetail
        }
        return visiblePlaces.first(where: { $0.id == selectedPlaceID }) ?? places.first(where: { $0.id == selectedPlaceID })
    }

    func loadPlaces() {
        isLoading = true
        errorMessage = nil
        successMessage = nil
        let dbPath = self.dbPath
        GeoReviewLogger.log("Starting loadPlaces()")

        Task {
            do {
                let rows = try await SQLiteCLI.fetchPlaces(dbPath: dbPath)
                await MainActor.run {
                    self.places = rows
                    self.applyDerivedState()
                    self.reconcileSelection()
                    self.isLoading = false
                    if self.selectedPlace == nil {
                        self.recenterMapToAllMappablePlaces()
                    }
                }
                if let selectedPlaceID = await MainActor.run(resultType: Int?.self, body: { self.selectedPlaceID }) {
                    async let detail = SQLiteCLI.fetchPlaceDetail(dbPath: dbPath, placeID: selectedPlaceID)
                    async let attempts = SQLiteCLI.fetchAttempts(dbPath: dbPath, placeID: selectedPlaceID)
                    let (loadedDetail, loadedAttempts) = try await (detail, attempts)
                    await MainActor.run {
                        self.selectedPlaceDetail = loadedDetail
                        self.selectedAttempts = loadedAttempts
                    }
                } else {
                    await MainActor.run {
                        self.selectedPlaceDetail = nil
                        self.selectedAttempts = []
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
                GeoReviewLogger.log("loadPlaces failed: \(error.localizedDescription)")
            }
        }
    }

    func saveReviewQuery(placeID: Int, reviewQuery: String) {
        let trimmed = reviewQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "review query cannot be blank"
            return
        }

        errorMessage = nil
        successMessage = nil
        isSaving = true
        let dbPath = self.dbPath
        GeoReviewLogger.log("Saving review_query for place #\(placeID): \(trimmed)")

        Task {
            do {
                try SQLiteCLI.updateReviewQuery(dbPath: dbPath, placeID: placeID, reviewQuery: trimmed)
                let updatedPlace = try SQLiteCLI.fetchPlaceSummary(dbPath: dbPath, placeID: placeID)
                await MainActor.run {
                    if let updatedPlace {
                        self.upsertPlace(updatedPlace)
                    }
                    self.selectedPlaceID = placeID
                    self.successMessage = "Saved review query"
                    self.isSaving = false
                    self.applyDerivedState()
                    self.reconcileSelection()
                }
                async let detail = SQLiteCLI.fetchPlaceDetail(dbPath: dbPath, placeID: placeID)
                async let attempts = SQLiteCLI.fetchAttempts(dbPath: dbPath, placeID: placeID)
                let (loadedDetail, loadedAttempts) = try await (detail, attempts)
                await MainActor.run {
                    self.selectedPlaceDetail = loadedDetail
                    self.selectedAttempts = loadedAttempts
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSaving = false
                }
            }
        }
    }

    func acceptResult(placeID: Int, query: String, result: GeocodePreviewResult) {
        errorMessage = nil
        successMessage = nil
        isSaving = true
        let dbPath = self.dbPath
        GeoReviewLogger.log("Accepting result for place #\(placeID): \(result.displayTitle)")

        Task {
            do {
                try SQLiteCLI.acceptResult(dbPath: dbPath, placeID: placeID, query: query, result: result)
                let updatedPlace = try SQLiteCLI.fetchPlaceSummary(dbPath: dbPath, placeID: placeID)
                await MainActor.run {
                    if let updatedPlace {
                        self.upsertPlace(updatedPlace)
                    }
                    self.successMessage = "Updated place from Apple Maps"
                    self.isSaving = false
                    self.applyDerivedState()
                    self.selectedPlaceID = nil
                    self.selectedAttempts = []
                    self.selectedPlaceDetail = nil
                    self.reconcileSelection()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSaving = false
                }
            }
        }
    }

    func markNotAPlace(placeID: Int, query: String) {
        errorMessage = nil
        successMessage = nil
        isSaving = true
        let dbPath = self.dbPath
        GeoReviewLogger.log("Marking place #\(placeID) as not_a_place")

        Task {
            do {
                try SQLiteCLI.markNotAPlace(dbPath: dbPath, placeID: placeID, query: query)
                let updatedPlace = try SQLiteCLI.fetchPlaceSummary(dbPath: dbPath, placeID: placeID)
                await MainActor.run {
                    if let updatedPlace {
                        self.upsertPlace(updatedPlace)
                    }
                    self.successMessage = "Marked as not a place"
                    self.isSaving = false
                    self.applyDerivedState()
                    self.selectedPlaceID = nil
                    self.selectedAttempts = []
                    self.selectedPlaceDetail = nil
                    self.reconcileSelection()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSaving = false
                }
            }
        }
    }

    func selectPlace(_ placeID: Int, source: SelectionSource = .sidebar) {
        if selectedPlaceID == placeID {
            clearSelection()
            return
        }
        selectedPlaceID = placeID
        selectedPlaceDetail = nil
        if source == .map, let place = places.first(where: { $0.id == placeID }) {
            recenterMap(on: place)
        }
        loadSelectedData(for: placeID)
    }

    func clearSelection() {
        selectedPlaceID = nil
        hoveredPlaceID = nil
        selectedPlaceDetail = nil
        selectedAttempts = []
    }

    func recenterMap(on place: PlaceRecord) {
        guard let coordinate = place.coordinate else { return }
        mapPosition = .region(
            MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
        )
        mapRegionRevision += 1
    }

    func recenterMapToFilteredPlaces() {
        let coords = visiblePlaces.compactMap(\.coordinate)
        guard !coords.isEmpty else { return }
        if coords.count == 1 {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coords[0],
                    span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                )
            )
            mapRegionRevision += 1
            return
        }

        let latitudes = coords.map(\.latitude)
        let longitudes = coords.map(\.longitude)
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.25, 0.2),
            longitudeDelta: max((maxLon - minLon) * 1.25, 0.2)
        )
        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        mapRegionRevision += 1
    }

    func scheduleSearchUpdate() {
        searchDebounceTask?.cancel()
        let latest = searchText
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.debouncedSearchText = latest
                self.applyDerivedState()
                self.reconcileSelection()
            }
        }
    }

    func filterDidChange() {
        applyDerivedState()
        reconcileSelection()
    }

    private func applyDerivedState() {
        let filtered = places.filter { place in
            matchesFilter(place) && matchesSearch(place)
        }
        visiblePlaces = filtered
        visibleMapItems = filtered.compactMap { place in
            guard let coordinate = place.coordinate else { return nil }
            return MapMarkerItem(id: place.id, name: place.name, reviewStatus: place.reviewStatus, coordinate: coordinate)
        }
        let reviewCount = places.reduce(into: 0) { partialResult, place in
            if place.reviewStatus == "needs_review" { partialResult += 1 }
        }
        visibleStatsLine = "\(filtered.count) shown · \(places.count) total · \(reviewCount) need review"
    }

    private func reconcileSelection() {
        if let selectedPlaceID, visiblePlaces.contains(where: { $0.id == selectedPlaceID }) {
            return
        }

        selectedPlaceID = nil
        selectedAttempts = []
        selectedPlaceDetail = nil
    }

    func recenterMapToAllMappablePlaces() {
        let coords = visibleMapItems.map(\.coordinate)
        guard !coords.isEmpty else { return }
        if coords.count == 1 {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coords[0],
                    span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
                )
            )
            mapRegionRevision += 1
            return
        }

        let latitudes = coords.map(\.latitude)
        let longitudes = coords.map(\.longitude)
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.25, 0.2),
            longitudeDelta: max((maxLon - minLon) * 1.25, 0.2)
        )
        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        mapRegionRevision += 1
    }

    private func loadSelectedData(for placeID: Int) {
        let dbPath = self.dbPath
        Task {
            do {
                async let detail = SQLiteCLI.fetchPlaceDetail(dbPath: dbPath, placeID: placeID)
                async let attempts = SQLiteCLI.fetchAttempts(dbPath: dbPath, placeID: placeID)
                let (loadedDetail, loadedAttempts) = try await (detail, attempts)
                await MainActor.run {
                    if self.selectedPlaceID == placeID {
                        self.selectedPlaceDetail = loadedDetail
                        self.selectedAttempts = loadedAttempts
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func upsertPlace(_ place: PlaceRecord) {
        if let existingIndex = places.firstIndex(where: { $0.id == place.id }) {
            places[existingIndex] = place
        } else {
            places.append(place)
        }
        sortPlacesInMemory()
    }

    private func sortPlacesInMemory() {
        places.sort { lhs, rhs in
            let lhsRank = reviewStatusRank(lhs.reviewStatus)
            let rhsRank = reviewStatusRank(rhs.reviewStatus)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.eventCount != rhs.eventCount {
                return lhs.eventCount > rhs.eventCount
            }
            return lhs.id < rhs.id
        }
    }

    private func reviewStatusRank(_ status: String?) -> Int {
        switch status {
        case "needs_review": return 0
        case "no_match": return 1
        case "not_a_place": return 2
        case nil: return 3
        default: return 4
        }
    }

    private func matchesFilter(_ place: PlaceRecord) -> Bool {
        switch reviewFilter {
        case .all:
            return true
        case .needsReview:
            return place.reviewStatus == "needs_review"
        case .ok:
            return place.reviewStatus == "ok"
        case .noMatch:
            return place.reviewStatus == "no_match"
        case .notAPlace:
            return place.reviewStatus == "not_a_place"
        case .unknown:
            return place.reviewStatus == nil || place.reviewStatus?.isEmpty == true
        }
    }

    private func matchesSearch(_ place: PlaceRecord) -> Bool {
        let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        return [
            place.name,
            place.reviewQuery ?? "",
            place.reviewReason ?? "",
            place.formattedAddress ?? "",
            place.city ?? "",
            place.state ?? "",
            place.country ?? "",
            place.lastGeocodeResultSummary ?? ""
        ]
        .joined(separator: "\n")
        .localizedCaseInsensitiveContains(query)
    }
}
