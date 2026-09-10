import SwiftUI

struct ProfileHistoryView: View {
    @ObservedObject var model: AppModel
    let profileID: UUID
    let onClose: () -> Void

    var body: some View {
        ProfileHistoryBrowser(
            profile: model.profiles.first { $0.id == profileID },
            history: model.profileHistory(for: profileID),
            canRestore: model.license.hasProAccess,
            onRestore: { entry in
                guard model.restore(entry) else {
                    let message =
                        model.errorMessage
                        ?? "This version could not be restored. Check that this profile still exists and Pro is active in Settings."
                    model.errorMessage = nil
                    return message
                }
                return nil
            },
            onClose: onClose)
    }
}

struct ProfileHistoryBrowser: View {
    let profile: Profile?
    let history: Result<[ProfileHistoryEntry], ProfileHistoryError>
    var canRestore: Bool = true
    var initialEntryID: UUID?
    let onRestore: (ProfileHistoryEntry) -> String?
    let onClose: () -> Void

    private enum Selection: Hashable {
        case current
        case saved(UUID)
    }

    @State private var selection: Selection? = .current
    @State private var selectedApplicationID: String?
    @State private var selectedLayerID: UUID?
    @State private var selectedKey: String?
    @State private var pendingRestore: ProfileHistoryEntry?
    @State private var restoreError: String?
    @State private var status: String?
    @FocusState private var focusedVersion: Selection?

    private var entries: [ProfileHistoryEntry] {
        ((try? history.get()) ?? []).sorted { $0.savedAt > $1.savedAt }
    }

    private var selectedEntry: ProfileHistoryEntry? {
        guard case .saved(let id) = selection else { return nil }
        return entries.first { $0.id == id }
    }

    private var preview: Profile? { selectedEntry?.profile ?? profile }

    private var selectedLayer: Layer? {
        preview?.layers.first { $0.id == selectedLayerID }
            ?? preview?.triggeredLayers.first ?? preview?.baseLayer
    }

    private var changes: [ProfileHistoryChange] {
        guard let profile, let preview else { return [] }
        return ProfileHistoryComparison.changes(from: profile, to: preview)
    }

    private var matchesCurrent: Bool { preview == profile }

