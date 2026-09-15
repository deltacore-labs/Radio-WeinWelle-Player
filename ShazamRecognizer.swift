//
//  ShazamRecognizer.swift
//  Radio-WeinWelle-Player
//

import ShazamKit
import AVFoundation

/// Erkennt den laufenden Song via Mikrofon-Tap (AVAudioEngine).
/// MTAudioProcessingTap / audioTap wurde in iOS 27 entfernt.
@MainActor
final class ShazamRecognizer: NSObject {
    var onMatch: ((String, String, URL?) -> Void)?
    private(set) var isRunning = false

    private var session: SHSession?
    private var audioEngine: AVAudioEngine?
    private var generator = SHSignatureGenerator()
    private var signatureTask: Task<Void, Never>?

    func start(with item: AVPlayerItem) {
        #if os(tvOS)
        print("[StreamShazam] tvOS hat kein Mikrofon – Shazam deaktiviert")
        return
        #endif
        guard !isRunning else {
            print("[StreamShazam] start() ignoriert – läuft bereits")
            return
        }
        print("[StreamShazam] start() – starte Shazam via Mikrofon")
        isRunning = true

        let shSession = SHSession()
        shSession.delegate = self
        session = shSession
        generator = SHSignatureGenerator()

        #if os(iOS) || os(visionOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothHFP, .defaultToSpeaker]
            )
            try AVAudioSession.sharedInstance().setActive(true)
            print("[StreamShazam] AudioSession → .playAndRecord + mixWithOthers")
        } catch {
            print("[StreamShazam] AudioSession-Fehler: \(error)")
            isRunning = false
            return
        }
        #endif

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, _ in
            try? self?.generator.append(buffer, at: nil)
        }

        do {
            try engine.start()
        } catch {
            print("[StreamShazam] AVAudioEngine-Fehler: \(error)")
            cleanupAudio()
            isRunning = false
            return
        }

        signatureTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { break }
                let sig = self.generator.signature()
                self.session?.match(sig)
                print("[StreamShazam] Signatur gesendet (\(String(format: "%.1f", sig.duration))s Audio)")
            }
        }
    }

    func stop() {
        guard isRunning || signatureTask != nil else { return }
        print("[StreamShazam] stop()")
        signatureTask?.cancel()
        signatureTask = nil
        cleanupAudio()
        session = nil
        isRunning = false
    }

    private func cleanupAudio() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        #if os(iOS) || os(visionOS)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)
                print("[StreamShazam] AudioSession → .playback wiederhergestellt")
            } catch {
                print("[StreamShazam] AudioSession-Restore-Fehler: \(error)")
            }
        }
        #endif
    }
}

// MARK: - SHSessionDelegate

extension ShazamRecognizer: SHSessionDelegate {
    nonisolated func session(_ session: SHSession, didFind match: SHMatch) {
        guard let item = match.mediaItems.first else { return }
        let artist = item.artist ?? ""
        let title = item.title ?? ""
        let artworkURL = item.artworkURL
        print("[StreamShazam] Match: \(artist) – \(title)")
        Task { @MainActor [weak self] in
            self?.onMatch?(artist, title, artworkURL)
            self?.stop()
        }
    }

    nonisolated func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature,
                             error: (any Error)?) {
        if let error {
            print("[StreamShazam] Kein Match – \(error.localizedDescription)")
        } else {
            print("[StreamShazam] Kein Match für diese Signatur")
        }
    }
}
