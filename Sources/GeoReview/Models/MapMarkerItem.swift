import CoreLocation

struct MapMarkerItem: Identifiable {
    let id: Int
    let name: String
    let reviewStatus: String?
    let coordinate: CLLocationCoordinate2D
}

enum SelectionSource {
    case map
    case sidebar
}
