import AppKit
import SwiftUI

@MainActor
enum ApplicationArtwork {
    static let cache = NSCache<NSString, NSImage>()

    static func icon(id: String, url: URL? = nil) -> NSImage? {
        if let image = cache.object(forKey: id as NSString) { return image }
        guard let url = url ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        cache.setObject(image, forKey: id as NSString)
        return image
    }
}

struct ApplicationIcon: View {
    let bundleID: String
    var size: CGFloat = 32
    var url: URL?
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable().padding(3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: bundleID) { icon = ApplicationArtwork.icon(id: bundleID, url: url) }
    }
}

struct PickableApplication: Identifiable, Sendable {
    let id: String
    let name: String
    let url: URL

    private static func isAgent(_ value: Any?) -> Bool {
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String {
            return ["1", "true", "yes"].contains(value.lowercased())
        }
        return false
    }

    static func read(_ url: URL) -> Self? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
            id != "app.tenuo", id != "app.tenuo.dev",
            let info = bundle.infoDictionary,
            !isAgent(info["LSUIElement"]),
            !isAgent(info["LSBackgroundOnly"])
        else { return nil }
        let name =
            (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return Self(id: id, name: name, url: url)
    }
}

@MainActor
enum ApplicationCatalog {
    static var cached: [PickableApplication] = []
    static var refreshedAt = Date.distantPast

    static func installed() async -> [PickableApplication] {
        if Date().timeIntervalSince(refreshedAt) < 60 { return cached }
        let apps = await Task.detached(priority: .userInitiated) {
            var found: [String: PickableApplication] = [:]
            for path in [
                "/Applications", "/System/Applications", NSHomeDirectory() + "/Applications",
            ] {
                guard
                    let entries = FileManager.default.enumerator(
                        at: URL(fileURLWithPath: path),
                        includingPropertiesForKeys: [.isHiddenKey, .isSymbolicLinkKey],
                        options: [.skipsPackageDescendants])
                else { continue }
                while let url = entries.nextObject() as? URL {
                    let attributes = try? url.resourceValues(forKeys: [
                        .isHiddenKey, .isSymbolicLinkKey,
                    ])
                    if attributes?.isHidden == true {
                        let target = url.resolvingSymlinksInPath()
                        let targetAttributes = try? target.resourceValues(forKeys: [.isHiddenKey])
                        guard attributes?.isSymbolicLink == true, url.pathExtension == "app",
                            targetAttributes?.isHidden == false
                        else {
                            entries.skipDescendants()
                            continue
                        }
                    }
                    guard url.pathExtension == "app", let app = PickableApplication.read(url) else {
                        continue
                    }
                    if found[app.id] == nil { found[app.id] = app }
                }
            }
            return found.values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }.value
        cached = apps
        refreshedAt = Date()
        return apps
    }
}

struct ApplicationPicker: View {
    var subtitle = "Give its keys a different job in this layer."
    let choose: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var applications: [PickableApplication] = ApplicationCatalog.cached
    @State private var runningIDs = Set<String>()
    @State private var isLoading = true
    @FocusState private var searchFocused: Bool

    private var matches: [PickableApplication] {
        applications.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Choose an app").font(DS.Typography.title)
                    Text(subtitle)
                        .font(DS.Typography.label).foregroundStyle(DS.Ink.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(DS.Surface.raised, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel app selection")
            }
            .padding(24)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(DS.Ink.tertiary)
                TextField("Search apps", text: $search)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit {
                        if let app = matches.first(where: { runningIDs.contains($0.id) })
                            ?? matches.first
                        {
                            select(app)
                        }
                    }
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(DS.Ink.tertiary)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .font(DS.Typography.body)
            .padding(.horizontal, 12).frame(height: 38)
            .background(DS.Surface.raised, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10).strokeBorder(
                    searchFocused ? DS.Line.strong : DS.Line.hairline, lineWidth: 1)
            )
            .padding(.horizontal, 24).padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let running = matches.filter { runningIDs.contains($0.id) }
                    let other = matches.filter { !runningIDs.contains($0.id) }
                    if !running.isEmpty { appGroup("Running", apps: running) }
                    if !other.isEmpty {
                        appGroup(running.isEmpty ? "Applications" : "Other apps", apps: other)
                    }
                    if matches.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: isLoading ? "app.dashed" : "magnifyingglass")
                                .font(.system(size: 24))
                            Text(isLoading ? "Finding your apps…" : "No apps found")
                                .font(DS.Typography.label)
                            if !isLoading {
                                Text("Try another name or choose an app below.")
                                    .font(DS.Typography.footnote)
                            }
                        }
                        .foregroundStyle(DS.Ink.tertiary)
                        .frame(maxWidth: .infinity).padding(.vertical, 56)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            Rectangle().fill(DS.Line.hairline).frame(height: 1)
            HStack {
                Button("Choose from Finder…") { browse() }
                    .buttonStyle(.plain).font(DS.Typography.label)
                    .foregroundStyle(DS.Ink.secondary)
                Spacer()
                Text("Select an app to continue")
                    .font(DS.Typography.footnote).foregroundStyle(DS.Ink.tertiary)
            }
            .padding(.horizontal, 24).frame(height: 48)
        }
        .frame(width: 440, height: 510)
        .background(DS.Surface.window)
        .task {
            searchFocused = true
            let running = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular
            }
            runningIDs = Set(running.compactMap(\.bundleIdentifier))
            let runningURLs = running.compactMap(\.bundleURL)
            let installed = await ApplicationCatalog.installed()
            let additional = await Task.detached(priority: .userInitiated) {
                runningURLs.compactMap(PickableApplication.read)
            }.value
            guard !Task.isCancelled else { return }
            var unique = Dictionary(uniqueKeysWithValues: installed.map { ($0.id, $0) })
            for app in additional { unique[app.id] = app }
            applications = unique.values.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            isLoading = false
        }
    }

    private func appGroup(_ title: String, apps: [PickableApplication]) -> some View {
        Group {
            Text(title).sectionLabel().padding(.horizontal, 10).padding(.top, 12).padding(
                .bottom, 6)
            ForEach(apps) { app in
                Button {
                    select(app)
                } label: {
                    HStack(spacing: 12) {
                        ApplicationIcon(bundleID: app.id, size: 30, url: app.url)
                        Text(app.name).font(DS.Typography.body).lineLimit(1)
                        Spacer(minLength: 8)
                        Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Ink.tertiary)
                    }
                    .padding(.horizontal, 10).frame(height: 46)
                    .contentShape(RoundedRectangle(cornerRadius: DS.Radius.small))
                }
                .buttonStyle(ApplicationControlStyle())
                .help("Customize \(app.name)")
            }
        }
    }

    private func select(_ app: PickableApplication) { choose(app.url); dismiss() }

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.begin { response in
            if response == .OK, let url = panel.url { choose(url); dismiss() }
        }
    }
}

struct ApplicationControlStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        ApplicationControlSurface(
            label: configuration.label, pressed: configuration.isPressed,
            reduceMotion: reduceMotion)
    }
}

struct ApplicationControlSurface<Content: View>: View {
    let label: Content
    let pressed: Bool
    let reduceMotion: Bool
    @State private var hovered = false

    var body: some View {
        label
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .fill(.white.opacity(hovered ? 0.04 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: pressed)
            .onHover { hovered = $0 }
    }
}

extension MacAction {
    @MainActor var icon: NSImage? {
        switch self {
        case let .application(target): return ApplicationArtwork.icon(id: target.id)
        case .shortcut: return ApplicationArtwork.icon(id: "com.apple.shortcuts")
        case .url, .file: return nil
        }
    }
}
