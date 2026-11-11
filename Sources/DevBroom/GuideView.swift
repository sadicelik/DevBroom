import SwiftUI

/// First-run guide: three short cards, shown once (Settings → Show guide again brings it back).
struct GuideView: View {
    var recentDays = 14
    let done: () -> Void
    @State private var page = 0

    private var cards: [(symbol: String, title: String, text: String)] { [
        ("arrow.triangle.2.circlepath", "Rebuilds vs Re-download",
         "Rebuilds rows come back on their own, so old ones start ticked. Re-download rows (simulators, models, emulators) must be downloaded again later: they show an orange warning and are never ticked for you."),
        ("trash", "Most things go to the Trash first",
         "Clean moves most items to the Trash, so you can put them back. Simulators and Docker are removed for good, and DevBroom asks again first. To get Trash space back now, press Delete from Trash now after a clean: it deletes only what DevBroom just moved."),
        ("clock", "Recent work is left alone",
         "Anything used in the last \(recentDays) days starts unticked and is tagged recently used. Right-click an item to reveal it in Finder or hide it from DevBroom."),
    ] }

    var body: some View {
        let card = cards[page]
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to DevBroom").font(.headline)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: card.symbol).font(.system(size: 28)).foregroundStyle(.tint).frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title).font(.title3.weight(.semibold))
                    Text(card.text).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary)
                }
            }
            HStack {
                ForEach(cards.indices, id: \.self) { i in
                    Circle().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                }
                Spacer()
                if page < cards.count - 1 {
                    Button("Skip", action: done)
                    Button("Next") { page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Got it", action: done).keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
