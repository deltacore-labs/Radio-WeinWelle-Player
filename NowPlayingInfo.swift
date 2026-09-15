//
//  NowPlayingInfo.swift
//  Radio-WeinWelle-Player
//

import Foundation

struct NowPlayingInfo: Equatable, Sendable {
    var title: String
    var artist: String
    var artworkURL: URL?

    static let empty = NowPlayingInfo(title: "Radio Wein-Welle", artist: "", artworkURL: nil)
}
