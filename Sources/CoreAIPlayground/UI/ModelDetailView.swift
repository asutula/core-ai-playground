import SwiftUI

struct ModelDetailView: View {
    @Environment(AppModel.self) private var appModel
    let model: ModelSpec
    @State private var tab: Tab = .fit

    enum Tab: String, CaseIterable, Identifiable {
        case fit = "Hardware Fit"
        case specs = "Specs"
        case playground = "Playground"
        var id: String { rawValue }
    }

    private var result: CompatibilityEngine.Result {
        appModel.result(for: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch tab {
                case .fit:        fitSection
                case .specs:      specsSection
                case .playground: PlaygroundView(model: model)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(model.name)
        .navigationSubtitle(model.family)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: model.modality.symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(result.verdict.color)
                    .frame(width: 56, height: 56)
                    .background(result.verdict.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name).font(.title2.bold())
                    Text(model.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                VerdictBadge(verdict: result.verdict)
            }

            Text(result.headline)
                .font(.headline)
                .foregroundStyle(result.verdict.color)
        }
    }

    // MARK: Hardware fit

    private var fitSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            MemoryGauge(model: model, host: appModel.host, utilization: result.memoryUtilization)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(result.checks.enumerated()), id: \.element.id) { index, check in
                    if index > 0 { Divider() }
                    CheckRow(check: check)
                }
            }
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            if let tps = result.estimatedTokensPerSecond {
                Label(String(format: "Estimated generation speed: ~%.0f tokens/sec", tps),
                      systemImage: "gauge.with.dots.needle.67percent")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Specs

    private var specsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpecGrid(rows: [
                ("Modality", model.modality.label),
                ("Family", model.family),
                ("Parameters", Format.params(model.parametersB)),
                ("Precision", model.precision.label),
                ("Download size", Format.size(mb: model.downloadSizeMB)),
                ("Est. runtime RAM", Format.gb(model.runtimeRAMGB)),
                ("Context window", model.contextTokens.map { "\($0.formatted()) tokens" } ?? "—"),
                ("Min macOS", "macOS \(model.minOSMajor)+"),
                ("Runtime library", model.runtimeLibrary),
                ("Apple Silicon", model.requiresAppleSilicon ? "Required" : "Not required"),
                ("Spec source", model.verified ? "Apple docs / WWDC26" : "Estimated")
            ])

            if !model.tags.isEmpty {
                FlowTags(tags: model.tags)
            }

            if let source = model.sourceURL, let url = URL(string: source) {
                Link(destination: url) {
                    Label("View in apple/coreai-models", systemImage: "arrow.up.right.square")
                }
                .font(.callout)
            }

            Text(appModel.catalog.note)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }
}

// MARK: - Subviews

private struct CheckRow: View {
    let check: CompatibilityEngine.Check
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.status.symbol)
                .foregroundStyle(check.status.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title).font(.subheadline.weight(.semibold))
                Text(check.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

/// Visual gauge of model working set vs available unified memory.
private struct MemoryGauge: View {
    let model: ModelSpec
    let host: HostMachine
    let utilization: Double

    var body: some View {
        let available = host.memoryAvailableForModelGB
        let fraction = min(1.0, utilization.isFinite ? utilization : 1.0)
        let color: Color = utilization > 1 ? .red : utilization > 0.85 ? .orange : utilization > 0.6 ? .blue : .green

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Unified memory").font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.1f GB model · %.1f GB free · %.0f GB total",
                            model.runtimeRAMGB, available, host.physicalMemoryGB))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 14)

            Text("Bar shows the model's working set as a share of RAM available after reserving \(Format.gb(host.systemReserveGB)) for macOS.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SpecGrid: View {
    let rows: [(String, String)]
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            ForEach(rows, id: \.0) { key, value in
                GridRow {
                    Text(key).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                    Text(value).fontWeight(.medium)
                }
                .font(.callout)
            }
        }
    }
}

private struct FlowTags: View {
    let tags: [String]
    private let columns = [GridItem(.adaptive(minimum: 60, maximum: 160), spacing: 6, alignment: .leading)]
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}
