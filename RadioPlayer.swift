//
//  RadioPlayer.swift
//  Radio-WeinWelle-Player
//

import Foundation
import AVFoundation
import MediaPlayer
import NowPlaying
import ShazamKit
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
@Observable
final class RadioPlayer: NSObject {
    enum PlaybackState: Equatable {
        case idle
        case buffering
        case playing
        case paused
        case failed(String)
    }

    let station: RadioStation
    nonisolated let id: String  // MediaSessionRepresentable
    private(set) var state: PlaybackState = .idle
    private(set) var nowPlaying: NowPlayingInfo = .empty

    private var player: AVPlayer?
    private var metadataOutput: AVPlayerItemMetadataOutput?
    private var statusObservation: NSKeyValueObservation?
    private var pollingTask: Task<Void, Never>?

    @ObservationIgnored private var shazamRecognizer: ShazamRecognizer?
    @ObservationIgnored private var shazamTimerTask: Task<Void, Never>?
    @ObservationIgnored private var hasStreamMetadata = false
    @ObservationIgnored private var lastArtworkKey = ""

    @ObservationIgnored private var _mediaSession: AnyObject?

    @available(iOS 27, macOS 27, *)
    private var mediaSession: MediaSession<RadioPlayer>? {
        get { _mediaSession as? MediaSession<RadioPlayer> }
        set { _mediaSession = newValue }
    }

