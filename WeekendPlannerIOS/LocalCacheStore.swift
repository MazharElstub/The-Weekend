import Foundation

final class LocalCacheStore {
    static let shared = LocalCacheStore()

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directoryURL = base.appendingPathComponent("WeekendPlannerIOSCache", isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func load<T: Decodable>(_ type: T.Type, fileName: String, fallback: T) -> T {
        let url = directoryURL.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(T.self, from: data) else {
            return fallback
        }
        return decoded
    }

    func save<T: Encodable>(_ value: T, fileName: String) {
        let url = directoryURL.appendingPathComponent(fileName)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func remove(fileName: String) {
        let url = directoryURL.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: url)
    }
}
