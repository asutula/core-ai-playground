import Foundation

/// Loads and holds the curated Core AI model catalog from the bundled JSON.
struct ModelCatalog: Sendable {

    let models: [ModelSpec]
    let note: String

    private struct Payload: Decodable {
        let note: String
        let models: [ModelSpec]
    }

    /// The bundle that carries `catalog.json`. SwiftPM synthesizes
    /// `Bundle.module`; the Xcode app target ships it in `Bundle.main`.
    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    /// Locates `catalog.json` whether it sits at the bundle's resource root or
    /// under a `Resources/` subdirectory (depends on the build system).
    static func catalogURL() -> URL? {
        let bundle = resourceBundle
        if let url = bundle.url(forResource: "catalog", withExtension: "json") {
            return url
        }
        return bundle.url(forResource: "catalog", withExtension: "json", subdirectory: "Resources")
    }

    /// Loads `catalog.json` from the appropriate bundle. Falls back to an empty
    /// catalog (with a diagnostic note) rather than crashing if decoding fails.
    static func loadBundled() -> ModelCatalog {
        guard let url = catalogURL() else {
            return ModelCatalog(models: [], note: "catalog.json not found in bundle.")
        }
        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            return ModelCatalog(models: payload.models, note: payload.note)
        } catch {
            return ModelCatalog(models: [], note: "Failed to decode catalog.json: \(error)")
        }
    }

    var families: [String] {
        Array(Set(models.map(\.family))).sorted()
    }
}
