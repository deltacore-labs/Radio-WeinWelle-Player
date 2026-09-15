//
//  ContentView.swift
//  Radio-WeinWelle-Player
//

import SwiftUI

struct ContentView: View {
    @Environment(RadioPlayer.self) private var player

    var body: some View {
        TabView {
            PlayerView()
                .tabItem { Label("Player", systemImage: "dot.radiowaves.left.and.right") }

            WebsiteView(url: player.station.websiteURL)
                .tabItem { Label("Webseite", systemImage: "globe") }

            LegalInfoView()
                .tabItem { Label("Info", systemImage: "info.circle") }
        }
        .tint(Color(red: 0.757, green: 0.184, blue: 0.212)) // #c12f36 Wein-Welle brand red
    }
}

#Preview {
    ContentView()
        .environment(RadioPlayer(station: .weinWelle))
}
