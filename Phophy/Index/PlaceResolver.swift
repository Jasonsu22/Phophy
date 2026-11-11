import CoreLocation
import Foundation
import MapKit

/// Turns photo locations into place names ("The University of Hong Kong",
/// "Central, Hong Kong") with Apple's map service, as Photos does. Photos
/// within about a kilometre share one lookup, and lookups are spaced out to
/// stay within Apple's rate limits. Only coordinates are sent, never photos.
actor PlaceResolver {
    static let shared = PlaceResolver()

    private var isRunning = false
    /// Apple allows roughly one lookup a second from an app.
    private let spacing: Duration = .milliseconds(1_200)

    func run() async {
        guard !isRunning, AppSettings.lookUpPlaces else { return }
        isRunning = true
        defer { isRunning = false }

        guard let pending = try? IndexStore.shared.unnamedPlaces() else { return }
        for area in pending {
            guard AppSettings.lookUpPlaces, !Task.isCancelled else { return }
            let location = CLLocation(latitude: area.latitude, longitude: area.longitude)
            guard let request = MKReverseGeocodingRequest(location: location) else { continue }
            do {
                let items = try await request.mapItems
                let item = items.first
                let representations = item?.addressRepresentations
                try? IndexStore.shared.savePlace(
                    key: area.key,
                    name: item?.name ?? "",
                    city: representations?.cityName ?? "",
                    region: representations?.regionName ?? "",
                    context: representations?.cityWithContext ?? representations?.regionName ?? ""
                )
            } catch {
                // Throttled or offline: stop for now; the next run resumes here.
                return
            }
            try? await Task.sleep(for: spacing)
        }
    }
}
