//
//  PlayerView.swift
//  Radio-WeinWelle-Player
//

import SwiftUI

struct PlayerView: View {
    @Environment(RadioPlayer.self) private var player

    var body: some View {
        ZStack {
            WeinBackground(isPlaying: isPlaying)
                .ignoresSafeArea()
            ArtworkBackground(url: player.nowPlaying.artworkURL, isPlaying: isPlaying)
                .ignoresSafeArea()

            #if os(tvOS)
            tvOSCard
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
            #else
            VStack {
                Spacer()
                card
                Spacer()
            }
            .padding(.vertical, 24)
            #endif
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - iOS/macOS Card

    #if !os(tvOS)
    private var card: some View {
        VStack(spacing: 0) {
            artwork
                .padding(.bottom, -22)
                .zIndex(1)

            VStack(spacing: 22) {
                Spacer().frame(height: 24)

                VStack(spacing: 7) {
                    MarqueeText(text: player.nowPlaying.title, font: .title.weight(.semibold), isPlaying: isPlaying)
                        .foregroundStyle(.white)
                    if !player.nowPlaying.artist.isEmpty {
                        MarqueeText(text: player.nowPlaying.artist, font: .title2, isPlaying: isPlaying)
                            .foregroundStyle(.white.opacity(0.80))
                    }
                }

                if case .buffering = player.state {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Verbinde …").foregroundStyle(.white.opacity(0.70))
                    }
                } else if case .failed(let message) = player.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.85))
                        .multilineTextAlignment(.center)
                }

                playButton
            }
            .padding(.bottom, 32)
            .padding(.horizontal, 28)
            .background { cardBackground(cornerRadius: 36) }
            .shadow(color: .black.opacity(0.55), radius: 16, y: 14)
            .zIndex(0)
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 28)
    }
    #endif

    // MARK: - tvOS Card (horizontal, 10-foot UI)

    #if os(tvOS)
    private var tvOSCard: some View {
        HStack(spacing: 70) {
            tvOSArtwork

            VStack(alignment: .leading, spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text(player.nowPlaying.title)
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if !player.nowPlaying.artist.isEmpty {
                        Text(player.nowPlaying.artist)
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.80))
                            .lineLimit(1)
                    }
                }

                Spacer().frame(height: 32)

                HStack(spacing: 24) {
                    if isPlaying { LiveBadge() }
                    statusText
                }

                Spacer().frame(height: 40)

                tvOSPlayButton

                Spacer()
            }
            .frame(maxWidth: 560)
        }
        .padding(.horizontal, 70)
        .padding(.vertical, 56)
        .background { cardBackground(cornerRadius: 44) }
        .shadow(color: .black.opacity(0.60), radius: 70, y: 30)
        .frame(maxWidth: 1200)
    }

    private var tvOSArtwork: some View {
        AsyncImage(url: player.nowPlaying.artworkURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color(red: 0.004, green: 0.098, blue: 0.231))
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .padding(56)
            }
        }
        .frame(width: 480, height: 480)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isPlaying ? 0.55 : 0.20),
                            .white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2.5
                )
        }
        .shadow(
            color: Color(red: 0.757, green: 0.184, blue: 0.212).opacity(isPlaying ? 0.75 : 0.18),
            radius: isPlaying ? 60 : 16
        )
        .shadow(color: .black.opacity(0.55), radius: 30, y: 14)
        .scaleEffect(isPlaying ? 1.03 : 1.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isPlaying)
    }

    private var tvOSPlayButton: some View {
        Button(action: player.togglePlayPause) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .resizable()
                .frame(width: 110, height: 110)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(red: 0.757, green: 0.184, blue: 0.212))
        }
        .accessibilityLabel(isPlaying ? "Pause" : "Wiedergabe")
        .animation(.spring(response: 0.35, dampingFraction: 0.70), value: isPlaying)
    }
    #endif

    // MARK: - Shared card background

    @ViewBuilder
    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.14, blue: 0.26).opacity(0.92),
                        Color(red: 0.03, green: 0.07, blue: 0.17).opacity(0.92),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), .white.opacity(0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.white.opacity(0.12), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(height: 90)
            }
    }

    // MARK: - Computed

    private var isPlaying: Bool {
        player.state == .playing || player.state == .buffering
    }

    // MARK: - Shared sub-views (iOS/macOS)

    #if !os(tvOS)
    @State private var artworkTiltX: Double = 0
    @State private var artworkTiltY: Double = 0
    @State private var artworkTilting = false

    @ViewBuilder
    private var artwork: some View {
        AsyncImage(url: player.nowPlaying.artworkURL) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(red: 0.004, green: 0.098, blue: 0.231))
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .padding(32)
            }
        }
        .frame(width: 310, height: 310)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(isPlaying ? 0.55 : 0.20),
                            .white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
        }
        .overlay(alignment: .bottomLeading) {
            if isPlaying { LiveBadge().padding(12) }
        }
        .shadow(
            color: Color(red: 0.757, green: 0.184, blue: 0.212).opacity(isPlaying ? 0.75 : 0.18),
            radius: isPlaying ? 22 : 12
        )
        .shadow(color: .black.opacity(0.55), radius: 24, y: 10)
        .scaleEffect(isPlaying ? 1.04 : 1.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isPlaying)
        .rotation3DEffect(.degrees(artworkTiltX), axis: (1, 0, 0), perspective: 0.4)
        .rotation3DEffect(.degrees(artworkTiltY), axis: (0, 1, 0), perspective: 0.4)
        .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.70), value: artworkTiltX)
        .animation(.interactiveSpring(response: 0.20, dampingFraction: 0.70), value: artworkTiltY)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.28), .clear],
                        center: UnitPoint(
                            x: 0.5 + artworkTiltY / 36.0,
                            y: 0.5 - artworkTiltX / 36.0
                        ),
                        startRadius: 10,
                        endRadius: 170
                    )
                )
                .blendMode(.screen)
                .opacity(artworkTilting ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: artworkTilting)
                .allowsHitTesting(false)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let dx = min(max((value.location.x - 155) / 155, -1.0), 1.0)
                    let dy = min(max((value.location.y - 155) / 155, -1.0), 1.0)
                    artworkTiltY = dx * 18
                    artworkTiltX = -dy * 18
                    artworkTilting = true
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.65)) {
                        artworkTiltX = 0
                        artworkTiltY = 0
                        artworkTilting = false
                    }
                }
        )
    }

    @ViewBuilder
    private var playButton: some View {
        Button(action: player.togglePlayPause) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .resizable()
                .frame(width: 78, height: 78)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(red: 0.757, green: 0.184, blue: 0.212))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Wiedergabe")
        .animation(.spring(response: 0.35, dampingFraction: 0.70), value: isPlaying)
    }
    #endif

    @ViewBuilder
    private var statusText: some View {
        switch player.state {
        case .buffering:
            HStack(spacing: 8) {
                ProgressView().tint(.white)
                Text("Verbinde …").foregroundStyle(.white.opacity(0.70))
            }
        case .failed(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red.opacity(0.85))
                .multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }
}

