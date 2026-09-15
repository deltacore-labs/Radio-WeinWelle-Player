//
//  Radio_WeinWelle_PlayerApp.swift
//  Radio-WeinWelle-Player
//
//  Created by Friedrich, Stefan on 15.09.26.
//

import SwiftUI

@main
struct Radio_WeinWelle_PlayerApp: App {
    @State private var player = RadioPlayer(station: .weinWelle)

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(player)
        }
    }
}
