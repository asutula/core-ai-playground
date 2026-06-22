import SwiftUI

struct CatalogSidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VerdictSummaryBar()
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            List(selection: $model.selectedModelID) {
                ForEach(model.visibleModels) { spec in
                    ModelRow(model: spec, verdict: model.verdict(for: spec))
                        .tag(spec.id)
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search models, families, tags")
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBar()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
        }
        .navigationTitle("Core AI Models")
    }
}

private struct FilterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack {
            Picker("Type", selection: $model.modalityFilter) {
                Text("All types").tag(ModelSpec.Modality?.none)
                ForEach(ModelSpec.Modality.allCases, id: \.self) { m in
                    Label(m.label, systemImage: m.symbol).tag(ModelSpec.Modality?.some(m))
                }
            }
            .labelsHidden()

            Spacer()

            Picker("Sort", selection: $model.sortOrder) {
                ForEach(AppModel.SortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 130)
        }
        .font(.caption)
    }
}

/// Header bar summarizing how many models land in each verdict bucket.
private struct VerdictSummaryBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            ForEach(model.verdictBreakdown, id: \.0) { verdict, count in
                HStack(spacing: 4) {
                    Image(systemName: verdict.symbol)
                    Text("\(count)")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(verdict.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(verdict.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .help("\(count) \(verdict.label)")
            }
        }
    }
}

private struct ModelRow: View {
    let model: ModelSpec
    let verdict: CompatibilityEngine.Verdict

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.modality.symbol)
                .font(.title3)
                .foregroundStyle(verdict.color)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name).font(.body.weight(.medium))
                    if !model.verified {
                        Text("est.")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(model.modality.label)
                    Text("·")
                    Text(Format.size(mb: model.downloadSizeMB))
                    if model.parametersB != nil {
                        Text("·")
                        Text(Format.params(model.parametersB))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
            VerdictBadge(verdict: verdict, compact: true)
        }
        .padding(.vertical, 3)
    }
}
