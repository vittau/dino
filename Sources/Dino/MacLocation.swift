import CoreLocation
import Foundation

/// One location fix on demand. Core Location owns the permission prompt; a
/// denial or timeout lets the caller fall back to its network estimate.
@MainActor
final class MacLocation: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = MacLocation()

    struct Fix {
        let latitude: Double
        let longitude: Double
        let label: String
    }

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var isDenied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }

    func get() async -> Fix? {
        guard !isDenied, continuation == nil else { return nil }
        let location = await withCheckedContinuation { (continuation: CheckedContinuation<CLLocation?, Never>) in
            self.continuation = continuation
            timeoutTask = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 8_000_000_000) }
                catch { return }
                finish(nil)
            }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            default:
                finish(nil)
            }
        }
        guard let location else { return nil }
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        let place = placemarks?.first
        let label = [place?.locality, place?.administrativeArea, place?.country]
            .compactMap { $0?.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return Fix(latitude: location.coordinate.latitude,
                   longitude: location.coordinate.longitude,
                   label: label.isEmpty ? "região detectada pelo Mac" : label)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard continuation != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let recent = locations.last {
            $0.horizontalAccuracy >= 0 && abs($0.timestamp.timeIntervalSinceNow) < 300
        }
        finish(recent)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: location)
    }
}
