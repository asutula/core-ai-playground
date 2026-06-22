//  ModelDownloaderExtension.swift
//
//  Production delivery path: Background Assets.
//
//  Unlike the in-app `ModelDownloadManager` (URLSession, runs only while the
//  app is open), Background Assets lets the system download `.aimodel` packs
//  out-of-process — including *before first launch* and while the app is
//  closed — driven by a manifest you host. This is the recommended way to ship
//  large Core AI models without bloating the app bundle.
//
//  This file is a ready-to-wire TEMPLATE. It is compiled only when the
//  `BACKGROUND_ASSETS_EXTENSION` Swift flag is set, because Background Assets
//  requires:
//
//    1. A dedicated app-extension target (type: Background Download) whose
//       principal class is this `@main` extension.
//    2. The `com.apple.developer.background-assets` entitlement on both the app
//       and the extension (needs a provisioning profile / App Store Connect).
//    3. Info.plist keys on the app:
//         BAManifestURL   – URL of your asset manifest
//         BAMaxInstallSize / BAMaxDownloadSize – budgets
//    4. Hosting an Apple-format asset manifest that lists each pack + size.
//
//  To activate: create the extension target, add `BACKGROUND_ASSETS_EXTENSION`
//  to its "Active Compilation Conditions", move this file into that target, and
//  add `@main` to the class. See the README "Production delivery via Background
//  Assets" section.

#if BACKGROUND_ASSETS_EXTENSION
import BackgroundAssets
import Foundation
import OSLog

@available(macOS 13.0, *)
final class ModelDownloaderExtension: BADownloaderExtension {

    private let log = Logger(subsystem: "io.textile.CoreAIPlayground", category: "BackgroundAssets")

    /// Called when the system fetches your manifest. Return the set of downloads
    /// you want scheduled. Here we'd map manifest entries → `.aimodel` packs.
    func downloads(for request: BAContentRequest,
                   manifestURL: URL,
                   extensionInfo: BAAppExtensionInfo) -> Set<BADownload> {
        log.info("Manifest available at \(manifestURL, privacy: .public) for request \(String(describing: request))")
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(AssetManifest.self, from: data)
            let downloads = manifest.packs.map { pack -> BADownload in
                BAURLDownload(
                    identifier: pack.id,
                    request: URLRequest(url: pack.url),
                    essential: pack.essential,
                    fileSize: pack.sizeBytes,
                    applicationGroupIdentifier: extensionInfo.applicationGroupIdentifier,
                    priority: .default
                )
            }
            return Set(downloads)
        } catch {
            log.error("Failed to build downloads: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func backgroundDownload(_ download: BADownload,
                            finishedWithFileURL fileURL: URL) {
        // Move the delivered pack into the shared app group container so the app
        // can load it via `CoreAILanguageModel(resourcesAt:)`.
        log.info("Finished \(download.identifier, privacy: .public) at \(fileURL, privacy: .public)")
    }

    func backgroundDownload(_ download: BADownload,
                            failedWithError error: Error) {
        log.error("Download \(download.identifier, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}

/// Shape of the manifest you host (mirror this on the server side).
private struct AssetManifest: Decodable {
    struct Pack: Decodable {
        let id: String
        let url: URL
        let sizeBytes: UInt64
        let essential: Bool
    }
    let packs: [Pack]
}
#endif
