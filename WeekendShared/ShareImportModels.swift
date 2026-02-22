import Foundation

enum ShareImportConstants {
    static let appGroupIdentifier = "group.com.mazharelstub.theweekend"
    static let inboxDirectoryName = "share-inbox"
    static let retentionInterval: TimeInterval = 7 * 24 * 60 * 60
}

struct IncomingSharePayload: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let url: URL?
    let text: String?
    let sourceAppBundleID: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        url: URL?,
        text: String?,
        sourceAppBundleID: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.url = url
        self.text = text
        self.sourceAppBundleID = sourceAppBundleID
    }
}

struct AddPlanPrefill: Codable, Equatable {
    let title: String?
    let details: String?

    static func from(payload: IncomingSharePayload) -> AddPlanPrefill? {
        let trimmedText = payload.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleFromText = trimmedText?
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        let normalizedURLString = payload.url?.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        let titleFromURL = payload.url
            .flatMap { $0.host }
            .map { host -> String in
                host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }

        let rawTitle = titleFromText ?? titleFromURL
        let resolvedTitle: String?
        if let rawTitle {
            resolvedTitle = String(rawTitle.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            resolvedTitle = nil
        }

        var detailChunks: [String] = []
        if let trimmedText, !trimmedText.isEmpty {
            detailChunks.append(trimmedText)
        }
        if let normalizedURLString, !normalizedURLString.isEmpty {
            let textAlreadyContainsURL = trimmedText?
                .range(of: normalizedURLString, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            if !textAlreadyContainsURL {
                detailChunks.append(normalizedURLString)
            }
        }

        let resolvedDetails = detailChunks.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetails = resolvedDetails.isEmpty ? nil : resolvedDetails

        guard resolvedTitle != nil || normalizedDetails != nil else { return nil }
        return AddPlanPrefill(title: resolvedTitle, details: normalizedDetails)
    }
}

final class SharedInboxStore {
    static let shared = SharedInboxStore()

    private let fileManager: FileManager
    private let directoryURL: URL
    private let retentionInterval: TimeInterval

    init(
        fileManager: FileManager = .default,
        appGroupIdentifier: String = ShareImportConstants.appGroupIdentifier,
        fallbackBaseDirectory: URL? = nil,
        retentionInterval: TimeInterval = ShareImportConstants.retentionInterval
    ) {
        self.fileManager = fileManager
        self.retentionInterval = retentionInterval

        let baseDirectory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? fallbackBaseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        directoryURL = baseDirectory.appendingPathComponent(ShareImportConstants.inboxDirectoryName, isDirectory: true)

        if !fileManager.fileExists(atPath: directoryURL.path) {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    func save(_ payload: IncomingSharePayload) {
        let url = fileURL(for: payload.id)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func load(id: UUID, now: Date = Date()) -> IncomingSharePayload? {
        let url = fileURL(for: id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let payload = try? decoder.decode(IncomingSharePayload.self, from: data) else {
            return nil
        }
        guard now.timeIntervalSince(payload.createdAt) <= retentionInterval else {
            remove(id: id)
            return nil
        }
        return payload
    }

    func remove(id: UUID) {
        try? fileManager.removeItem(at: fileURL(for: id))
    }

    func purgeExpiredPayloads(now: Date = Date()) {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for fileURL in fileURLs where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let payload = try? decoder.decode(IncomingSharePayload.self, from: data) else {
                try? fileManager.removeItem(at: fileURL)
                continue
            }
            if now.timeIntervalSince(payload.createdAt) > retentionInterval {
                try? fileManager.removeItem(at: fileURL)
            }
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directoryURL.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }
}
