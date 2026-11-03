import AppKit
import DevBroomCore
import SwiftUI

extension CategoryID {
    var color: Color {
        switch self {
        case .derivedData: .blue
        case .packageCaches: .teal
        case .appCaches: .cyan
        case .nodeModules: .green
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
    /// Snapshot taken when the summary opens (spec section 4 rule 4): exactly these items are shown and cleaned.
    @State private var cleanSheet: (items: [CleanItem], recent: [String])?

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
            }
            .frame(height: 380)
            Divider()
            HStack {
                Button("Clean \(bytes(model.selectedBytes))") {
                    Task {
                        let recent = await model.recheckBeforeClean()
                        if model.isOpen { cleanSheet = (model.selectedItems, recent) }  // closed meanwhile: no summary
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selectedItems.isEmpty || model.isCleaning)
                Spacer()
                SettingsLink { Text("Settings") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
    }

    private var header: some View {
        HStack {
            if let free = model.freeBytes, let total = model.totalBytes {
                Text("\(bytes(total - free)) used · \(bytes(free)) free").font(.headline)
            }
            Spacer()
            if model.isScanning { ProgressView().controlSize(.small) }
            Button("Rescan") { model.rescan() }.disabled(model.isScanning)
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
                HStack(spacing: 0) {
                    ForEach(cats) { c in c.id.color.frame(width: g.size.width * Double(c.sizeBytes) / total) }
                    Color.gray.frame(width: g.size.width * other / total)
                    Color.gray.opacity(0.2)
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

    var body: some View {
        DisclosureGroup {
            ForEach(category.items) { ItemRow(model: model, item: $0) }
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
    }

    private var checkImage: String {
        let on = category.items.filter { model.selected.contains($0.id) }.count
        return on == 0 ? "square" : on == category.items.count ? "checkmark.square.fill" : "minus.square"
    }

    @ViewBuilder private var caption: some View {
        switch category.status {
        case .notUpdated: Text("not updated").font(.caption).foregroundStyle(.secondary)
        case .unavailable(let why): Text(why).font(.caption).foregroundStyle(.secondary)
        case .fresh: EmptyView()
        }
        if category.id.kind == .redownload, category.sizeBytes > 0 {
            Label("Re-download: \(bytes(category.sizeBytes))", systemImage: "exclamationmark.triangle")
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
    }

    private var details: String {
        var parts = [item.detail].filter { !$0.isEmpty }
        if let d = item.lastUsed { parts.append("\(Int(Date().timeIntervalSince(d) / 86_400))d ago") }
        let tags: [(ItemTag, String)] = [(.recentlyUsed, "recently used"), (.appRunning, "app is running"), (.inUse, "in use")]
        parts += tags.filter { item.tags.contains($0.0) }.map(\.1)
        return parts.joined(separator: " · ")
    }
}

private extension CategoryStatus {
    var isUnavailable: Bool { if case .unavailable = self { true } else { false } }
}
