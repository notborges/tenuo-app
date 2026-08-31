import SwiftUI

struct LayerEditorView: View {
    @ObservedObject var model: AppModel
    var onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            LayerList(model: model, onOpenSettings: onOpenSettings)
                .frame(width: DS.Metrics.sidebarWidth)

            ColumnDivider()

            LayersPage(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Surface.window)
        .alert(
            "Could not read that profile",
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
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: DS.Metrics.header)
            .padding(.top, DS.Metrics.titlebar)
    }
}
