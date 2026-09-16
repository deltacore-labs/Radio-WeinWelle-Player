//
//  RadioPlayer.swift
//  Radio-WeinWelle-Player
//

import Foundation
import AVFoundation
import MediaPlayer
#if !os(tvOS)
import NowPlaying
#endif
import Observation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@inline(__always) private func log(_ message: @autoclosure () -> String) {
    #if DEBUG
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[\(ts)] \(message())")
    #endif
}

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
    private var artworkTask: Task<Void, Never>?

    @ObservationIgnored private var hasStreamMetadata = false
    @ObservationIgnored private var lastArtworkKey = ""
    // URL?? outer nil = never loaded; .some(nil) = logo shown; .some(url) = url artwork shown
    @ObservationIgnored private var lastLegacyArtworkURL: URL?? = .none
    @ObservationIgnored private var songStartDate: Date? = nil
    @ObservationIgnored private var currentTrackDuration: TimeInterval? = nil
    // Pre-downloaded artwork data — set before nowPlaying.artworkURL so both paths see it immediately
    @ObservationIgnored private var cachedArtwork: (url: URL, data: Data)? = nil

    #if !os(tvOS)
    @ObservationIgnored private var _mediaSession: AnyObject?

    @available(iOS 27, macOS 27, *)
    private var mediaSession: MediaSession<RadioPlayer>? {
        get { _mediaSession as? MediaSession<RadioPlayer> }
        set { _mediaSession = newValue }
    }
    #endif

    init(station: RadioStation) {
        self.station = station
        self.id = station.id.uuidString
        super.init()
        nowPlaying = NowPlayingInfo(title: station.name, artist: "", artworkURL: nil)
        log("[Player] init – Station: \(station.name), Stream: \(station.streamURL)")
        setupInterruptionHandling()
        setupBackgroundObservers()
        #if !os(tvOS)
        if #available(iOS 27, macOS 27, *) {
            mediaSession = MediaSession(self)
            log("[Player] MediaSession (iOS 27) erstellt")
        } else {
            configureRemoteCommandsLegacy()
            log("[Player] Legacy-RemoteCommands konfiguriert")
        }
        #else
        configureRemoteCommandsLegacy()
        log("[Player] Legacy-RemoteCommands konfiguriert (tvOS)")
        #endif
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
        log("[Player] play() – aktueller State: \(state)")
        if case .failed = state { tearDownPlayer() }
        configureAudioSession()
        if player == nil { setUpPlayer() }
        player?.play()
        state = player?.currentItem?.status == .readyToPlay ? .playing : .buffering
        log("[Player] State nach play(): \(state)")
        hasStreamMetadata = false
        lastArtworkKey = ""
        lastLegacyArtworkURL = .none
        startPolling()
        #if !os(tvOS)
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
        #else
        updateNowPlayingCenterLegacy()
        #endif
    }

    func pause() {
        log("[Player] pause()")
        player?.pause()
        state = .paused
        stopPolling()
        #if !os(tvOS)
        if #available(iOS 27, macOS 27, *) {
            // MediaSession beobachtet state-Änderungen automatisch über @Observable
        } else {
            updateNowPlayingCenterLegacy()
        }
        #else
        updateNowPlayingCenterLegacy()
        #endif
    }

    // MARK: - Player-Setup

    private func setUpPlayer() {
        log("[Player] AVPlayer wird aufgebaut – URL: \(station.streamURL)")
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
                    self.state = .playing
                    log("[Player] AVPlayerItem readyToPlay → state = .playing")
                    #if !os(tvOS)
                    if #available(iOS 27, macOS 27, *) {
                        // automatisch
                    } else {
                        self.updateNowPlayingCenterLegacy()
                    }
                    #else
                    self.updateNowPlayingCenterLegacy()
                    #endif
                case .failed:
                    let msg = item.error?.localizedDescription ?? "Unbekannter Fehler"
                    log("[Player] AVPlayerItem failed: \(msg)")
                    self.state = .failed(msg)
                default:
                    break
                }
            }
        }

        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer
    }

    private func tearDownPlayer() {
        log("[Player] tearDownPlayer()")
        stopPolling()
        artworkTask?.cancel()
        artworkTask = nil
        statusObservation = nil
        player?.pause()
        player = nil
        metadataOutput = nil
        songStartDate = nil
        currentTrackDuration = nil
        cachedArtwork = nil
    }

    private func configureAudioSession() {
        #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                log("[Player] AudioSession → .playback, aktiv")
            } catch {
                log("[Player] AudioSession-Fehler: \(error)")
            }
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

    private func setupBackgroundObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        #endif
    }

    #if os(iOS)
    @objc private nonisolated func appDidEnterBackground() {
        Task { @MainActor in
            guard self.state == .playing || self.state == .buffering else { return }
            log("[Player] Hintergrund – normales Polling pausiert, Song-End-Watch aktiv")
            self.startBackgroundPolling()
        }
    }

    @objc private nonisolated func appWillEnterForeground() {
        Task { @MainActor in
            guard self.state == .playing || self.state == .buffering else { return }
            log("[Player] Vordergrund – Polling wird wieder gestartet")
            self.startPolling()
        }
    }
    #endif

    #if os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
    @objc private nonisolated func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        Task { @MainActor in
            switch type {
            case .began:
                log("[Player] Unterbrechung begonnen – Player pausiert")
                if self.state == .playing || self.state == .buffering {
                    self.stopPolling()
                    self.state = .paused
                }
            case .ended:
                let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                log("[Player] Unterbrechung beendet – shouldResume: \(options.contains(.shouldResume))")
                if options.contains(.shouldResume), self.state == .paused {
                    self.play()
                }
            @unknown default:
                break
            }
        }
    }
    #endif

    // MARK: - Legacy: MPRemoteCommandCenter / MPNowPlayingInfoCenter

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
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = nowPlaying.title
        info[MPMediaItemPropertyArtist] = nowPlaying.artist
        info[MPNowPlayingInfoPropertyIsLiveStream] = true
        info[MPNowPlayingInfoPropertyPlaybackRate] = isActive ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkLegacyIfNeeded()
    }

    private func loadArtworkLegacyIfNeeded() {
        let artworkURL: URL? = nowPlaying.artworkURL
        let newState: URL?? = artworkURL  // URL? wrapped to URL?? (.some(nil) != outer .none)
        guard newState != lastLegacyArtworkURL else { return }
        lastLegacyArtworkURL = newState
        artworkTask?.cancel()
        artworkTask = nil
        if let url = artworkURL {
            // Use pre-downloaded data if available — avoids a second network request
            if let cached = cachedArtwork, cached.url == url,
               let image = PlatformImage(data: cached.data) {
                setArtworkLegacy(image)
                return
            }
            artworkTask = Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let self,
                      let image = PlatformImage(data: data),
                      self.lastLegacyArtworkURL == newState else { return }
                self.setArtworkLegacy(image)
            }
        } else {
            #if canImport(UIKit)
            if let image = UIImage(named: "logo") { setArtworkLegacy(image) }
            #elseif canImport(AppKit)
            if let image = NSImage(named: "logo") { setArtworkLegacy(image) }
            #endif
        }
    }

    private func setArtworkLegacy(_ image: PlatformImage) {
        let isActive = state == .playing || state == .buffering
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: nowPlaying.title,
            MPMediaItemPropertyArtist: nowPlaying.artist,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isActive ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0,
            MPMediaItemPropertyArtwork: artwork
        ]
    }

    // MARK: - iTunes Cover-Art-Lookup

    private func fetchArtwork(artist: String, title: String) async {
        let key = "\(artist)|\(title)"
        guard !artist.isEmpty, !title.isEmpty, key != lastArtworkKey else { return }
        lastArtworkKey = key
        songStartDate = Date()
        currentTrackDuration = nil
        let query = "\(artist) \(title)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlStr = "https://itunes.apple.com/search?term=\(query)&media=music&limit=1&country=DE"
        log("[iTunes] Artwork-Suche: \(artist) – \(title)")
        guard let url = URL(string: urlStr),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let result = try? JSONDecoder().decode(iTunesSearchResult.self, from: data),
              let track = result.results.first else {
            log("[iTunes] Kein Artwork-Ergebnis gefunden – nächste Poll-Runde versucht es erneut")
            lastArtworkKey = ""
            return
        }
        let highRes = track.artworkUrl100.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        if let ms = track.trackTimeMillis {
            currentTrackDuration = Double(ms) / 1000.0
            log("[iTunes] Dauer: \(ms / 1000)s (\(String(format: "%.1f", Double(ms) / 60000.0)) min)")
        }
        guard let artworkURL = URL(string: highRes),
              let (imgData, _) = try? await URLSession.shared.data(from: artworkURL) else {
            log("[iTunes] Artwork-Download fehlgeschlagen")
            lastArtworkKey = ""
            return
        }
        log("[iTunes] Artwork heruntergeladen (\(imgData.count / 1024) KB)")
        // Cache first — both paths read this before/during nowPlaying update
        cachedArtwork = (url: artworkURL, data: imgData)
        nowPlaying.artworkURL = artworkURL
        #if !os(tvOS)
        if #available(iOS 27, macOS 27, *) {
            // MediaSession observes nowPlaying via @Observable; content liest cachedArtwork
        } else {
            updateNowPlayingCenterLegacy()
        }
        #else
        updateNowPlayingCenterLegacy()
        #endif
    }

    // MARK: - Icecast-API-Polling

    private func startPolling() {
        guard station.nowPlayingURL != nil else {
            log("[Icecast] Kein nowPlayingURL konfiguriert – Polling deaktiviert")
            return
        }
        log("[Icecast] Polling gestartet (alle 15 s) → \(station.nowPlayingURL!)")
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.fetchIcecastMetadata()
                let interval = self.nextPollingInterval()
                try? await Task.sleep(for: interval)
            }
            log("[Icecast] Polling-Task beendet")
        }
    }

    private func stopPolling() {
        log("[Icecast] Polling gestoppt")
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func startBackgroundPolling() {
        guard station.nowPlayingURL != nil else { return }
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.nextBackgroundInterval()
                log("[Icecast] Hintergrund – nächster Check in \(Int(interval.components.seconds))s")
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                log("[Icecast] Hintergrund – Song-Ende erwartet, Metadaten werden aktualisiert")
                await self.fetchIcecastMetadata()
            }
        }
    }

    private func nextBackgroundInterval() -> Duration {
        if let start = songStartDate, let duration = currentTrackDuration {
            let elapsed = Date().timeIntervalSince(start)
            let remaining = duration - elapsed + 2  // 2s Puffer nach Song-Ende
            if remaining > 5 { return .seconds(remaining) }
        }
        return .seconds(180)  // unbekannte Dauer: alle 3 Minuten prüfen
    }

    private func nextPollingInterval() -> Duration {
        if let start = songStartDate, let duration = currentTrackDuration {
            let elapsed = Date().timeIntervalSince(start)
            let remaining = duration - elapsed
            // Sicherheitsnetz: Song läuft > 60s über die erwartete Dauer → wieder langsam
            if elapsed < duration + 60 {
                if remaining < 20 { return .seconds(4) }
                if remaining < 45 { return .seconds(10) }
            }
        }
        return .seconds(15)
    }

    private func fetchIcecastMetadata() async {
        guard let apiURL = station.nowPlayingURL else { return }
        log("[Icecast] Hole Metadaten von \(apiURL)")
        guard let (data, _) = try? await URLSession.shared.data(from: apiURL) else {
            if !Task.isCancelled {
                log("[Icecast] Netzwerkfehler – keine Antwort")
            }
            return
        }
        guard let status = try? JSONDecoder().decode(IcecastStatus.self, from: data) else {
            let raw = String(data: data, encoding: .utf8)?.prefix(200) ?? "<leer>"
            log("[Icecast] JSON-Decode fehlgeschlagen. Antwort: \(raw)")
            return
        }

        let streamPath = station.streamURL.path
        let source = status.icestats.source?.first {
            $0.listenurl?.hasSuffix(streamPath) == true
        } ?? status.icestats.source?.first

        guard let rawTitle = source?.title, !rawTitle.isEmpty else {
            log("[Icecast] Kein Titel in der API-Antwort (listenurl: \(source?.listenurl ?? "nil"))")
            if !hasStreamMetadata {
                await fetchPlaylistMetadata()
            }
            return
        }

        let decoded = fixEncoding(rawTitle)
        log("[Icecast] Rohtitel: \"\(rawTitle)\" → dekodiert: \"\(decoded)\"")

        let parts = decoded.components(separatedBy: " - ")
        guard parts.count >= 2 else {
            log("[Icecast] Kein Trennzeichen ' - ' im Titel – kein Song-Metadatum")
            if !hasStreamMetadata { await fetchPlaylistMetadata() }
            return
        }

        let artist = parts[0]
        let songTitle = parts[1...].joined(separator: " - ")

        guard artist.caseInsensitiveCompare(station.name) != .orderedSame else {
            log("[Icecast] Promo-Text erkannt (Künstler = Sendername '\(artist)') – ignoriert")
            if !hasStreamMetadata { await fetchPlaylistMetadata() }
            return
        }

        log("[Icecast] Song erkannt: \(artist) – \(songTitle)")
        nowPlaying.artist = artist
        nowPlaying.title = songTitle
        hasStreamMetadata = true
        await fetchArtwork(artist: nowPlaying.artist, title: nowPlaying.title)
        #if !os(tvOS)
        if #available(iOS 27, macOS 27, *) {
            // automatisch
        } else {
            updateNowPlayingCenterLegacy()
        }
        #else
        updateNowPlayingCenterLegacy()
        #endif
    }

    // MARK: - Playlist-Scraping (Fallback)

    private func fetchPlaylistMetadata() async {
        guard let url = station.playlistURL else { return }
        log("[Playlist] Hole Fallback-Metadaten von \(url)")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else {
            log("[Playlist] Netzwerkfehler oder ungültiges HTML")
            return
        }
        guard let match = html.firstMatch(of: /(?s)list-item-big.*?<h1>\s*(.*?)\s*<\/h1>.*?<h2>von\s+(.*?)\s*<\/h2>/) else {
            log("[Playlist] Kein Titel-/Künstlereintrag gefunden")
            return
        }
        let title = String(match.1).trimmingCharacters(in: .whitespaces)
        let artist = String(match.2).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !artist.isEmpty else { return }
        guard nowPlaying.artist != artist || nowPlaying.title != title else {
            log("[Playlist] Identisch mit aktuellem Titel – ignoriert")
            return
        }
        log("[Playlist] Titel erkannt: \(artist) – \(title)")
        nowPlaying.artist = artist
        nowPlaying.title = title
        await fetchArtwork(artist: artist, title: title)
        #if !os(tvOS)
        if #available(iOS 27, macOS 27, *) {} else { updateNowPlayingCenterLegacy() }
        #else
        updateNowPlayingCenterLegacy()
        #endif
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

#if !os(tvOS)
@available(iOS 27, macOS 27, *)
@MainActor
extension RadioPlayer: MediaSessionRepresentable {

    var content: (any MediaContentRepresentable)? {
        let artworkObj: Artwork? = {
            if let url = nowPlaying.artworkURL {
                // Use pre-downloaded data when available — avoids network request in closure
                if let cached = cachedArtwork, cached.url == url {
                    let capturedData = cached.data
                    return Artwork(id: url.absoluteString) { _ in
                        return try ArtworkRepresentation(data: capturedData)
                    }
                }
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
#endif

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
                    log("[ICY] Stream-Metadatum empfangen: \"\(fixed)\"")

                    let parts = fixed.components(separatedBy: " - ")
                    guard parts.count >= 2 else {
                        log("[ICY] Kein Trennzeichen ' - ' – ignoriert")
                        continue
                    }
                    let artist = parts[0]
                    let songTitle = parts[1...].joined(separator: " - ")

                    guard artist.caseInsensitiveCompare(self.station.name) != .orderedSame else {
                        log("[ICY] Promo-Text erkannt (Künstler = Sendername '\(artist)') – ignoriert")
                        if !self.hasStreamMetadata { await self.fetchPlaylistMetadata() }
                        continue
                    }

                    log("[ICY] Song gesetzt: \(artist) – \(songTitle)")
                    self.nowPlaying.artist = artist
                    self.nowPlaying.title = songTitle
                    self.hasStreamMetadata = true
                    await self.fetchArtwork(artist: artist, title: songTitle)
                    #if !os(tvOS)
                    if #available(iOS 27, macOS 27, *) {
                        // automatisch
                    } else {
                        self.updateNowPlayingCenterLegacy()
                    }
                    #else
                    self.updateNowPlayingCenterLegacy()
                    #endif
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
    struct Track: Decodable {
        let artworkUrl100: String
        let trackTimeMillis: Int?
    }
    let results: [Track]
}

// MARK: - Preview Helper

extension RadioPlayer {
    static func makePreview(
        title: String = "Rote Lippen soll man küssen",
        artist: String = "Cindy & Bert",
        state: PlaybackState = .playing,
        artworkURL: URL? = nil
    ) -> RadioPlayer {
        let p = RadioPlayer(station: .weinWelle)
        p.nowPlaying = NowPlayingInfo(title: title, artist: artist, artworkURL: artworkURL)
        p.state = state
        return p
    }
}
