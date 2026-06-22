import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            CatalogSidebar()
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 460)
        } detail: {
            if let selected = model.selectedModel {
                ModelDetailView(model: selected)
                    .id(selected.id)
            } else {
                ContentUnavailableView("Select a model",
                                       systemImage: "square.stack.3d.up",
                                       description: Text("Pick a Core AI model to see how it fits this Mac."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HardwarePill()
            }
        }
    }
}

/// Compact chip/RAM summary that opens the full hardware report.
private struct HardwarePill: View {
    @Environment(AppModel.self) private var model
    @State private var showingReport = false

    var body: some View {
        Button {
            showingReport = true
        } label: {
            let host = model.host
            Label {
                Text("\(host.chip?.canonicalName ?? host.brandString) · \(Int(host.physicalMemoryGB.rounded())) GB")
                    .font(.callout.weight(.medium))
            } icon: {
                Image(systemName: host.isAppleSilicon ? "cpu.fill" : "cpu")
            }
        }
        .help("Show full hardware report")
        .popover(isPresented: $showingReport, arrowEdge: .bottom) {
            HardwareReportView()
                .frame(width: 460)
        }
    }
}
