import AppKit
import SwiftUI

enum MappingOutput: String, CaseIterable {
    case key = "Key"
    case application = "App"
    case open = "Open"
    case shortcut = "Shortcut"

    var symbol: String {
        switch self {
        case .key: return "keyboard"
        case .application: return "app"
        case .open: return "folder"
        case .shortcut: return "square.stack.3d.up"
        }
    }

    init(mapping: LayerMapping?) {
        guard case let .action(.macAction(action)) = mapping else { self = .key; return }
        switch action {
        case .application: self = .application
        case .file, .url: self = .open
        case .shortcut: self = .shortcut
        }
    }
}

struct MappingOutputPicker: View {
    @Binding var selection: MappingOutput
    var hasPro: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MappingOutput.allCases, id: \.self) { output in
                Button {
                    selection = output
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: output.symbol).font(.system(size: 15))
                        Text(output.rawValue).font(DS.Typography.footnote)
                        if !hasPro && output != .key {
                            Text("Pro").font(.system(size: 9, weight: .medium))
                                .foregroundStyle(DS.Ink.tertiary)
                        }
                    }
                    .foregroundStyle(selection == output ? DS.Ink.primary : DS.Ink.secondary)
                    .frame(maxWidth: .infinity).frame(height: hasPro ? 50 : 62)
                    .background(
                        selection == output ? DS.Selection.fill : .clear,
                        in: RoundedRectangle(cornerRadius: DS.Radius.small)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(ApplicationControlStyle())
                .accessibilityAddTraits(selection == output ? .isSelected : [])
            }
        }
        .padding(4)
        .background(DS.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.small + 4))
    }
}

struct MacActionEditor: View {
    let output: MappingOutput
    let current: LayerMapping?
    let hasPro: Bool
    let activate: () -> Void
    let assign: (MacAction) -> Void
    @State private var showsApps = false
    @State private var showsShortcuts = false
    @State private var link = ""
    @State private var failure: String?
    @State private var unavailable = false

    private var destination: MacAction? {
        guard MappingOutput(mapping: current) == output,
            case let .action(.macAction(action)) = current
        else { return nil }
        return action
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.medium) {
            Text(title).sectionLabel()
            if let destination {
                HStack(spacing: 12) {
                    if case let .application(target) = destination {
                        ApplicationIcon(bundleID: target.id, size: 36)
                    } else {
                        Image(systemName: destination.symbol).font(.system(size: 25))
                            .frame(width: 36, height: 36).foregroundStyle(DS.Ink.secondary)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(destination.displayLabel).font(DS.Typography.body).lineLimit(2)
                        Text(
                            !hasPro
                                ? "Inactive · requires Tenuo Pro"
                                : (unavailable ? "Not found on this Mac" : "Assigned to this key")
                        )
                        .font(DS.Typography.footnote).foregroundStyle(DS.Ink.tertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard()
            }
            Text(description).font(DS.Typography.label).foregroundStyle(DS.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !hasPro {
                ProFeaturePrompt(
                    title: "Included in Tenuo Pro", detail: example, activate: activate)
            } else {
                controls
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.circle")
                    .font(DS.Typography.label).foregroundStyle(DS.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showsApps) {
            ApplicationPicker(subtitle: "Open this app, or bring it to the front.") { url in
                guard let app = PickableApplication.read(url) else { return }
                assign(.application(NamedActionTarget(id: app.id, name: app.name)))
            }
        }
        .sheet(isPresented: $showsShortcuts) {
            ShortcutPicker { chosen in
                var target = chosen
                if unavailable, case let .shortcut(previous) = destination {
                    target.localID = previous.localID
                }
                assign(.shortcut(target))
            }
        }
        .task(id: destination) {
            failure = nil
            unavailable = false
            if case let .url(value) = destination { link = value }
            if case let .application(target) = destination {
                unavailable =
                    NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.id) == nil
            }
            if case let .file(target) = destination {
                unavailable = await Task.detached {
                    var stale = false
                    guard
                        let url = try? URL(
                            resolvingBookmarkData: target.bookmark,
                            options: [.withoutUI, .withoutMounting], relativeTo: nil,
                            bookmarkDataIsStale: &stale)
                    else { return true }
                    return !FileManager.default.fileExists(atPath: url.path)
                }.value
            }
            if case let .shortcut(target) = destination {
                do {
                    unavailable = try await !ShortcutCatalog.load().contains { $0.id == target.id }
                } catch { failure = error.localizedDescription }
            }
        }
    }

    @ViewBuilder private var controls: some View {
        switch output {
        case .application:
            targetButton("Choose app…", symbol: "plus.app") { showsApps = true }
        case .shortcut:
            targetButton("Choose shortcut…", symbol: "square.stack.3d.up") { showsShortcuts = true }
        case .open:
            targetButton("Choose file or folder…", symbol: "folder") { chooseFile() }
            VStack(alignment: .leading, spacing: 8) {
                Text("Or open a website").sectionLabel()
                TextField("https://example.com", text: $link)
                    .textFieldStyle(.plain).font(DS.Typography.label)
                    .padding(10).background(
                        DS.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.field)
                    )
                    .onSubmit { saveLink() }
                    .accessibilityLabel("Website address")
                Button("Use this link", action: saveLink)
                    .disabled(
                        !MacAction.url(link.trimmingCharacters(in: .whitespacesAndNewlines)).isValid
                    )
            }
        case .key: EmptyView()
        }
    }

    private func targetButton(_ title: String, symbol: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                Text(destination == nil ? title : (unavailable ? "Choose on this Mac…" : "Change…"))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
            }
            .font(DS.Typography.body).padding(.horizontal, 12).frame(height: 40)
            .background(DS.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(ApplicationControlStyle())
    }

    private var example: String {
        switch output {
        case .application: return "For example, hold your layer key and press S to open Safari."
        case .open: return "For example, open your project folder with a single layer shortcut."
        case .shortcut: return "For example, start your focus routine with a single layer shortcut."
        case .key: return ""
        }
    }

    private var title: String {
        switch output {
        case .application: return "Open an app"
        case .open: return "Open a file or link"
        case .shortcut: return "Run an Apple Shortcut"
        case .key: return "Send a key"
        }
    }

    private var description: String {
        switch output {
        case .application: return "Launch an app or switch to it if it’s already open."
        case .open: return "Keep a project folder, document, or website one key away."
        case .shortcut:
            return
                "Run one of your shortcuts. Shortcuts handles any permissions or prompts it needs."
        case .key: return ""
        }
    }

    private func saveLink() {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard MacAction.url(value).isValid else { return }
        assign(.url(value))
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    var target = try await Task.detached {
                        FileActionTarget(
                            bookmark: try url.bookmarkData(
                                options: [],
                                includingResourceValuesForKeys: nil, relativeTo: nil),
                            name: url.lastPathComponent)
                    }.value
                    if unavailable, case let .file(previous) = destination {
                        target.localID = previous.localID
                    }
                    assign(.file(target))
                } catch { failure = "This item could not be saved. Try choosing it again." }
            }
        }
    }
}