    init(station: RadioStation) {
        self.station = station
        self.id = station.id.uuidString
        super.init()
        nowPlaying = NowPlayingInfo(title: station.name, artist: "", artworkURL: nil)
        print("[Player] init – Station: \(station.name), Stream: \(station.streamURL)")
        configureAudioSession()
        setupInterruptionHandling()
        if #available(iOS 27, macOS 27, *) {
            mediaSession = MediaSession(self)
            print("[Player] MediaSession (iOS 27) erstellt")
        } else {
            configureRemoteCommandsLegacy()
            print("[Player] Legacy-RemoteCommands konfiguriert")
        }
    }

    deinit {
        #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        NotificationCenter.default.removeObserver(self)
        #endif
    }

    // MARK: - Steuerung

    func togglePlayPause() {
        switch state {
        case .playing, .buffering:
            pause()
        default:
            play()
        }
    }

    func play() {
        print("[Player] play() – aktueller State: \(state)")
        if case .failed = state { tearDownPlayer() }
        configureAudioSession()
        if player == nil { setUpPlayer() }
        player?.play()
        state = player?.currentItem?.status == .readyToPlay ? .playing : .buffering
        print("[Player] State nach play(): \(state)")
        hasStreamMetadata = false
        lastArtworkKey = ""
        startPolling()
        startShazamTimerIfNeeded()
        if #available(iOS 27, macOS 27, *) {
            Task {
                try? await mediaSession?.requestToBecomeApplicationPrimary()
                #if os(iOS)
                try? await mediaSession?.requestToBecomeSystemPrimary()
                #endif
            }
        } else {
            updateNowPlayingCenterLegacy()
        }
    }

    func pause() {
        print("[Player] pause()")
        player?.pause()
        state = .paused
        stopPolling()
        stopShazam()
        if #available(iOS 27, macOS 27, *) {
            // MediaSession beobachtet state-Änderungen automatisch über @Observable
        } else {
            updateNowPlayingCenterLegacy()
        }
    }

    // MARK: - Player-Setup

    private func setUpPlayer() {
        print("[Player] AVPlayer wird aufgebaut – URL: \(station.streamURL)")
        let item = AVPlayerItem(url: station.streamURL)

        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(self, queue: .main)
        item.add(output)
        metadataOutput = output

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    guard case .buffering = self.state else { break }
                    self.player?.play()
                    self.state = .playing
                    print("[Player] AVPlayerItem readyToPlay → state = .playing")
                    if #available(iOS 27, macOS 27, *) {
                        // automatisch
                    } else {
                        self.updateNowPlayingCenterLegacy()
                    }
                case .failed:
                    let msg = item.error?.localizedDescription ?? "Unbekannter Fehler"
                    print("[Player] AVPlayerItem failed: \(msg)")
                    self.state = .failed(msg)
                default:
                    break
                }
            }
        }

        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        self.player = avPlayer
    }

    private func tearDownPlayer() {
        print("[Player] tearDownPlayer()")
        stopPolling()
        stopShazam()
        statusObservation = nil
        player?.pause()
        player = nil
        metadataOutput = nil
    }

    private func configureAudioSession() {
        #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            print("[Player] AudioSession → .playback, aktiv")
        } catch {
            print("[Player] AudioSession-Fehler: \(error)")
        }
        #endif
    }

    private func setupInterruptionHandling() {
        #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        #endif
    }

    #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
    @objc private nonisolated func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        Task { @MainActor in
            switch type {
            case .began:
                print("[Player] Unterbrechung begonnen – Player pausiert")
                if self.state == .playing || self.state == .buffering {
                    self.state = .paused
                }
            case .ended:
                let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                print("[Player] Unterbrechung beendet – shouldResume: \(options.contains(.shouldResume))")
                if options.contains(.shouldResume), self.state == .paused {
                    self.play()
                }
            @unknown default:
                break
            }
        }
    }
    #endif

    // MARK: - Legacy: MPRemoteCommandCenter / MPNowPlayingInfoCenter (iOS < 27)

    private func configureRemoteCommandsLegacy() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
    }

    private func updateNowPlayingCenterLegacy() {
        let isActive = state == .playing || state == .buffering
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.artist,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isActive ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkLegacy()
    }

    private func loadArtworkLegacy() {
        if let url = nowPlaying.artworkURL {
            Task {
                if let (data, _) = try? await URLSession.shared.data(from: url),
                   let image = PlatformImage(data: data) {
                    setArtworkLegacy(image)
                }
            }
        } else {
            #if canImport(UIKit)
            if let image = UIImage(named: "logo") { setArtworkLegacy(image) }
            #endif
        }
    }

    private func setArtworkLegacy(_ image: PlatformImage) {
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - ShazamKit (Fallback-Erkennung wenn kein Stream-Titel)

    private func startShazamTimerIfNeeded() {
        print("[Shazam] Timer gestartet – Shazam startet in 15 s, falls kein Stream-Titel kommt")
        shazamTimerTask?.cancel()
        shazamTimerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else {
                print("[Shazam] Timer abgebrochen (Task cancelled oder self nil)")
                return
            }
            guard !self.hasStreamMetadata else {
                print("[Shazam] Timer abgelaufen – Stream hat Metadaten geliefert, Shazam nicht nötig")
                return
            }
            guard let currentItem = self.player?.currentItem else {
                print("[Shazam] Kein AVPlayerItem – Shazam nicht möglich")
                return
            }
            print("[Shazam] Timer abgelaufen – kein Stream-Titel, starte Stream-Shazam")
            let recognizer = ShazamRecognizer()
            recognizer.onMatch = { [weak self] artist, title, artworkURL in
                guard let self, !self.hasStreamMetadata else {
                    print("[Shazam] Match ignoriert – Stream hat inzwischen Metadaten")
                    return
                }
                guard self.nowPlaying.artist != artist || self.nowPlaying.title != title else {
                    print("[Shazam] Match ignoriert – identisch mit aktuellem Titel")
                    return
                }
                print("[Shazam] Match: \(artist) – \(title), Artwork: \(artworkURL?.absoluteString ?? "nil")")
                self.nowPlaying.artist = artist
                self.nowPlaying.title = title
                self.nowPlaying.artworkURL = artworkURL
                self.stopShazam()
                Task { await self.fetchArtwork(artist: artist, title: title) }
                if #available(iOS 27, macOS 27, *) {} else {
                    self.updateNowPlayingCenterLegacy()
                }
            }
            self.shazamRecognizer = recognizer
            recognizer.start(with: currentItem)
        }
    }

    private func stopShazam() {
        guard shazamRecognizer != nil || shazamTimerTask != nil else { return }
        print("[Shazam] stopShazam()")
        shazamTimerTask?.cancel()
        shazamTimerTask = nil
        shazamRecognizer?.stop()
        shazamRecognizer = nil
    }

    // MARK: - iTunes Cover-Art-Lookup

    private func fetchArtwork(artist: String, title: String) async {
        let key = "\(artist)|\(title)"
        guard !artist.isEmpty, !title.isEmpty, key != lastArtworkKey else { return }
        lastArtworkKey = key
        let query = "\(artist) \(title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://itunes.apple.com/search?term=\(query)&media=music&limit=1&country=DE"
        print("[iTunes] Artwork-Suche: \(artist) – \(title)")
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let result = try? JSONDecoder().decode(iTunesSearchResult.self, from: data),
              let track = result.results.first else {
            print("[iTunes] Kein Artwork-Ergebnis gefunden")
            return
        }
        let highRes = track.artworkUrl100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        print("[iTunes] Artwork gefunden: \(highRes)")
        nowPlaying.artworkURL = URL(string: highRes)
        if #available(iOS 27, macOS 27, *) {} else {
            updateNowPlayingCenterLegacy()
        }
    }

    // MARK: - Icecast-API-Polling

    private func startPolling() {
        guard station.nowPlayingURL != nil else {
            print("[Icecast] Kein nowPlayingURL konfiguriert – Polling deaktiviert")
            return
        }
        print("[Icecast] Polling gestartet (alle 15 s) → \(station.nowPlayingURL!)")
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetchIcecastMetadata()
                try? await Task.sleep(for: .seconds(15))
            }
            print("[Icecast] Polling-Task beendet")
        }
    }

    private func stopPolling() {
        guard pollingTask != nil else { return }
        print("[Icecast] Polling gestoppt")
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func fetchIcecastMetadata() async {
        guard let apiURL = station.nowPlayingURL else { return }
        print("[Icecast] Hole Metadaten von \(apiURL)")
        guard let (data, _) = try? await URLSession.shared.data(from: apiURL) else {
            if !Task.isCancelled {
                print("[Icecast] Netzwerkfehler – keine Antwort")
            }
            return
        }
        guard let status = try? JSONDecoder().decode(IcecastStatus.self, from: data) else {
            let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? "<leer>"
            print("[Icecast] JSON-Decode fehlgeschlagen. Antwort: \(raw)")
            return
        }

        let streamPath = station.streamURL.path
        let source = status.icestats.source?.first {
            $0.listenurl?.hasSuffix(streamPath) == true
        } ?? status.icestats.source?.first

        guard let rawTitle = source?.title, !rawTitle.isEmpty else {
            print("[Icecast] Kein Titel in der API-Antwort (listenurl: \(source?.listenurl ?? "nil"))")
            return
        }

        let decoded = fixEncoding(rawTitle)
        print("[Icecast] Rohtitel: \"\(rawTitle)\" → dekodiert: \"\(decoded)\"")

        let parts = decoded.components(separatedBy: " - ")
        guard parts.count >= 2 else {
            print("[Icecast] Kein Trennzeichen ' - ' im Titel – kein Song-Metadatum")
            return
        }

        let artist = parts[0]
        let songTitle = parts[1...].joined(separator: " - ")

        guard artist.caseInsensitiveCompare(station.name) != .orderedSame else {
            print("[Icecast] Promo-Text erkannt (Künstler = Sendername '\(artist)') – ignoriert")
            return
        }

        print("[Icecast] Song erkannt: \(artist) – \(songTitle)")
        nowPlaying.artist = artist
        nowPlaying.title = songTitle
        hasStreamMetadata = true
        stopShazam()
        await fetchArtwork(artist: nowPlaying.artist, title: nowPlaying.title)
        if #available(iOS 27, macOS 27, *) {
            // automatisch
        } else {
            updateNowPlayingCenterLegacy()
        }
    }

    /// Icecast-Server kodieren den Titel manchmal als UTF-8, lesen ihn aber
    /// als Latin-1 zurück — dadurch entsteht doppelt enkodierter Text ("Mojibake").
    /// Diese Funktion macht den Fehler rückgängig.
    private func fixEncoding(_ string: String) -> String {
        guard let bytes = string.data(using: .isoLatin1) else { return string }
        return String(data: bytes, encoding: .utf8) ?? string
    }
}

