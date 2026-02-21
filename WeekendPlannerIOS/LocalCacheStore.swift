import Foundation

enum PersistencePolicy {
    case debounced
    case immediate
}

final class LocalCacheStore {
    static let shared = LocalCacheStore()

    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        self.fileManager = fileManager

        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directoryURL = base.appendingPathComponent("WeekendPlannerIOSCache", isDirectory: true)
        }

        if !fileManager.fileExists(atPath: self.directoryURL.path) {
            try? fileManager.createDirectory(at: self.directoryURL, withIntermediateDirectories: true)
        }
    }

    func load<T: Decodable>(_ type: T.Type, fileName: String, fallback: T) -> T {
        let url = directoryURL.appendingPathComponent(fileName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let decoded = try? decoder.decode(T.self, from: data) else {
            return fallback
        }
        return decoded
    }

    func save<T: Encodable>(_ value: T, fileName: String) {
        let url = directoryURL.appendingPathComponent(fileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func remove(fileName: String) {
        let url = directoryURL.appendingPathComponent(fileName)
        try? fileManager.removeItem(at: url)
    }
}

final class PersistenceCoordinator {
    private let store: LocalCacheStore
    private let queue: DispatchQueue
    private let debounceInterval: TimeInterval
    private var pendingWorkItems: [String: DispatchWorkItem] = [:]

    init(
        store: LocalCacheStore = .shared,
        debounceInterval: TimeInterval = 0.3,
        queue: DispatchQueue = DispatchQueue(label: "weekendplanner.persistence", qos: .utility)
    ) {
        self.store = store
        self.debounceInterval = debounceInterval
        self.queue = queue
    }

    func scheduleSave<T: Encodable>(_ value: T, fileName: String, policy: PersistencePolicy = .debounced) {
        let action = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.store.save(value, fileName: fileName)
            self.pendingWorkItems[fileName] = nil
        }
        schedule(action: action, fileName: fileName, policy: policy)
    }

    func scheduleRemove(fileName: String, policy: PersistencePolicy = .debounced) {
        let action = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.store.remove(fileName: fileName)
            self.pendingWorkItems[fileName] = nil
        }
        schedule(action: action, fileName: fileName, policy: policy)
    }

    private func schedule(action: DispatchWorkItem, fileName: String, policy: PersistencePolicy) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pendingWorkItems[fileName]?.cancel()
            self.pendingWorkItems[fileName] = action

            switch policy {
            case .immediate:
                self.queue.async(execute: action)
            case .debounced:
                self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: action)
            }
        }
    }
}
