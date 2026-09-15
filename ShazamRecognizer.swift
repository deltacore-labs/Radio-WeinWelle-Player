//
//  ShazamRecognizer.swift
//  Radio-WeinWelle-Player
//

import ShazamKit
import AVFoundation
import MediaToolbox

/// Erkennt den laufenden Song direkt aus dem Stream-Audio via MTAudioProcessingTap.
/// Kein Mikrofon, kein AudioSession-Wechsel.
@MainActor
final class ShazamRecognizer: NSObject {
    var onMatch: ((String, String, URL?) -> Void)?
    private(set) var isRunning = false

    private var session: SHSession?
    private var playerItem: AVPlayerItem?
    private var tapContext: TapContext?
    private var installTask: Task<Void, Never>?
    private var signatureTask: Task<Void, Never>?

    func start(with item: AVPlayerItem) {
        guard !isRunning else {
            print("[StreamShazam] start() ignoriert – läuft bereits")
            return
        }
        print("[StreamShazam] start() – installiere Audio-Tap auf Stream")

        let shSession = SHSession()
        shSession.delegate = self
        session = shSession
        playerItem = item
        isRunning = true

        let ctx = TapContext(session: shSession)
        tapContext = ctx

        installTask = Task { [weak self] in
            await self?.installTap(on: item, context: ctx)
        }
    }

    func stop() {
        guard isRunning || installTask != nil else { return }
        print("[StreamShazam] stop()")
        installTask?.cancel()
        installTask = nil
        signatureTask?.cancel()
        signatureTask = nil
        playerItem?.audioMix = nil
        tapContext = nil
        playerItem = nil
        session = nil
        isRunning = false
    }

    private func installTap(on item: AVPlayerItem, context: TapContext) async {
        // Live streams don't expose tracks via AVAsset.loadTracks; use item.tracks instead.
        let audioTrack = item.tracks
            .compactMap { $0.assetTrack }
            .first { $0.mediaType == .audio }

        guard let audioTrack, !Task.isCancelled else {
            if !Task.isCancelled {
                print("[StreamShazam] Kein Audio-Track – Tap nicht installiert")
            }
            return
        }

        let retained = Unmanaged.passRetained(context)

        let callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retained.toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: nil,
            process: tapProcess
        )

        var tap: MTAudioProcessingTap?
        var mutableCallbacks = callbacks
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &mutableCallbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects, &tap
        )
        guard status == noErr, let tap else {
            print("[StreamShazam] MTAudioProcessingTapCreate fehlgeschlagen: \(status)")
            retained.release()
            return
        }

        let params = AVMutableAudioMixInputParameters(track: audioTrack)
        params.setValue(tap, forKey: "audioTap")

        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        item.audioMix = mix

        print("[StreamShazam] Audio-Tap installiert – starte periodisches Matching")

        signatureTask = Task { [weak context] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let ctx = context else { break }
                let sig = ctx.generator.signature()
                ctx.session.match(sig)
                print("[StreamShazam] Signatur gesendet (\(String(format: "%.1f", sig.duration))s Audio)")
            }
        }
    }
}

// MARK: - TapContext (Heap-allocated; Lebensdauer durch MTAudioProcessingTap gesteuert)

private final class TapContext {
    let generator = SHSignatureGenerator()
    let session: SHSession
    var audioFormat: AVAudioFormat?

    init(session: SHSession) {
        self.session = session
    }
}

// MARK: - MTAudioProcessingTap Callbacks (kein Capture – Kontext via tapStorage)

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, tapStorageOut in
    tapStorageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    let s = MTAudioProcessingTapGetStorage(tap)
    Unmanaged<TapContext>.fromOpaque(s).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, _, processingFormat in
    let ctx = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    ctx.audioFormat = AVAudioFormat(streamDescription: processingFormat)
}

private let tapProcess: MTAudioProcessingTapProcessCallback = {
    tap, numFrames, _, bufListInOut, numFramesOut, flagsOut in

    var tapFlags: MTAudioProcessingTapFlags = 0
    var srcFrames: CMItemCount = 0
    MTAudioProcessingTapGetSourceAudio(tap, numFrames, bufListInOut, &tapFlags, nil, &srcFrames)
    numFramesOut.pointee = srcFrames
    flagsOut.pointee = tapFlags

    let ctx = Unmanaged<TapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    guard srcFrames > 0, let format = ctx.audioFormat,
          let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(srcFrames)),
          let floatData = pcm.floatChannelData else { return }
    pcm.frameLength = AVAudioFrameCount(srcFrames)

    let abl = UnsafeMutableAudioBufferListPointer(bufListInOut)
    for (ch, ab) in abl.enumerated() where ch < Int(format.channelCount) {
        guard let src = ab.mData else { continue }
        memcpy(floatData[ch], src, Int(ab.mDataByteSize))
    }

    try? ctx.generator.append(pcm, at: nil)
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