// MARK: - NowPlaying Framework (iOS 27 / macOS 27+)

@available(iOS 27, macOS 27, *)
@MainActor
extension RadioPlayer: MediaSessionRepresentable {

    var content: (any MediaContentRepresentable)? {
        let artworkObj: Artwork? = {
            if let url = nowPlaying.artworkURL {
                return Artwork(id: url.absoluteString) { _ in
                    let (data, _) = try await URLSession.shared.data(from: url)
                    return try ArtworkRepresentation(data: data)
                }
            }
            #if canImport(UIKit)
            return Artwork(id: "station-logo") { _ in
                guard let image = UIImage(named: "logo"),
                      let data = image.pngData() else { throw CocoaError(.fileNoSuchFile) }
                return try ArtworkRepresentation(data: data)
            }
            #else
            return nil
            #endif
        }()
        let program: String? = {
            if !nowPlaying.artist.isEmpty {
                return "\(nowPlaying.artist) – \(nowPlaying.title)"
            }
            return nowPlaying.title != station.name ? nowPlaying.title : nil
        }()
        return RadioContent(
            id: station.id.uuidString,
            stationName: station.name,
            programName: program,
            artwork: artworkObj
        )
    }

    var playbackSnapshot: MediaPlaybackSnapshot? {
        switch state {
        case .playing:
            return MediaPlaybackSnapshot(state: .playing(rate: 1.0))
        case .buffering:
            return MediaPlaybackSnapshot(state: .buffering)
        case .paused:
            return MediaPlaybackSnapshot(state: .paused)
        case .idle, .failed:
            return MediaPlaybackSnapshot(state: .stopped)
        }
    }

