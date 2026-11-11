import Foundation
import Testing
@testable import DevBroomCore

struct ItemListingTests {
    private func item(_ name: String, _ size: Int64, daysAgo: Double?, detail: String = "") -> CleanItem {
        CleanItem(id: "/p/\(name)", category: .projectBuilds, name: name, detail: detail, sizeBytes: size,
                  lastUsed: daysAgo.map { Date().addingTimeInterval(-$0 * 86_400) },
                  method: .trash(URL(fileURLWithPath: "/p/\(name)")), tags: [])
    }

    private var items: [CleanItem] {
        [item("beta", 10, daysAgo: 5), item("Alpha", 30, daysAgo: 90), item("gamma", 20, daysAgo: nil, detail: "~/code/weather")]
    }

    @Test func sortsBySizeLastUsedAndName() {
        #expect(arrange(items, by: .size).map(\.name) == ["Alpha", "gamma", "beta"])
        #expect(arrange(items, by: .lastUsed).map(\.name) == ["gamma", "Alpha", "beta"])  // never used counts as oldest
        #expect(arrange(items, by: .name).map(\.name) == ["Alpha", "beta", "gamma"])
    }

    @Test func searchMatchesNameDetailAndPathIgnoringCase() {
        #expect(arrange(items, by: .size, matching: "ALP").map(\.name) == ["Alpha"])
        #expect(arrange(items, by: .size, matching: "weather").map(\.name) == ["gamma"])
        #expect(arrange(items, by: .size, matching: "/p/be").map(\.name) == ["beta"])
        #expect(arrange(items, by: .size, matching: "  ").count == 3)
        #expect(arrange(items, by: .size, matching: "zzz").isEmpty)
    }

    @Test func hiddenItemsAreRemovedByExactId() {
        let r = CategoryResult(id: .projectBuilds, items: items, status: .fresh)
        let out = removingHidden(r, hidden: ["/p/beta", "/p/gam"])  // "/p/gam" is not an exact id: nothing else hidden
        #expect(out.items.map(\.name) == ["Alpha", "gamma"])
        #expect(out.status == .fresh)
    }
}
