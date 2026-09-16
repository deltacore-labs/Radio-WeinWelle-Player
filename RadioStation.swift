//
//  RadioStation.swift
//  Radio-WeinWelle-Player
//

import Foundation

struct RadioStation: Identifiable, Hashable, Sendable {
    let id = UUID()
    let name: String
    let streamURL: URL
    let websiteURL: URL

    /// Optionaler JSON-Endpunkt für "Now Playing"-Infos (z.B. AzuraCast).
    let nowPlayingURL: URL?

    /// Optionale HTML-Playlist-Seite als Fallback für Metadaten.
    let playlistURL: URL?
}

extension RadioStation {
    static let weinWelle = RadioStation(
        name: "Radio Wein-Welle",
        streamURL: URL(string: "https://stream.radio-wein-welle.de/radioweinwelle_high")!,
        websiteURL: URL(string: "https://www.radio-wein-welle.de")!,
        nowPlayingURL: URL(string: "https://stream.radio-wein-welle.de/status-json.xsl"),
        playlistURL: URL(string: "https://www.radio-wein-welle.de/playlist")
    )
}
