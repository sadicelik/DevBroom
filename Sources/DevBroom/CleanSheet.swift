import DevBroomCore
import SwiftUI

/// Spec section 10: summary, confirm (second confirmation for permanent deletes), progress, result.
struct CleanSheet: View {
    let model: AppModel
    let items: [CleanItem]
    let recentlyUnticked: [String]
    let dismiss: () -> Void

    @State private var understood = false

    var body: some View {
        let trash = items.filter { !$0.method.isPermanent }
        let permanent = items.filter(\.method.isPermanent)
        VStack(alignment: .leading, spacing: 10) {
            if let report = model.lastReport {
                result(report)
                Button("Done") { model.lastReport = nil; dismiss() }.keyboardShortcut(.defaultAction)
            } else if model.isCleaning {
                let p = model.cleanProgress ?? (0, items.count)
                ProgressView("Cleaning \(p.done) of \(p.total)", value: Double(p.done), total: Double(max(p.total, 1)))
            } else {
                if !recentlyUnticked.isEmpty {
                    Text("Recently used, unticked: " + recentlyUnticked.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !trash.isEmpty {
                            section("Moves to Trash", trash, color: .primary)
                            Text("Space comes back when you empty the Trash.").font(.caption).foregroundStyle(.secondary)
                        }
                        if !permanent.isEmpty { section("Deleted permanently", permanent, color: .red) }
                    }
                }
                .frame(maxHeight: 360)
                if !permanent.isEmpty {
                    Toggle("I understand these are deleted permanently", isOn: $understood).toggleStyle(.checkbox)
                }
                HStack {
                    Button("Cancel", action: dismiss).keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Confirm") { model.clean(items) }
                    .buttonStyle(.borderedProminent)
                    .disabled(items.isEmpty || model.isCleaning || (!permanent.isEmpty && !understood))
                }
            }
        }
    }

    private func section(_ title: String, _ items: [CleanItem], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(bytes(items.reduce(0) { $0 + $1.sizeBytes })).font(.headline).monospacedDigit()
            }
            ForEach(items) { item in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).lineLimit(1)
                        if !item.detail.isEmpty {
                            Text(item.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    Spacer()
                    Text(bytes(item.sizeBytes)).monospacedDigit()
                }
                .font(.caption)
            }
        }
        .foregroundStyle(color)
    }

    @ViewBuilder private func result(_ r: CleanReport) -> some View {
        Text("Moved \(bytes(r.trashedBytes)) to Trash · Deleted \(bytes(r.deletedBytes)) permanently")
        if case .deleted = r.outcomes["docker"] {
            Text("Docker: space returns within a few minutes").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(r.failures.indices, id: \.self) { i in
            Text("\(r.failures[i].name): \(r.failures[i].reason)").font(.caption).foregroundStyle(.red)
        }
    }
}
