import CoreLocation
import SwiftUI

/// Current conditions from Open-Meteo. No API key, no account, no entitlement -
/// which matters because WeatherKit requires a paid team identifier.
@MainActor
@Observable
final class WeatherStore: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherStore()

    struct Snapshot: Equatable {
        var temperature: Double
        var apparent: Double
        var high: Double
        var low: Double
        var code: Int
        var isDay: Bool
        var place: String
        var updated: Date

        var symbolName: String { WeatherStore.symbol(for: code, isDay: isDay) }
        var summary: String { WeatherStore.summary(for: code) }
    }

    private(set) var snapshot: Snapshot?
    private(set) var usesFahrenheit = Locale.current.measurementSystem == .us

    private let locationManager = CLLocationManager()
    private var refreshTimer: Timer?
    private var lastLocation: CLLocation?

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var authorizationStatus: CLAuthorizationStatus { locationManager.authorizationStatus }
    var needsAuthorization: Bool { authorizationStatus == .notDetermined }

    /// Only ever called from an explicit user action: a launch-time permission
    /// prompt for an app that lives in the notch is hostile.
    func requestAccess() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    func start() {
        guard Preferences.shared.weatherEnabled, refreshTimer == nil else { return }
        guard authorizationStatus == .authorized || authorizationStatus == .authorizedAlways else { return }
        locationManager.startUpdatingLocation()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        locationManager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            lastLocation = location
            manager.stopUpdatingLocation()
            refresh()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorized, .authorizedAlways: manager.startUpdatingLocation()
            default: break
            }
        }
    }

    func refresh() {
        guard let location = lastLocation else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        let unit = usesFahrenheit ? "fahrenheit" : "celsius"
        let endpoint = "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)" +
            "&current=temperature_2m,apparent_temperature,is_day,weather_code" +
            "&daily=temperature_2m_max,temperature_2m_min&forecast_days=1" +
            "&temperature_unit=\(unit)&timezone=auto"
        guard let url = URL(string: endpoint) else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let current = json["current"] as? [String: Any],
                      let daily = json["daily"] as? [String: Any]
                else { return }

                let place = await Self.placeName(for: location)
                let next = Snapshot(
                    temperature: current["temperature_2m"] as? Double ?? 0,
                    apparent: current["apparent_temperature"] as? Double ?? 0,
                    high: (daily["temperature_2m_max"] as? [Double])?.first ?? 0,
                    low: (daily["temperature_2m_min"] as? [Double])?.first ?? 0,
                    code: current["weather_code"] as? Int ?? 0,
                    isDay: (current["is_day"] as? Int ?? 1) == 1,
                    place: place,
                    updated: .now)
                withAnimation(Motion.content) { snapshot = next }
            } catch {
                // Offline: keep showing the last good reading.
            }
        }
    }

    private static func placeName(for location: CLLocation) async -> String {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.locality ?? placemarks?.first?.name ?? "Nearby"
    }

    nonisolated static func symbol(for code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: "cloud.rain.fill"
        case 71, 73, 75, 77: "cloud.snow.fill"
        case 80, 81, 82: "cloud.heavyrain.fill"
        case 85, 86: "wind.snow"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    nonisolated static func summary(for code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51, 53, 55, 56, 57: "Drizzle"
        case 61, 63, 65, 66, 67: "Rain"
        case 71, 73, 75, 77: "Snow"
        case 80, 81, 82: "Showers"
        case 85, 86: "Snow showers"
        case 95, 96, 99: "Thunderstorms"
        default: "Cloudy"
        }
    }
}
