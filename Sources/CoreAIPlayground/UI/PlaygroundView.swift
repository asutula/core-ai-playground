import SwiftUI
import UniformTypeIdentifiers

/// Interactive prompt console. Loads a downloaded `.aimodel` resource folder and
/// streams completions via `LanguageRunner`. Inference only executes on a build
/// that links Core AI (macOS 27 + Xcode 27); otherwise it explains what's needed.
struct PlaygroundView: View {
    let model: ModelSpec
    @Environment(AppModel.self) private var appModel
    @State private var runner = LanguageRunner()
    @State private var prompt: String = "Explain on-device AI in two sentences."
    @State private var output: String = ""
    @State private var showingImporter = false
    @State private var pasteURL: String = ""

    private var verdict: CompatibilityEngine.Verdict {
        appModel.verdict(for: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !LanguageRunner.runtimeAvailable {
                unavailableBanner
            } else if verdict == .unsupported {
                wontRunBanner
            }

            if model.modality != .languageModel {
                modalityNote
            }

            downloadSection

            modelLoaderRow

            promptEditor

            outputView

            statusLine
        }
        .fileImporter(isPresented: $showingImporter,
                      allowedContentTypes: [.folder, .data, .package],
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await runner.load(modelAt: url) }
            }
        }
    }

    // MARK: Rows

    private var modelLoaderRow: some View {
        HStack(spacing: 10) {
            Button {
                showingImporter = true
            } label: {
                Label(runner.loadedModelURL == nil ? "Load .aimodel…" : "Change model…",
                      systemImage: "tray.and.arrow.down")
            }
            .disabled(!LanguageRunner.runtimeAvailable)

            if let url = runner.loadedModelURL {
                Text(url.lastPathComponent)
                    .font(.caption.monospaced())
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
            } else {
                Text("Point at a downloaded resource folder for \(model.name).")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    // MARK: Download

    private var downloadSection: some View {
        let phase = appModel.downloads.phase(for: model)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("https://…/\(model.id).aimodel", text: $pasteURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .disabled(phase.isActive)

                switch phase {
                case .downloading, .verifying:
                    Button(role: .cancel) { appModel.downloads.cancel(model: model) } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                default:
                    Button { startDownload() } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .disabled(URL(string: pasteURL.trimmingCharacters(in: .whitespaces)) == nil)
                }
            }

            switch phase {
            case .downloading(let fraction, let received, let total):
                VStack(alignment: .leading, spacing: 2) {
                    ProgressView(value: fraction)
                    Text(total > 0
                         ? "\(byteString(received)) of \(byteString(total)) (\(Int(fraction * 100))%)"
                         : "\(byteString(received)) downloaded…")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            case .verifying:
                Label("Verifying checksum…", systemImage: "checkmark.shield").font(.caption2).foregroundStyle(.secondary)
            case .finished(let url):
                HStack(spacing: 8) {
                    Label("Downloaded \(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                    Button("Load this asset") { Task { await runner.load(modelAt: url) } }
                        .font(.caption)
                        .disabled(!LanguageRunner.runtimeAvailable)
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").font(.caption2).foregroundStyle(.orange)
            case .idle:
                if let existing = appModel.downloads.existingAsset(for: model) {
                    Button { Task { await runner.load(modelAt: existing) } } label: {
                        Label("Use previously downloaded \(existing.lastPathComponent)", systemImage: "internaldrive")
                    }
                    .font(.caption)
                    .disabled(!LanguageRunner.runtimeAvailable)
                } else {
                    Text("Paste a URL to an exported .aimodel asset, or load one from disk below.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .onAppear {
            appModel.downloads.register(model)
            if pasteURL.isEmpty, let u = model.downloadURL { pasteURL = u }
        }
    }

    private func startDownload() {
        guard let url = URL(string: pasteURL.trimmingCharacters(in: .whitespaces)) else { return }
        appModel.downloads.register(model)
        appModel.downloads.download(model: model, from: url)
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Prompt").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 80, maxHeight: 140)
                .padding(6)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))

            HStack {
                Spacer()
                Button {
                    runGeneration()
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRun)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private var outputView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Output").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                Text(output.isEmpty ? "Model output will stream here." : output)
                    .font(.body)
                    .foregroundStyle(output.isEmpty ? .tertiary : .primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 120, maxHeight: 240)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch runner.state {
        case .idle:
            EmptyView()
        case .loading(let name):
            Label("Loading \(name) — first load specializes for this chip and may take a moment…",
                  systemImage: "gearshape.2")
                .font(.caption).foregroundStyle(.secondary)
        case .ready:
            Label("Ready.", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.green)
        case .generating:
            Label("Generating…", systemImage: "ellipsis").font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }

    // MARK: Banners

    private var unavailableBanner: some View {
        banner(color: .orange, icon: "wrench.and.screwdriver",
               text: LanguageRunner.unavailabilityReason)
    }

    private var wontRunBanner: some View {
        banner(color: .red, icon: "xmark.octagon",
               text: "Compatibility analysis says this model won't fit this Mac. You can still load it, but expect failures or heavy paging.")
    }

    private var modalityNote: some View {
        banner(color: .blue, icon: "info.circle",
               text: "Interactive prompting targets language models. \(model.name) is a \(model.modality.label.lowercased()) model — drive it through \(model.runtimeLibrary) in code; this console focuses on text generation.")
    }

    private func banner(color: Color, icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Actions

    private var canRun: Bool {
        LanguageRunner.runtimeAvailable
        && model.modality == .languageModel
        && runner.loadedModelURL != nil
        && runner.state != .generating
        && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func runGeneration() {
        output = ""
        Task {
            await runner.generate(prompt: prompt) { delta in
                output = delta
            }
        }
    }
}
