import SwiftUI

struct ContentView: View {
    @Environment(RadioPlayer.self) private var player
    @State private var liveChecker = YouTubeLiveChecker()

    var body: some View {
        #if os(tvOS)
        PlayerView()
        #else
        TabView {
            PlayerView()
                .tabItem { Label("Player", systemImage: "dot.radiowaves.left.and.right") }

            WebsiteView(url: player.station.websiteURL)
                .tabItem { Label("Webseite", systemImage: "globe") }

            NavigationStack {
                YouTubeLiveView(checker: liveChecker)
                    .navigationTitle("YouTube Live")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Live", systemImage: "play.rectangle.fill") }
            .badge(liveChecker.isLive ? "LIVE" : nil)

            LegalInfoView()
                .tabItem { Label("Info", systemImage: "info.circle") }
        }
        .tint(Color(red: 0.757, green: 0.184, blue: 0.212)) // #c12f36 Wein-Welle brand red
        .task {
            await liveChecker.checkLiveStatus()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(300))
                } catch {
                    return
                }
                await liveChecker.checkLiveStatus()
            }
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environment(RadioPlayer(station: .weinWelle))
}
