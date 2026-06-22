import Foundation
import Observation
#if canImport(CoreAILanguageModels) && canImport(FoundationModels)
import CoreAILanguageModels
import FoundationModels
#endif

/// Drives on-device language inference through Core AI.
///
/// The real Core AI / FoundationModels symbols only exist on macOS 27 with the
/// Xcode 27 SDK, so the actual calls are wrapped in `#if canImport(...)`. On any
/// other toolchain the runner compiles to a stub that explains why inference is
/// unavailable — keeping the catalog + hardware analyzer fully buildable.
///
/// Reference (WWDC26 "Integrate on-device AI models into your app using Core AI"):
/// ```swift
/// import FoundationModels
/// import CoreAILanguageModels
/// let model = try await CoreAILanguageModel(resourcesAt: modelURL)
/// let session = LanguageModelSession(model: model)
/// let response = try await session.respond(to: prompt)
/// ```
@MainActor
@Observable
final class LanguageRunner {

    enum State: Equatable {
        case idle
        case loading(String)
        case ready
        case generating
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var loadedModelURL: URL?

    /// Whether this build can actually run Core AI inference.
    static var runtimeAvailable: Bool {
        #if canImport(CoreAILanguageModels) && canImport(FoundationModels)
        return true
        #else
        return false
        #endif
    }

    static var unavailabilityReason: String {
        "Core AI inference requires building on macOS 27 with the Xcode 27 SDK "
        + "(frameworks CoreAILanguageModels + FoundationModels). The catalog and "
        + "hardware analysis work everywhere; this pane runs models once you build on a supported Mac."
    }

#if canImport(CoreAILanguageModels) && canImport(FoundationModels)
    private var session: LanguageModelSession?

    /// Load a `.aimodel` resource folder selected by the user.
    func load(modelAt url: URL) async {
        state = .loading(url.lastPathComponent)
        do {
            let model = try await CoreAILanguageModel(resourcesAt: url)
            session = LanguageModelSession(model: model)
            loadedModelURL = url
            state = .ready
        } catch {
            state = .failed("Load failed: \(error.localizedDescription)")
        }
    }

    /// Stream a completion for `prompt`, appending deltas via `onToken`.
    func generate(prompt: String, onToken: @escaping (String) -> Void) async {
        guard let session else {
            state = .failed("No model loaded.")
            return
        }
        state = .generating
        do {
            let stream = session.streamResponse(to: prompt)
            for try await partial in stream {
                onToken(partial.content)
            }
            state = .ready
        } catch {
            state = .failed("Generation failed: \(error.localizedDescription)")
        }
    }
#else
    /// Stub used when the Core AI frameworks aren't in the SDK.
    func load(modelAt url: URL) async {
        loadedModelURL = url
        state = .failed(Self.unavailabilityReason)
    }

    func generate(prompt: String, onToken: @escaping (String) -> Void) async {
        state = .failed(Self.unavailabilityReason)
    }
#endif
}