#Preview {
    PlayerView()
        .environment(RadioPlayer(station: .weinWelle))
}

#Preview("Spielt – mit Titel & Interpret") {
    PlayerView()
        .environment(RadioPlayer.makePreview())
}

#Preview("Spielt – langer Titel") {
    PlayerView()
        .environment(RadioPlayer.makePreview(
            title: "Ein sehr langer Songtitel der definitiv über die Breite geht",
            artist: "Eine sehr lange Bandbezeichnung aus dem Weinviertel"
        ))
}

#Preview("Spielt – nur Titel, kein Interpret") {
    PlayerView()
        .environment(RadioPlayer.makePreview(artist: ""))
}

#Preview("Pausiert") {
    PlayerView()
        .environment(RadioPlayer.makePreview(state: .paused))
}

#Preview("Spielt – mit Albumcover") {
    PlayerView()
        .environment(RadioPlayer.makePreview(
            artworkURL: URL(string: "https://picsum.photos/seed/weinwelle/600/600")
        ))
}

#Preview("Pausiert – mit Albumcover") {
    PlayerView()
        .environment(RadioPlayer.makePreview(
            state: .paused,
            artworkURL: URL(string: "https://picsum.photos/seed/weinwelle/600/600")
        ))
}

// MARK: - Animated Wine Background (floating orbs)

