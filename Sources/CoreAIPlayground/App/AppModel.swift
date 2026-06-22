import Foundation
import Observation

/// Top-level observable application state.
@MainActor
@Observable
final class AppModel {
    let host: HostMachine
    let catalog: ModelCatalog
    /// Shared across model selections so downloads survive navigation.
    let downloads = ModelDownloadManager()
    var selectedModelID: ModelSpec.ID?
    var modalityFilter: ModelSpec.Modality?
    var searchText: String = ""
    var sortOrder: SortOrder = .bestFit

    enum SortOrder: String, CaseIterable, Identifiable {
        case bestFit = "Best fit"
        case sizeAscending = "Size ↑"
        case sizeDescending = "Size ↓"
        case name = "Name"
        var id: String { rawValue }
    }

    init() {
        self.host = HostMachine.current()
        self.catalog = ModelCatalog.loadBundled()
        self.selectedModelID = catalog.models.first?.id
    }

    var selectedModel: ModelSpec? {
        guard let id = selectedModelID else { return nil }
        return catalog.models.first { $0.id == id }
    }

    /// Models after search + modality filtering, sorted per `sortOrder`.
    var visibleModels: [ModelSpec] {
        var models = catalog.models

        if let modality = modalityFilter {
            models = models.filter { $0.modality == modality }
        }
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let q = searchText.lowercased()
            models = models.filter {
                $0.name.lowercased().contains(q)
                || $0.family.lowercased().contains(q)
                || $0.tags.contains { $0.lowercased().contains(q) }
            }
        }

        switch sortOrder {
        case .name:
            models.sort { $0.name < $1.name }
        case .sizeAscending:
            models.sort { $0.downloadSizeMB < $1.downloadSizeMB }
        case .sizeDescending:
            models.sort { $0.downloadSizeMB > $1.downloadSizeMB }
        case .bestFit:
            models.sort {
                verdict(for: $0).rawValue > verdict(for: $1).rawValue
                    || (verdict(for: $0) == verdict(for: $1) && $0.downloadSizeMB < $1.downloadSizeMB)
            }
        }
        return models
    }

    // Not observed: memoization writes happen during view evaluation and must
    // not trigger SwiftUI invalidation. The host/catalog are immutable, so the
    // cache never needs to drive updates.
    @ObservationIgnored
    private var verdictCache: [ModelSpec.ID: CompatibilityEngine.Verdict] = [:]

    func verdict(for model: ModelSpec) -> CompatibilityEngine.Verdict {
        if let cached = verdictCache[model.id] { return cached }
        let v = CompatibilityEngine.evaluate(model: model, on: host).verdict
        verdictCache[model.id] = v
        return v
    }

    func result(for model: ModelSpec) -> CompatibilityEngine.Result {
        CompatibilityEngine.evaluate(model: model, on: host)
    }

    /// Count of models in each verdict bucket — used for the header summary.
    var verdictBreakdown: [(CompatibilityEngine.Verdict, Int)] {
        let grouped = Dictionary(grouping: catalog.models) { verdict(for: $0) }
        return [.recommended, .capable, .tight, .unsupported].map { ($0, grouped[$0]?.count ?? 0) }
    }
}
