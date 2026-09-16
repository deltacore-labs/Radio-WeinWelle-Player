import SwiftUI

struct ContentView: View {
    @Environment(RadioPlayer.self) private var player
    @Environment(\.scenePhase) private var scenePhase
    @State private var liveChecker = YouTubeLiveChecker()

    var body: some View {
        #if os(tvOS)
        PlayerView()
        #else
        TabView {
            Tab("Player", systemImage: "dot.radiowaves.left.and.right") {
                PlayerView()
            }
            Tab("Webseite", systemImage: "globe") {
                WebsiteView(url: player.station.websiteURL)
            }
            Tab("Live", systemImage: "play.rectangle.fill") {
                NavigationStack {
                    YouTubeLiveView(checker: liveChecker)
                        .navigationTitle("YouTube Live")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
            .badge(liveChecker.isLive ? Text("LIVE") : nil)
            Tab("Info", systemImage: "info.circle") {
                LegalInfoView()
            }
        }
        .tint(Color(red: 0.757, green: 0.184, blue: 0.212)) // #c12f36 Wein-Welle brand red
        .task {
            await liveChecker.checkLiveStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            guard liveChecker.lastChecked.map({ Date().timeIntervalSince($0) >= 300 }) ?? true else { return }
            Task { await liveChecker.checkLiveStatus() }
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environment(RadioPlayer(station: .weinWelle))
}
