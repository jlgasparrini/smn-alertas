import Foundation

public protocol HTTPClient: Sendable {
    func data(from url: URL) async throws -> Data
}

public enum FetchError: LocalizedError, Equatable {
    case status(Int)
    case emptyFeed

    public var errorDescription: String? {
        switch self {
        case .status(429): "El SMN limitó las consultas; reintento en unos minutos."
        case .status(let code): "El servidor respondió con error \(code)."
        case .emptyFeed: "El feed del SMN vino vacío."
        }
    }
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 20)
        // A non-browser agent gets the RSS version of the SMN feed.
        request.setValue("SMNAlertas/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FetchError.status(status) }
        return data
    }
}

/// CAP files never change per URL, so they're kept across launches.
public protocol CAPStore: Sendable {
    func load(_ url: URL) -> Data?
    func save(_ data: Data, for url: URL)
    func prune(keeping urls: [URL])
}

public struct DiskCAPStore: CAPStore {
    let directory: URL

    public init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// ~/Library/Application Support/SMNAlertas/cap
    public static var standard: DiskCAPStore {
        DiskCAPStore(directory: URL.applicationSupportDirectory.appending(path: "SMNAlertas/cap", directoryHint: .isDirectory))
    }

    func file(_ url: URL) -> URL { directory.appending(path: url.pathComponents.suffix(2).joined(separator: "__")) }

    public func load(_ url: URL) -> Data? { try? Data(contentsOf: file(url)) }
    public func save(_ data: Data, for url: URL) { try? data.write(to: file(url), options: .atomic) }

    public func prune(keeping urls: [URL]) {
        let keep = Set(urls.map { file($0).lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for f in files where !keep.contains(f.lastPathComponent) { try? FileManager.default.removeItem(at: f) }
    }
}

public struct City: Codable, Equatable, Sendable {
    public var name: String
    public var coordinate: Coordinate
    public init(name: String, coordinate: Coordinate) { self.name = name; self.coordinate = coordinate }
}

/// City search through Open-Meteo's geocoding API, limited to Argentina.
public struct Geocoder: Sendable {
    let http: HTTPClient
    public init(http: HTTPClient = URLSessionHTTPClient()) { self.http = http }

    struct Response: Decodable {
        struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double; let admin1: String? }
        let results: [Result]?
    }

    public func search(_ query: String, limit: Int = 1) async throws -> [City] {
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [.init(name: "name", value: query), .init(name: "count", value: String(limit)),
                            .init(name: "language", value: "es"), .init(name: "countryCode", value: "AR")]
        let response = try JSONDecoder().decode(Response.self, from: try await http.data(from: comps.url!))
        return (response.results ?? []).map {
            City(name: [$0.name, $0.admin1].compactMap { $0 }.joined(separator: ", "),
                 coordinate: Coordinate(lat: $0.latitude, lon: $0.longitude))
        }
    }
}