private struct WeinBackground: View {
    let isPlaying: Bool
    @State private var liveOpacity: Double = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.043, green: 0.184, blue: 0.318),
                    Color(red: 0.004, green: 0.098, blue: 0.231),
                    Color(red: 0.003, green: 0.07,  blue: 0.17),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            TimelineView(.animation(minimumInterval: 1.0 / 8, paused: !isPlaying || scenePhase != .active)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    ZStack {
                        Circle()
                            .fill(RadialGradient(
                                colors: [Color(red: 0.757, green: 0.184, blue: 0.212).opacity(0.80), .clear],
                                center: .center, startRadius: 0, endRadius: w * 0.375
                            ))
                            .frame(width: w * 0.75, height: w * 0.75)
                            .offset(x: sin(t * 0.25) * w * 0.15,
                                    y: cos(t * 0.18) * h * 0.15 - h * 0.22)

                        Circle()
                            .fill(RadialGradient(
                                colors: [Color(red: 0.992, green: 0.725, blue: 0.075).opacity(0.50), .clear],
                                center: .center, startRadius: 0, endRadius: w * 0.275
                            ))
                            .frame(width: w * 0.55, height: w * 0.55)
                            .offset(x: cos(t * 0.30 + 1.5) * w * 0.18 + w * 0.22,
                                    y: sin(t * 0.22 + 0.5) * h * 0.12 + h * 0.18)

                        Circle()
                            .fill(RadialGradient(
                                colors: [Color(red: 0.831, green: 0.000, blue: 0.188).opacity(0.60), .clear],
                                center: .center, startRadius: 0, endRadius: w * 0.325
                            ))
                            .frame(width: w * 0.65, height: w * 0.65)
                            .offset(x: sin(t * 0.20 + 3.0) * w * 0.12 - w * 0.18,
                                    y: cos(t * 0.28 + 1.0) * h * 0.15 + h * 0.12)
                    }
                    .frame(width: w, height: h)
                }
            }
            .opacity(liveOpacity)
            .animation(.easeInOut(duration: 2.0), value: liveOpacity)
        }
        .onAppear { liveOpacity = isPlaying ? 1.0 : 0.0 }
        .onChange(of: isPlaying) { _, playing in liveOpacity = playing ? 1.0 : 0.0 }
    }
}

// MARK: - Blurred Artwork Background (Apple Music Style)

private struct ArtworkBackground: View {
    let url: URL?
    let isPlaying: Bool
    @State private var opacity: Double = 0

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 55, opaque: true)
                        .saturation(1.6)
                        .brightness(-0.08)
                        .drawingGroup()
                        .blendMode(.overlay)
                        .opacity(opacity)
                        .onAppear {
                            withAnimation(.easeIn(duration: 0.9)) {
                                opacity = isPlaying ? 0.60 : 0.35
                            }
                        }
                        .onChange(of: isPlaying) { _, playing in
                            withAnimation(.easeInOut(duration: 1.5)) {
                                opacity = playing ? 0.60 : 0.35
                            }
                        }
                } else {
                    EmptyView()
                }
            }
            .id(url)
        }
    }
}

// MARK: - LIVE Badge

private struct LiveBadge: View {
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: 0.831, green: 0.0, blue: 0.188))
                .frame(width: 6, height: 6)
                .scaleEffect(pulsing ? 1.5 : 0.85)
                .animation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true), value: pulsing)
                .onAppear { pulsing = true }
            Text("LIVE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.50), in: Capsule())
    }
}

// MARK: - Marquee Text (seamless ticker, iOS/macOS only)

#if !os(tvOS)
private struct MarqueeText: View {
    let text: String
    let font: Font
    var isPlaying: Bool = true

    @State private var textWidth: CGFloat = 0
    @State private var textHeight: CGFloat = 28
    @State private var startDate: Date = .distantPast

    private let gap: CGFloat = 60
    private let speed: Double = 30
    private let pauseSeconds: Double = 1.5

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width
            let tw = textWidth

            if tw > cw && tw > 0 {
                let cycle = Double(tw + gap)
                TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !isPlaying)) { ctx in
                    let elapsed = max(0, ctx.date.timeIntervalSince(startDate) - pauseSeconds)
                    let phase = CGFloat((elapsed * speed).truncatingRemainder(dividingBy: cycle))
                    HStack(spacing: gap) {
                        label
                        label
                    }
                    .offset(x: -phase)
                }
            } else {
                label.frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(height: max(textHeight, 20))
        .clipped()
        .background {
            label
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { size in
                    guard size.width > 1 else { return }
                    textWidth = size.width
                    textHeight = size.height
                    startDate = .now
                }
        }
        .id(text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}
#endif

// MARK: - Previews: Sub-Views

#Preview("WeinBackground – spielend") {
    WeinBackground(isPlaying: true)
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

#Preview("WeinBackground – gestoppt") {
    WeinBackground(isPlaying: false)
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
}

#Preview("LiveBadge") {
    LiveBadge()
        .padding()
        .background(.black)
}
