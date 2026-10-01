import Foundation

/// Optional facts appended to the fixed personality prompt for each request.
/// Weather and IP fallback need no API key. The preferred Mac fix requires
/// Location Services permission, which the system requests on first use.
actor LiveContext {
    static let shared = LiveContext()

    private struct Place {
        let latitude: Double
        let longitude: Double
        let label: String
        let fromMac: Bool
    }

    private struct Location: Decodable {
        let success: Bool
        let city: String?
        let region: String?
        let country: String?
        let latitude: Double?
        let longitude: Double?

        var coordinates: (Double, Double)? {
            guard success, let latitude, let longitude,
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
            return (latitude, longitude)
        }

        var label: String {
            [city, region, country]
                .compactMap { $0?.replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines).prefix(80) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
    }

    private struct Forecast: Decodable {
        struct Current: Decodable {
            let time: String
            let temperature_2m: Double
            let weather_code: Int
        }

        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
            let precipitation_probability_max: [Int?]
        }

        let current: Current
        let daily: Daily

        var summary: String? {
            guard daily.time.count >= 3,
                  daily.weather_code.count >= 3,
                  daily.temperature_2m_max.count >= 3,
                  daily.temperature_2m_min.count >= 3 else { return nil }
            var lines = ["Agora (\(current.time), hora local da previsão): \(current.temperature_2m.formatted(.number.precision(.fractionLength(0...1)))) °C, \(Self.condition(current.weather_code))."]
            for index in 0..<3 {
                var line = "\(daily.time[index]): \(Self.condition(daily.weather_code[index])), mínima \(daily.temperature_2m_min[index].formatted(.number.precision(.fractionLength(0...1)))) °C, máxima \(daily.temperature_2m_max[index].formatted(.number.precision(.fractionLength(0...1)))) °C"
                if index < daily.precipitation_probability_max.count,
                   let chance = daily.precipitation_probability_max[index] {
                    line += ", chance máxima de chuva \(chance)%"
                }
                lines.append(line + ".")
            }
            return lines.joined(separator: "\n")
        }

        private static func condition(_ code: Int) -> String {
            switch code {
            case 0: return "céu limpo"
            case 1, 2: return "parcialmente nublado"
            case 3: return "nublado"
            case 45, 48: return "neblina"
            case 51...57: return "garoa"
            case 61...67: return "chuva"
            case 71...77: return "neve"
            case 80...82: return "pancadas de chuva"
            case 85, 86: return "pancadas de neve"
            case 95...99: return "trovoadas"
            default: return "condição não especificada (código \(code))"
            }
        }
    }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 7
        return URLSession(configuration: config)
    }()
    private var macCache: (value: Place, date: Date)?
    private var ipCache: (value: Place, date: Date)?
    private var forecastCache: (value: Forecast, latitude: Double, longitude: Double, date: Date)?

    func prompt() async -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE, d 'de' MMMM 'de' yyyy 'às' HH:mm:ss"
        let offset = TimeZone.current.secondsFromGMT(for: now)
        let sign = offset < 0 ? "-" : "+"
        let hours = abs(offset) / 3600
        let minutes = abs(offset) % 3600 / 60
        var lines = [
            "## Contexto atual",
            "Data e hora no Mac: \(formatter.string(from: now)) (\(TimeZone.current.identifier), UTC\(sign)\(String(format: "%02d:%02d", hours, minutes)))."
        ]

        if let place = await location() {
            if place.fromMac {
                lines.append("Local aproximado pelos Serviços de Localização do Mac: \(place.label).")
            } else {
                lines.append("Local aproximado pela rede/IP: \(place.label). Pode estar errado se houver VPN, relay ou rede móvel.")
            }
            if let forecast = await forecast(latitude: place.latitude, longitude: place.longitude),
               let summary = forecast.summary {
                lines.append("Clima e previsão (Open-Meteo, para o local aproximado; dias na hora local de lá):\n\(summary)")
            } else {
                lines.append("Clima e previsão: indisponíveis no momento.")
            }
        } else {
            lines.append("Local aproximado: indisponível no momento.")
            lines.append("Clima e previsão: indisponíveis sem uma localização aproximada.")
        }
        lines.append("Use estes dados apenas quando forem relevantes. Não apresente estimativas de localização como localização exata nem invente dados ausentes ou atualizados depois dos horários acima.")
        return Personality.default + "\n\n---\n\n" + lines.joined(separator: "\n")
    }

    private func location() async -> Place? {
        if let cached = macCache, Date().timeIntervalSince(cached.date) < 6 * 3600,
           !(await MacLocation.shared.isDenied) {
            return cached.value
        }
        if let fix = await MacLocation.shared.get() {
            let place = Place(latitude: fix.latitude, longitude: fix.longitude,
                              label: fix.label, fromMac: true)
            macCache = (place, Date())
            return place
        }
        if let cached = ipCache, Date().timeIntervalSince(cached.date) < 6 * 3600 {
            return cached.value
        }
        guard let url = URL(string: "https://ipwho.is/") else { return nil }
        do {
            let value: Location = try await get(url)
            guard let (latitude, longitude) = value.coordinates else { return nil }
            let place = Place(latitude: latitude, longitude: longitude,
                              label: value.label.isEmpty ? "região estimada pela rede" : value.label,
                              fromMac: false)
            ipCache = (place, Date())
            return place
        } catch {
            return nil
        }
    }

    private func forecast(latitude: Double, longitude: Double) async -> Forecast? {
        if let cached = forecastCache,
           cached.latitude == latitude, cached.longitude == longitude,
           Date().timeIntervalSince(cached.date) < 30 * 60 {
            return cached.value
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { return nil }
        do {
            let value: Forecast = try await get(url)
            guard value.summary != nil else { return nil }
            forecastCache = (value, latitude, longitude, Date())
            return value
        } catch {
            return nil
        }
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
