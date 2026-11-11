import AppKit
import DevBroomCore
import SwiftUI

extension CategoryID {
    var color: Color {
        switch self {
        case .derivedData: .blue
        case .xcodeExtras: Color(red: 0.45, green: 0.6, blue: 1.0)
        case .androidEmulators: Color(red: 0.24, green: 0.86, blue: 0.52)
        case .packageCaches: .teal
        case .appCaches: .cyan
        case .nodeModules: .green
        case .projectBuilds: .mint
        case .aiModels: .red
        case .oldExtensions: .yellow
        case .deviceSupport: .indigo
        case .wallpaper: .purple
        case .simDevices: .orange
        case .simRuntimes: .pink
        case .docker: .brown
        }
    }
}

struct PopoverView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings
    /// Snapshot taken when the summary opens (spec section 4 rule 4): exactly these items are shown and cleaned.
    @State private var cleanSheet: (items: [CleanItem], recent: [String])?
    /// Height of the category list's content, so the panel fits it (up to a maximum) instead of a fixed size.
    @State private var listHeight: CGFloat = 300
    @State private var preparing = false

    var body: some View {
        // VStack, not Group: Group would forward onAppear/onDisappear to each swapped child.
        VStack {
            // A clean in progress or an undismissed report takes over the popover, also after reopening.
            if let sheet = cleanSheet ?? (model.isCleaning || model.lastReport != nil ? ([], []) : nil) {
                CleanSheet(model: model, items: sheet.items, recentlyUnticked: sheet.recent) { cleanSheet = nil }
            } else {
                main
            }
        }
        .padding(12)
        .frame(width: 400)
        .onAppear { model.popoverOpened() }
        .onDisappear {
            cleanSheet = nil
            model.popoverClosed()
        }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            StorageBar(model: model)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(model.results) { CategoryRow(model: model, category: $0) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(listHeight, 520))
            Divider()
            HStack {
                Button("Clean \(bytes(model.selectedBytes))") {
                    guard !preparing, cleanSheet == nil else { return }  // ⌘⏎ key repeat: prepare the summary once
                    preparing = true
                    Task {
                        let recent = await model.recheckBeforeClean()
                        preparing = false
                        if model.isOpen, cleanSheet == nil { cleanSheet = (model.selectedItems, recent) }  // closed meanwhile: no summary
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)  // opens the summary; nothing is removed before Confirm
                .disabled(model.selectedItems.isEmpty || model.isCleaning || preparing)
                Spacer()
                Button("Settings") {
                    openSettings()
                    SettingsWindow.bringToFront()
                }
                .keyboardShortcut(",", modifiers: .command)
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if let free = model.freeBytes, let total = model.totalBytes {
                    Text("\(bytes(total - free)) used · \(bytes(free)) free").font(.headline)
                }
                HStack(spacing: 6) {
                    if model.selectedBytes > 0 {
                        Text("\(bytes(model.selectedBytes)) ready to clean").foregroundStyle(.tint)
                    }
                    scannedText
                }
                .font(.caption)
            }
            Spacer()
            if model.isScanning { ProgressView().controlSize(.small) }
            Button("Rescan") { model.rescan() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isScanning)
        }
    }

    private static let ago: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    @ViewBuilder private var scannedText: some View {
        if model.isScanning {
            Text("Scanning…").foregroundStyle(.secondary)
        } else if let date = model.lastScanned {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text("Scanned " + (date > context.date.addingTimeInterval(-60) ? "just now"
                    : Self.ago.localizedString(for: date, relativeTo: context.date)))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StorageBar: View {
    let model: AppModel

    var body: some View {
        let total = Double(max(model.totalBytes ?? 1, 1))
        let free = Double(model.freeBytes ?? 0)
        let cats = model.results.filter { $0.sizeBytes > 0 }
        let other = max(total - free - Double(cats.reduce(0) { $0 + $1.sizeBytes }), 0)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                // Ticked part of each category solid, the rest faded; the line marks where free space ends after cleaning.
                HStack(spacing: 0) {
                    ForEach(cats) { c in
                        let on = Double(c.items.filter { model.selected.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes })
                        c.id.color.frame(width: g.size.width * on / total)
                        c.id.color.opacity(0.35).frame(width: g.size.width * (Double(c.sizeBytes) - on) / total)
                    }
                    Color.gray.frame(width: g.size.width * other / total)
                    Color.gray.opacity(0.2)
                }
                .overlay(alignment: .leading) {
                    if model.selectedBytes > 0 {
                        Rectangle().fill(.primary).frame(width: 2)
                            .offset(x: g.size.width * max(total - free - Double(model.selectedBytes), 0) / total - 1)
                    }
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 2) {
                ForEach(cats) { legend($0.id.color, $0.id.title) }
                legend(.gray, "Other")
                legend(.gray.opacity(0.2), "Free")
            }
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            color.frame(width: 8, height: 8).clipShape(RoundedRectangle(cornerRadius: 2))
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct CategoryRow: View {
    let model: AppModel
    let category: CategoryResult
    @State private var sort: ItemSort = .size
    @State private var query = ""

    var body: some View {
        DisclosureGroup {
            if !category.items.isEmpty {
                HStack {
                    Picker("Sort", selection: $sort) {
                        ForEach(ItemSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu).fixedSize()
                    if category.items.count > 10 {
                        TextField("Search", text: $query).textFieldStyle(.roundedBorder)
                    }
                }
                .controlSize(.small)
            }
            let shown = arrange(category.items, by: sort, matching: category.items.count > 10 ? query : "")
            ForEach(shown) { ItemRow(model: model, item: $0) }
            if shown.isEmpty, !category.items.isEmpty {
                Text("No matches").font(.caption).foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 6) {
                category.id.color.frame(width: 10, height: 10).clipShape(RoundedRectangle(cornerRadius: 2))
                Button { model.toggle(category: category) } label: { Image(systemName: checkImage) }
                    .buttonStyle(.plain)
                    .disabled(category.items.isEmpty)
                    .accessibilityLabel("Select all in \(category.id.title)")
                VStack(alignment: .leading, spacing: 1) {
                    Text(category.id.title)
                    caption
                }
                Spacer()
                Text(bytes(category.sizeBytes)).monospacedDigit()
            }
            .opacity(category.status.isUnavailable ? 0.5 : 1)
        }
        // A search typed while the row was large must not come back filtering later.
        .onChange(of: category.items.count > 10) { _, searchable in if !searchable { query = "" } }
    }

    private var checkImage: String {
        let on = category.items.filter { model.selected.contains($0.id) }.count
        return on == 0 ? "square" : on == category.items.count ? "checkmark.square.fill" : "minus.square"
    }

    @ViewBuilder private var caption: some View {
        if !category.items.isEmpty {
            Text(category.items.count == 1 ? "1 item" : "\(category.items.count) items")
                .font(.caption).foregroundStyle(.secondary)
        }
        switch category.status {
        case .notUpdated: Text("not updated").font(.caption).foregroundStyle(.secondary)
        case .unavailable(let why): Text(why).font(.caption).foregroundStyle(.secondary)
        case .fresh: EmptyView()
        }
        let redownload = category.items.filter { $0.kind == .redownload }.reduce(Int64(0)) { $0 + $1.sizeBytes }
        if redownload > 0 {
            Label("Re-download: \(bytes(redownload))", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        }
    }
}

private struct ItemRow: View {
    let model: AppModel
    let item: CleanItem

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: Binding(get: { model.selected.contains(item.id) }, set: { _ in model.toggle(item: item) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).lineLimit(1)
                    Text(details).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            Text(bytes(item.sizeBytes)).monospacedDigit().foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .contextMenu {
            if case .trash(let url) = item.method {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Button("Hide from DevBroom") { model.hide(item) }
        }
    }

    private var details: String {
        var parts = [item.detail].filter { !$0.isEmpty }
        if let d = item.lastUsed { parts.append("\(Int(Date().timeIntervalSince(d) / 86_400))d ago") }
        let tags: [(ItemTag, String)] = [(.recentlyUsed, "recently used"), (.appRunning, "app is running"), (.inUse, "in use")]
        if item.kind == .redownload, item.category.kind == .rebuilds { parts.append("re-download") }
        parts += tags.filter { item.tags.contains($0.0) }.map(\.1)
        return parts.joined(separator: " · ")
    }
}

private extension CategoryStatus {
    var isUnavailable: Bool { if case .unavailable = self { true } else { false } }
}
