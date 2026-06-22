import Foundation

/// Loads and holds the curated Core AI model catalog from the bundled JSON.
struct ModelCatalog: Sendable {

    let models: [ModelSpec]
    let note: String

    private struct Payload: Decodable {
        let note: String
        let models: [ModelSpec]
    }

    /// Loads `catalog.json` from the module bundle. Falls back to an empty
    /// catalog (with a diagnostic note) rather than crashing if decoding fails.
    static func loadBundled() -> ModelCatalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json") else {
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
