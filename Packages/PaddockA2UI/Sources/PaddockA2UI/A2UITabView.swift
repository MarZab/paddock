import A2UICore
import A2UISwiftUI
import SwiftUI

/// An A2UI tab: the agent's surfaces, one under the other, drawn by A2UI's SwiftUI renderer with
/// Paddock's catalog. A capsule says whether the operator's last answer reached the agent (or a
/// link opened in the sandbox); a bar says while a surface waits for the agent.
public struct A2UITabView: View {
    let tab: A2UITab
    @State private var shown: A2UITab.Notice?

    public init(tab: A2UITab) {
        self.tab = tab
    }

    public var body: some View {
        Group {
            if tab.surfaces.isEmpty {
                ContentUnavailableView("Waiting for the agent", systemImage: "rectangle.and.pencil.and.ellipsis",
                                       description: Text("The agent's interface shows here once it sends it."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(tab.surfaces, id: \.surfaceID) { surface in
                            SurfaceCard(surface: surface, catalog: tab.catalog)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .overlay(alignment: .top) {
            if let shown {
                Label(shown.text, systemImage: shown.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .foregroundStyle(shown.ok ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if !tab.waitingCalls.isEmpty {
                Label("Waiting for the agent to answer", systemImage: "hourglass")
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 10)
            }
        }
        .onChange(of: tab.notice) { _, notice in
            guard let notice else { return }
            withAnimation { shown = notice }
            Task {
                try? await Task.sleep(for: .seconds(notice.ok ? 3 : 8))
                withAnimation { if shown == notice { shown = nil } }
            }
        }
    }
}

/// One surface; A2UI's `Surface` observes its model.
private struct SurfaceCard: View {
    @ObservedObject var surface: SurfaceViewModel
    let catalog: Catalog<ComponentImplementation>

    var body: some View {
        Surface(viewModel: surface, catalog: catalog)
    }
}