    private var dayGroups: [Date] {
        Set(entries.map { Calendar.current.startOfDay(for: $0.savedAt) }).sorted(by: >)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .windowPanel()
                .padding(.leading, DS.Metrics.windowInset)
                .padding(.vertical, DS.Metrics.windowInset)
            detail
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(DS.Surface.window)
        .foregroundStyle(DS.Ink.primary)
        .tint(DS.Selection.accent)
        .onAppear {
            if let id = initialEntryID ?? entries.first?.id { selection = .saved(id) }
            selectedLayerID = selectedLayer?.id
            focusedVersion = selection
        }
        .onChange(of: selection) { _, _ in
            selectedKey = nil
            status = nil
            if preview?.layers.contains(where: { $0.id == selectedLayerID }) != true {
                selectedLayerID = preview?.triggeredLayers.first?.id ?? preview?.baseLayer?.id
            }
        }
        .onChange(of: entries.map(\.id)) { _, ids in
            if case .saved(let id) = selection, !ids.contains(id) { selection = .current }
        }
        .confirmationDialog(
            "Restore this version of “\(profile?.name ?? "Profile")”?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } })
        ) {
            Button("Restore version", action: restore)
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        } message: {
            if let pendingRestore {
                Text(
                    "Restore the version saved \(pendingRestore.savedAt.formatted(date: .abbreviated, time: .shortened)). Your current version will be saved first."
                )
            }
        }
        .alert(
            "Could not restore version",
            isPresented: Binding(
                get: { restoreError != nil }, set: { if !$0 { restoreError = nil } })
        ) {
            Button("Close", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("History").font(DS.Typography.display)
                Text(profile?.name ?? "Profile unavailable")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Ink.secondary)
                    .lineLimit(1)
                    .help(profile?.name ?? "Profile unavailable")
            }
            .padding(.horizontal, 18)
            .padding(.top, DS.Metrics.titlebar)
            .padding(.bottom, 18)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        versionRow(
                            .current, title: "Current profile", subtitle: "Latest changes",
                            symbol: "keyboard")
                        ForEach(dayGroups, id: \.self) { day in
                            Text(dayLabel(day))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Ink.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 20)
                                .padding(.bottom, 5)
                            ForEach(
                                entries.filter {
                                    Calendar.current.isDate($0.savedAt, inSameDayAs: day)
                                }
                            ) { entry in
                                versionRow(
                                    .saved(entry.id),
                                    title: entry.savedAt.formatted(
                                        .dateTime.hour().minute().second()),
                                    subtitle: entrySummary(entry),
                                    symbol: entry.profile == profile ? "checkmark.circle" : "clock"
                                )
                                .help(
                                    entry.savedAt.formatted(date: .complete, time: .standard)
                                        + " · " + entrySummary(entry))
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
                .onChange(of: selection) { _, value in
                    if let value { proxy.scrollTo(value) }
                }
            }
            Spacer(minLength: 0)
            Text("Saved on this Mac · Up to 20 checkpoints")
                .help(
                    "Related edits share a checkpoint. A new checkpoint starts after 30 seconds idle, when you switch profiles or layers, or after five minutes of editing."
                )
                .font(.system(size: 10))
                .foregroundStyle(DS.Ink.secondary)
                .padding(18)
        }
        .frame(width: DS.Metrics.sidebarWidth)
        .navigationSurface()
        .onMoveCommand { direction in
            let options: [Selection] = [.current] + entries.map { .saved($0.id) }
            let index = options.firstIndex(of: selection ?? .current) ?? 0
            let next: Int
            switch direction {
            case .up: next = max(0, index - 1)
            case .down: next = min(options.count - 1, index + 1)
            default: return
            }
            selection = options[next]
            focusedVersion = selection
        }
    }

    private func versionRow(_ value: Selection, title: String, subtitle: String, symbol: String)
        -> some View
    {
        Button {
            selection = value
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(selection == value ? DS.Selection.accent : DS.Ink.secondary)
                    .frame(width: 16)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(DS.Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(DS.Ink.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, DS.Metrics.windowInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                selection == value ? DS.Selection.fill : .clear,
                in: RoundedRectangle(cornerRadius: DS.Radius.small)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedVersion, equals: value)
        .overlay {
            if focusedVersion == value {
                RoundedRectangle(cornerRadius: DS.Radius.small)
                    .strokeBorder(DS.Selection.accent.opacity(0.7), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityAddTraits(selection == value ? .isSelected : [])
        .id(value)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(
                        selectedEntry.map {
                            $0.savedAt.formatted(date: .abbreviated, time: .shortened)
                        } ?? "Current profile"
                    )
                    .font(DS.Typography.display)
                    Text(
                        selectedEntry == nil
                            ? "Your latest configuration" : "Saved version · Read only"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Ink.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Label("Back to editing", systemImage: "arrow.left")
                }
                .buttonStyle(RoundedActionStyle())
                .keyboardShortcut(.cancelAction)
                .font(.system(size: 12))
            }
            .padding(.horizontal, 24)
            .frame(height: DS.Space.small + DS.Metrics.header + DS.Metrics.windowInset)
            Divider()

            if profile == nil {
                stateView(
                    "Profile unavailable", symbol: "folder.badge.questionmark",
                    message:
                        "This profile was removed. Go back to editing to choose another profile.")
            } else if case .failure = history {
                stateView(
                    "History could not be read", symbol: "exclamationmark.triangle",
                    message:
                        "The saved data has been kept. Export your current profile from the profile menu as a backup, then contact support for help recovering history."
                )
                Link(
                    "Get help with history",
                    destination: URL(string: "https://github.com/notborges/tenuo-app/issues")!
                )
                .padding(.bottom, 24)
            } else if entries.isEmpty {
                stateView(
                    "No saved versions yet", symbol: "clock.arrow.circlepath",
                    message:
                        "As you edit this profile, Tenuo keeps earlier versions here. Return to your profile to make your first change."
                )
            } else {
                previewContent
                footer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if let preview, let selectedLayer {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Text("Keyboard preview")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            InspectorPicker(
                                title: selectedLayer.name,
                                selection: Binding(
                                    get: { self.selectedLayer?.id ?? selectedLayer.id },
                                    set: {
                                        selectedLayerID = $0; selectedKey = nil;
                                        selectedApplicationID = nil
                                    })
                            ) {
                                ForEach(preview.layers) { layer in Text(layer.name).tag(layer.id) }
                            }
                            .frame(width: Inspector.controlWidth)
                            .accessibilityLabel("Preview layer")
                        }
                        if !selectedLayer.applications.isEmpty || selectedApplicationID != nil {
                            Picker(
                                "Application",
                                selection: Binding(
                                    get: { selectedApplicationID },
                                    set: {
                                        selectedApplicationID = $0; selectedKey = nil
                                    })
                            ) {
                                Text("Default").tag(nil as String?)
                                ForEach(selectedLayer.applications.keys.sorted(), id: \.self) {
                                    id in
                                    Text(selectedLayer.applications[id]?.name ?? id).tag(
                                        Optional(id))
                                }
                                if let id = selectedApplicationID,
                                    selectedLayer.applications[id] == nil
                                {
                                    Text("Removed app · Default mappings").tag(Optional(id))
                                }
                            }
                        }
                        KeyboardLayoutView(
                            mappings: selectedLayer.mappings(for: selectedApplicationID),
                            inherited: inheritedMappings(for: selectedLayer, in: preview),
                            selected: selectedKey,
                            triggerName: selectedLayer.trigger?.displayLabel ?? "Base",
                            triggerKey: selectedLayer.trigger?.key,
                            isReadOnly: true,
                            changedKeys: Set(
                                changes.filter {
                                    $0.layerID == selectedLayer.id
                                        && $0.applicationID == selectedApplicationID
                                }.compactMap(\.key))
                        ) { key in selectedKey = selectedKey == key ? nil : key }
                        .frame(height: min(260, max(140, geometry.size.height - 320)))
                        .frame(maxWidth: 610)
                        .frame(maxWidth: .infinity)

                        keyDetail(in: preview, layer: selectedLayer)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                comparison
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

            }
        }
    }

    private func keyDetail(in profile: Profile, layer: Layer) -> some View {
        HStack(spacing: 8) {
            if let selectedKey {
                let inherited = inheritedMappings(for: layer, in: profile)[selectedKey]
                Text(KeyCatalog.key(named: selectedKey)?.displayName ?? selectedKey)
                    .foregroundStyle(DS.Ink.primary)
                    .fontWeight(.medium)
                Image(systemName: "arrow.right").font(.system(size: 9))
                Text(
                    ProfileHistoryComparison.mappingLabel(
                        layer.mappings(for: selectedApplicationID)[selectedKey] ?? inherited,
                        in: profile)
                )
                .textSelection(.enabled)
                Spacer(minLength: 4)
                Text(
                    layer.mappings(for: selectedApplicationID)[selectedKey] != nil
                        ? "Direct" : inherited != nil ? "Inherited" : "Unmapped")
            } else {
                Text("Select a key to inspect")
                Spacer()
                Label("Changed", systemImage: "diamond.fill")
                    .font(.system(size: 10))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(DS.Ink.secondary)
        .frame(minHeight: 18)
        .accessibilityElement(children: .combine)
    }

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(
                    selectedEntry == nil
                        ? "Compare a saved version" : "Restoring this version will…"
                )
                .font(.system(size: 14, weight: .semibold))
                Spacer()
                if selectedEntry != nil {
                    Text("\(changes.count) \(changes.count == 1 ? "change" : "changes")")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(DS.Surface.raised, in: Capsule())
                }
            }
            if selectedEntry == nil {
                Text("Choose a saved version to compare it with your current profile.")
                    .foregroundStyle(DS.Ink.secondary)
            } else if matchesCurrent {
                Label("No differences from your current profile", systemImage: "checkmark.circle")
                    .foregroundStyle(DS.Ink.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(changes) { change in
                                changeRow(change).id(change.id)
                                if change.id != changes.last?.id { Divider().opacity(0.5) }
                            }
                        }
                    }
                    .frame(maxHeight: CGFloat(changes.count) * 64)
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: selectedKey) { _, key in
                        if let change = changes.first(where: {
                            $0.key == key && $0.layerID == selectedLayerID
                        }) {
                            proxy.scrollTo(change.id)
                        }
                    }
                }
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .glassCard()
    }

    @ViewBuilder
    private func changeRow(_ change: ProfileHistoryChange) -> some View {
        let description = changeDescription(change)
        let row = HStack(alignment: .top, spacing: 12) {
            if change.key != nil {
                Keycap(label: change.title, width: 30, height: 30, legendSize: 11, isLit: true)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 30, height: 30)
                    .foregroundStyle(DS.Ink.secondary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(description.title)
                    .font(DS.Typography.body.weight(.medium))
                    .foregroundStyle(DS.Ink.primary)
                Text(description.detail)
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Ink.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if let layerID = change.layerID, let key = change.key,
            preview?.layers.contains(where: { $0.id == layerID }) == true
        {
            Button {
                selectedLayerID = layerID
                selectedApplicationID = change.applicationID
                selectedKey = key
            } label: {
                row
            }
            .buttonStyle(.plain)
            .background(
                selectedKey == key && selectedLayerID == layerID ? DS.Selection.fill : .clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .accessibilityLabel(
                "\(description.title). \(description.detail)"
            )
            .help("Inspect this key in the saved version")
        } else {
            row.textSelection(.enabled)
        }
    }

    private func changeDescription(_ change: ProfileHistoryChange) -> (
        title: String, detail: String
    ) {
        if change.applicationID != nil {
            return (
                "\(change.title): \(change.before) → \(change.after)", change.layerName ?? "Profile"
            )
        }
        let scope = change.layerName.map { "\($0) layer" } ?? "Profile"
        guard let key = change.key, let layerID = change.layerID else {
            if change.title == "Add layer" {
                return ("Add the “\(change.after)” layer", "Not in your current profile")
            }
            if change.title == "Remove layer" {
                return ("Remove the “\(change.before)” layer", "Its mappings will be removed too")
            }
            return (
                "Set \(change.title.lowercased()) to \(change.after)",
                "\(scope) · Currently: \(change.before)"
            )
        }
        let before = profile?.layers.first { $0.id == layerID }?.mappings[key]
        let after = preview?.layers.first { $0.id == layerID }?.mappings[key]
        func label(_ mapping: LayerMapping?, in profile: Profile?) -> String {
            if let binding = mapping?.binding {
                let parts =
                    binding.modifiers.map { $0.rawValue.capitalized }
                    + [KeyCatalog.key(named: binding.key)?.displayName ?? binding.key]
                return parts.joined(separator: " + ")
            }
            guard let profile else { return "Unassigned" }
            return ProfileHistoryComparison.mappingLabel(mapping, in: profile)
        }
        guard let after else {
            return (
                "Remove the mapping for \(change.title)",
                "\(scope) · Currently: \(label(before, in: profile))"
            )
        }
        let title: String
        switch after {
        case .blocked: title = "Block \(change.title)"
        case .transparent: title = "Let \(change.title) pass through to lower layers"
        case .action: title = "Map \(change.title) to \(label(after, in: preview))"
        }
        let detail =
            before == nil
            ? "No mapping assigned here yet" : "Currently: \(label(before, in: profile))"
        return (title, "\(scope) · \(detail)")
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 16) {
                Label(
                    status
                        ?? (canRestore
                            ? "Current version saved before restoring."
                            : "Activate Pro in Settings to restore a version."),
                    systemImage: status == nil ? "clock.arrow.circlepath" : "checkmark.circle"
                )
                .font(.system(size: 12))
                .foregroundStyle(DS.Ink.secondary)
                .accessibilityLabel(status ?? "Current version saved before restoring.")
                Spacer(minLength: 0)
                Button("Restore version…") { pendingRestore = selectedEntry }
                    .buttonStyle(RoundedActionStyle(prominent: true))
                    .disabled(selectedEntry == nil || matchesCurrent || !canRestore)
            }
            .padding(.horizontal, 28)
            .frame(height: DS.Metrics.footerHeight)
        }
    }

    private func stateView(_ title: String, symbol: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DS.Ink.secondary)
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(DS.Ink.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Back to editing", action: onClose)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func entrySummary(_ entry: ProfileHistoryEntry) -> String {
        guard let profile else { return "Saved version" }
        let differences = ProfileHistoryComparison.changes(from: profile, to: entry.profile)
        guard !differences.isEmpty else { return "Matches current profile" }
        let keys = differences.filter { $0.key != nil }.count
        let settings = differences.count - keys
        if keys == 0 {
            return
                "\(settings) \(settings == 1 ? "setting differs" : "settings differ") from current"
        }
        if settings == 0 {
            return "\(keys) \(keys == 1 ? "key differs" : "keys differ") from current"
        }
        return
            "\(keys) \(keys == 1 ? "key" : "keys") · \(settings) \(settings == 1 ? "setting differs" : "settings differ")"
    }

    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func inheritedMappings(for layer: Layer, in profile: Profile) -> [String: LayerMapping]
    {
        guard let index = profile.layers.firstIndex(where: { $0.id == layer.id }) else {
            return [:]
        }
        var mappings: [String: LayerMapping] = [:]
        for earlier in profile.layers.prefix(index) {
            for (key, mapping) in earlier.mappings(for: selectedApplicationID)
            where mapping != .transparent {
                mappings[key] = mapping
            }
        }
        for key in layer.mappings.keys { mappings.removeValue(forKey: key) }
        return mappings
    }

    private func restore() {
        guard let pendingRestore else { return }
        self.pendingRestore = nil
        if let error = onRestore(pendingRestore) {
            restoreError = error
        } else {
            selection = .current
            selectedKey = nil
            // Set after the selection observer clears the previous version's status.
            DispatchQueue.main.async {
                status = "Version restored. Previous version saved in History."
            }
            focusedVersion = selection
            NSAccessibility.post(
                element: NSApp.keyWindow as Any, notification: .announcementRequested,
                userInfo: [
                    .announcement: "Profile version restored",
                    .priority: NSAccessibilityPriorityLevel.medium.rawValue,
                ])
        }
    }
}

#if DEBUG
    struct ProfileHistoryPreview: View {
        @State private var profile = Presets.navigation
        @State private var entries: [ProfileHistoryEntry] = {
            var older = Presets.navigation
            older.layers[1].mappings["h"] = .action(
                .sendKey(KeyBinding(key: "leftArrow", modifiers: [.option])))
            older.layers[1].mappings["l"] = .action(
                .sendKey(KeyBinding(key: "rightArrow", modifiers: [.option])))
            let latest = ProfileHistoryEntry(
                profile: older, savedAt: .now.addingTimeInterval(-1200))
            older.layers[1].tapAction = nil
            older.layers[1].mappings["j"] = .blocked
            return [
                latest,
                ProfileHistoryEntry(profile: older, savedAt: .now.addingTimeInterval(-86400)),
            ]
        }()

        var body: some View {
            ProfileHistoryBrowser(
                profile: profile,
                history: ProcessInfo.processInfo.arguments.contains("--history-error")
                    ? .failure(.unreadable)
                    : .success(
                        ProcessInfo.processInfo.arguments.contains("--history-empty") ? [] : entries
                    ),
                initialEntryID: entries.first?.id,
                onRestore: { entry in
                    entries.insert(ProfileHistoryEntry(profile: profile, savedAt: .now), at: 0)
                    profile = entry.profile
                    return nil
                },
                onClose: { NSApp.keyWindow?.close() })
        }
    }
#endif