private struct ShortcutPicker: View {
    let choose: (NamedActionTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var shortcuts: [NamedActionTarget] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var revision = 0
    @FocusState private var searchFocused: Bool

    private var matches: [NamedActionTarget] {
        shortcuts.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Choose a shortcut").font(DS.Typography.title)
                    Text("Your shortcuts, one key away.").font(DS.Typography.label).foregroundStyle(
                        DS.Ink.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").frame(width: 28, height: 28)
                        .background(DS.Surface.raised, in: Circle()).contentShape(Circle())
                }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel(
                    "Cancel shortcut selection")
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(DS.Ink.tertiary)
                TextField("Search shortcuts", text: $search).textFieldStyle(.plain).focused(
                    $searchFocused
                )
                .onSubmit { if let item = matches.first { select(item) } }
            }.padding(10).background(
                DS.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.field))
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let failure {
                ContentUnavailableView(
                    "Couldn’t load shortcuts", systemImage: "exclamationmark.circle",
                    description: Text(failure))
            } else if matches.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No shortcuts yet" : "No matching shortcuts",
                    systemImage: "square.stack.3d.up",
                    description: Text(
                        search.isEmpty
                            ? "Create one in Apple Shortcuts, then refresh this list."
                            : "Try a different name."))
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(matches, id: \.id) { item in
                            Button {
                                select(item)
                            } label: {
                                HStack(spacing: 10) {
                                    ApplicationIcon(bundleID: "com.apple.shortcuts", size: 28)
                                    Text(item.name).font(DS.Typography.body).lineLimit(1)
                                    Spacer()
                                }.padding(.horizontal, 10).frame(height: 44).contentShape(
                                    Rectangle())
                            }.buttonStyle(ApplicationControlStyle())
                        }
                    }
                }
            }
            HStack {
                Button("Open Shortcuts") {
                    if let url = NSWorkspace.shared.urlForApplication(
                        withBundleIdentifier: "com.apple.shortcuts")
                    {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    }
                }
                Spacer()
                Button {
                    revision += 1
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(loading)
            }.font(DS.Typography.label)
        }
        .padding(24).frame(width: 440, height: 510).background(DS.Surface.window)
        .task(id: revision) {
            loading = true; failure = nil
            do { shortcuts = try await ShortcutCatalog.load(refresh: revision > 0) } catch {
                failure = error.localizedDescription
            }
            loading = false; searchFocused = true
        }
    }

    private func select(_ item: NamedActionTarget) {
        choose(item)
        dismiss()
    }
}

struct ProFeaturePrompt: View {
    let title: String
    let detail: String
    let activate: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(DS.Typography.body.weight(.semibold))
            Text(detail).font(DS.Typography.label).foregroundStyle(DS.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Get Tenuo Pro") {
                openURL(URL(string: "https://tenuo.app/#pricing")!)
            }
            QuietButton(title: "Activate license", action: activate)
        }
    }
}