    var commands: [MediaCommand] {
        switch state {
        case .playing, .buffering:
            return [
                .pause { [weak self] in self?.pause() },
                .togglePlayPause { [weak self] in self?.togglePlayPause() }
            ]
        default:
            return [
                .play { [weak self] in self?.play() },
                .togglePlayPause { [weak self] in self?.togglePlayPause() }
            ]
        }
    }
}

// MARK: - ICY-Metadaten

extension RadioPlayer: AVPlayerItemMetadataOutputPushDelegate {
    nonisolated func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                                    didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                                    from track: AVPlayerItemTrack?) {
        let items = groups.flatMap { $0.items }
        Task { @MainActor in
            for meta in items {
                if let value = try? await meta.load(.stringValue) {
                    let fixed = fixEncoding(value)
                    print("[ICY] Stream-Metadatum empfangen: \"\(fixed)\"")

                    let parts = fixed.components(separatedBy: " - ")
                    guard parts.count >= 2 else {
                        print("[ICY] Kein Trennzeichen ' - ' – ignoriert")
                        continue
                    }
                    let artist = parts[0]
                    let songTitle = parts[1...].joined(separator: " - ")

                    guard artist.caseInsensitiveCompare(self.station.name) != .orderedSame else {
                        print("[ICY] Promo-Text erkannt (Künstler = Sendername '\(artist)') – ignoriert")
                        continue
                    }

                    print("[ICY] Song gesetzt: \(artist) – \(songTitle)")
                    self.nowPlaying.artist = artist
                    self.nowPlaying.title = songTitle
                    self.hasStreamMetadata = true
                    self.stopShazam()
                    await self.fetchArtwork(artist: artist, title: songTitle)
                    if #available(iOS 27, macOS 27, *) {
                        // automatisch
                    } else {
                        self.updateNowPlayingCenterLegacy()
                    }
                }
            }
        }
    }
}

// MARK: - Icecast-JSON-Modell

private struct IcecastStatus: Decodable {
    struct Source: Decodable {
        let listenurl: String?
        let title: String?
    }
    struct Stats: Decodable {
        let source: [Source]?
    }
    let icestats: Stats
}

private struct iTunesSearchResult: Decodable {
    struct Track: Decodable { let artworkUrl100: String }
    let results: [Track]
}

// MARK: - Preview Helper

#if DEBUG
extension RadioPlayer {
    static func makePreview(
        title: String = "Rote Lippen soll man küssen",
        artist: String = "Cindy & Bert",
        state: PlaybackState = .playing
    ) -> RadioPlayer {
        let p = RadioPlayer(station: .weinWelle)
        p.nowPlaying = NowPlayingInfo(title: title, artist: artist, artworkURL: nil)
        p.state = state
        return p
    }
}
#endif
