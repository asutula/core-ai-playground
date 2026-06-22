import SwiftUI

/// Full breakdown of the host machine — the reference panel for the
/// "specs vs. requirements" story.
struct HardwareReportView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let host = model.host
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: host.isAppleSilicon ? "cpu.fill" : "cpu")
                        .font(.system(size: 30))
                        .foregroundStyle(host.supportsCoreAI ? .green : .orange)
                    VStack(alignment: .leading) {
                        Text(host.chip?.canonicalName ?? host.brandString)
                            .font(.title3.bold())
                        Text(host.osVersionString).font(.caption).foregroundStyle(.secondary)
                    }
                }

                coreAIBanner(host)

                Group {
                    section("Compute") {
                        row("Chip", host.chip?.canonicalName ?? host.brandString)
                        row("Architecture", host.isAppleSilicon ? "Apple Silicon (arm64)" : "Intel (x86_64)")
                        row("CPU cores", "\(host.totalCPUCores) (\(host.performanceCores)P / \(host.efficiencyCores)E)")
                        if let chip = host.chip {
                            row("GPU cores", chip.gpuCores.lowerBound == chip.gpuCores.upperBound
                                ? "\(chip.gpuCores.lowerBound)"
                                : "\(chip.gpuCores.lowerBound)–\(chip.gpuCores.upperBound)")
                            row("Neural Engine", formatTOPS(chip.neuralEngineTOPS))
                            row("Memory bandwidth", "\(chip.memoryBandwidthGBs) GB/s")
                        }
                        if let metal = host.metalDeviceName {
                            row("Metal device", metal)
                        }
                    }

                    section("Memory & storage") {
                        row("Unified memory", Format.gb(host.physicalMemoryGB))
                        row("Reserved for macOS", Format.gb(host.systemReserveGB))
                        row("Available for models", Format.gb(host.memoryAvailableForModelGB))
                        if let ws = host.recommendedMaxWorkingSetGB {
                            row("GPU working-set hint", Format.gb(ws))
                        }
                        row("Free disk", Format.gb(host.freeDiskGB))
                    }

                    section("Software") {
                        row("OS", host.osVersionString)
                        row("Model identifier", host.modelIdentifier)
                        row("Core AI (macOS 27+)", host.supportsCoreAI ? "Available" : "Not available")
                        row("Inference runtime", LanguageRunner.runtimeAvailable ? "Linked" : "Not in this build")
                    }
                }
            }
            .padding(18)
        }
    }

    private func coreAIBanner(_ host: HostMachine) -> some View {
        let ok = host.supportsCoreAI
        return Label {
            Text(ok
                 ? "This Mac meets Core AI's baseline (Apple Silicon + macOS 27+)."
                 : host.isAppleSilicon
                   ? "Core AI needs macOS 27+. You can still explore the catalog and fit analysis."
                   : "Core AI requires Apple Silicon. Catalog and analysis remain available.")
        } icon: {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(ok ? .green : .orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((ok ? Color.green : .orange).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).fontWeight(.medium).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }

    private func formatTOPS(_ t: Double) -> String {
        t == t.rounded() ? String(format: "%.0f TOPS", t) : String(format: "%.1f TOPS", t)
    }
}
