import UIKit
import UniformTypeIdentifiers
import os

final class ShareViewController: UIViewController {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WeekendPlannerShareExtension",
        category: "ShareImport"
    )
    private var hasProcessedShare = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasProcessedShare else { return }
        hasProcessedShare = true

        Task { @MainActor in
            await processShareRequest()
        }
    }

    @MainActor
    private func processShareRequest() async {
        guard let payload = await extractPayload() else {
            logger.error("No supported URL/text content found in share request.")
            presentAlertAndFinish(
                title: "Unsupported Share",
                message: "Share a web link or text to add it to The Weekend."
            )
            return
        }

        let store = SharedInboxStore()
        store.purgeExpiredPayloads()
        store.save(payload)

        guard let callbackURL = URL(string: "theweekend://share?id=\(payload.id.uuidString)") else {
            logger.error("Failed to construct callback URL for payload id=\(payload.id.uuidString, privacy: .public)")
            completeRequest()
            return
        }

        extensionContext?.open(callbackURL) { [weak self] success in
            guard let self else { return }
            if success {
                self.logger.log("Opened host app for payload id=\(payload.id.uuidString, privacy: .public)")
                self.completeRequest()
                return
            }

            self.logger.error("Failed to open host app for payload id=\(payload.id.uuidString, privacy: .public)")
            DispatchQueue.main.async {
                self.presentAlertAndFinish(
                    title: "Open The Weekend",
                    message: "Saved your shared item. Open The Weekend to finish adding this plan."
                )
            }
        }
    }

    private func extractPayload() async -> IncomingSharePayload? {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return nil
        }

        let providers = extensionItems
            .compactMap { $0.attachments }
            .flatMap { $0 }

        let sharedURL = await loadFirstURL(from: providers)
        let sharedText = await loadFirstText(from: providers)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard sharedURL != nil || !sharedText.isEmpty else { return nil }

        return IncomingSharePayload(
            url: sharedURL,
            text: sharedText.isEmpty ? nil : sharedText,
            sourceAppBundleID: nil
        )
    }

    private func loadFirstURL(from providers: [NSItemProvider]) async -> URL? {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { continue }
            if let item = await loadItem(from: provider, typeIdentifier: UTType.url.identifier) {
                if let url = item as? URL {
                    return url
                }
                if let url = item as? NSURL {
                    return url as URL
                }
                if let string = item as? String {
                    return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8) {
                    return URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return nil
    }

    private func loadFirstText(from providers: [NSItemProvider]) async -> String {
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { continue }
            if let item = await loadItem(from: provider, typeIdentifier: UTType.plainText.identifier) {
                if let string = item as? String {
                    return string
                }
                if let attributed = item as? NSAttributedString {
                    return attributed.string
                }
                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8) {
                    return string
                }
            }
        }
        return ""
    }

    private func loadItem(from provider: NSItemProvider, typeIdentifier: String) async -> Any? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                continuation.resume(returning: item)
            }
        }
    }

    @MainActor
    private func presentAlertAndFinish(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.completeRequest()
        })

        if presentedViewController == nil {
            present(alert, animated: true)
        } else {
            completeRequest()
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
