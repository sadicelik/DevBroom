import Testing
import Foundation
@testable import DevBroomCore

let now = Date(timeIntervalSince1970: 1_800_000_000)
func item(_ c: CategoryID, daysAgo: Double?, tags: Set<ItemTag> = []) -> CleanItem {
    CleanItem(id: "x", category: c, name: "x", detail: "", sizeBytes: 1,
              lastUsed: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
              method: .trash(URL(fileURLWithPath: "/tmp/x")), tags: tags)
}

@Test func oldRebuildableIsTicked() { #expect(defaultTicked(item(.derivedData, daysAgo: 15), now: now, cutoffDays: 14)) }
@Test func recentRebuildableIsNotTicked() { #expect(!defaultTicked(item(.nodeModules, daysAgo: 13), now: now, cutoffDays: 14)) }
@Test func redownloadNeverTicked() {
    for c in [CategoryID.deviceSupport, .wallpaper, .simDevices, .simRuntimes, .docker] {
        #expect(!defaultTicked(item(c, daysAgo: 400), now: now, cutoffDays: 14))
    }
}
@Test func runningOrInUseNotTicked() {
    #expect(!defaultTicked(item(.appCaches, daysAgo: 100, tags: [.appRunning]), now: now, cutoffDays: 14))
    #expect(!defaultTicked(item(.simDevices, daysAgo: 100, tags: [.inUse]), now: now, cutoffDays: 14))
}
@Test func unknownLastUsedIsNotRecent() { #expect(!isRecentlyUsed(nil, now: now, cutoffDays: 14)) }
@Test func locationsUseInjectedHome() {
    let l = Locations(home: URL(fileURLWithPath: "/h"))
    #expect(l.derivedData.path == "/h/Library/Developer/Xcode/DerivedData")
    #expect(l.packageCaches.first?.url.path == "/h/.npm")
    #expect(l.wallpaperVideos.path == "/h/Library/Application Support/com.apple.wallpaper/aerials/videos")
}
