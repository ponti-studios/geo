import MapKit
import SwiftUI

struct PlaceMapView: View {
    @EnvironmentObject private var store: ReviewStore

    var body: some View {
        ZStack {
            if store.visibleMapItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "map")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                    Text("No geocoded places available")
                        .font(.headline)
                    Text("Places will appear here once records have coordinates.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                Map(position: $store.mapPosition) {
                    ForEach(store.visibleMapItems) { item in
                        let isSelected = store.selectedPlaceID == item.id
                        let isHovered = store.hoveredPlaceID == item.id

                        Annotation(item.name, coordinate: item.coordinate, anchor: .center) {
                            Button {
                                store.selectPlace(item.id, source: .map)
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: isSelected ? 22 : (isHovered ? 18 : 14), height: isSelected ? 22 : (isHovered ? 18 : 14))
                                        .shadow(color: .black.opacity(isSelected ? 0.24 : 0.18), radius: isSelected ? 7 : 4, x: 0, y: 2)
                                    Circle()
                                        .fill(statusColor(item.reviewStatus))
                                        .frame(width: isSelected ? 12 : (isHovered ? 10 : 8), height: isSelected ? 12 : (isHovered ? 10 : 8))
                                }
                                .scaleEffect(isSelected ? 1.06 : (isHovered ? 1.03 : 1.0))
                                .animation(.easeOut(duration: 0.14), value: isSelected)
                                .animation(.easeOut(duration: 0.14), value: isHovered)
                            }
                            .buttonStyle(.plain)
                            .onHover { hovering in
                                store.hoveredPlaceID = hovering ? item.id : (store.hoveredPlaceID == item.id ? nil : store.hoveredPlaceID)
                            }
                        }
                    }
                }
            }
        }
    }
}
