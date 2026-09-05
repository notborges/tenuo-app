import SwiftUI

struct LayerEditorView: View {
    @ObservedObject var model: AppModel
    var onOpenSettings: () -> Void
    @State private var historyProfileID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                LayerList(
                    model: model, onOpenSettings: onOpenSettings,
                    onOpenHistory: { historyProfileID = $0 }
                )
                .frame(width: DS.Metrics.sidebarWidth)
                .windowPanel()
                .padding(.leading, DS.Metrics.windowInset)
                .padding(.vertical, DS.Metrics.windowInset)

                LayersPage(model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(historyProfileID == nil ? 1 : 0)
            .offset(x: reduceMotion || historyProfileID == nil ? 0 : -8)
            .allowsHitTesting(historyProfileID == nil)
            .disabled(historyProfileID != nil)
            .accessibilityHidden(historyProfileID != nil)

            if let historyProfileID {
                ProfileHistoryView(model: model, profileID: historyProfileID) {
                    self.historyProfileID = nil
                }
                .id(historyProfileID)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(x: 12)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: historyProfileID)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 1080, minHeight: 620)
        .background(DS.Surface.window)
        .tint(DS.Selection.solid)
        .onAppear {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-preview"),
                    ProcessInfo.processInfo.arguments.contains("--editor-history")
                {
                    historyProfileID = model.profile.id
                }
            #endif
        }
        .alert(
            "Could not complete that action",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct ColumnDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Line.hairline)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
    }
}

struct ColumnHeader<Content: View>: View {
    var reservesWindowControls = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: DS.Metrics.header)
            .padding(.top, reservesWindowControls ? DS.Metrics.titlebar : DS.Space.small)
    }
}
