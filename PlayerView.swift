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

            VStack {
                Spacer()
                card
                Spacer()
            }
            .padding(.vertical, 24)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 0) {
            // Artwork floats above the glass panel (42 pt overlap)
            artwork
                .padding(.bottom, -22)
                .zIndex(1)

            // Glass panel
            VStack(spacing: 22) {
                // top spacer compensates for artwork overlap
                Spacer().frame(height: 24)

                VStack(spacing: 7) {
                    MarqueeText(text: player.nowPlaying.title, font: .title.weight(.semibold))
                        .foregroundStyle(.white)
                    if !player.nowPlaying.artist.isEmpty {
                        MarqueeText(text: player.nowPlaying.artist, font: .title2)
                            .foregroundStyle(.white.opacity(0.80))
                    }
                }

                statusText

                playButton
            }
            .padding(.bottom, 32)
            .padding(.horizontal, 28)
            .background {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        // Top highlight rim — gives the card a "lit from above" look
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
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
                        // Subtle inner glow at the top edge of the panel
                        LinearGradient(
                            colors: [.white.opacity(0.12), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                        .frame(height: 90)
                    }
            }
            .shadow(color: .black.opacity(0.55), radius: 40, y: 20)
            .zIndex(0)
        }
        .frame(maxWidth: 480)
        .padding(.horizontal, 20)
    }

    // MARK: - Computed

    private var isPlaying: Bool {
        player.state == .playing || player.state == .buffering
    }

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
        // White glow ring around the artwork
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
        // Red color glow
        .shadow(
            color: Color(red: 0.757, green: 0.184, blue: 0.212).opacity(isPlaying ? 0.75 : 0.18),
            radius: isPlaying ? 46 : 12
        )
        // Diffuse outer halo for extra lift
        .shadow(
            color: .black.opacity(0.55),
            radius: 24, y: 10
        )
        .scaleEffect(isPlaying ? 1.04 : 1.0)
        .animation(.spring(response: 0.6, dampingFraction: 0.75), value: isPlaying)
    }

    @ViewBuilder
    private var playButton: some View {
        Button(action: player.togglePlayPause) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .resizable()
                .frame(width: 78, height: 78)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color(red: 0.757, green: 0.184, blue: 0.212)) // #c12f36
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? "Pause" : "Wiedergabe")
        .animation(.spring(response: 0.35, dampingFraction: 0.70), value: isPlaying)
    }

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

// MARK: - Animated Wine Background (floating orbs)

private struct WeinBackground: View {
    let isPlaying: Bool
    @State private var liveOpacity: Double = 0

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

            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !isPlaying)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.757, green: 0.184, blue: 0.212).opacity(0.75))
                            .frame(width: w * 0.75, height: w * 0.75)
                            .blur(radius: w * 0.22)
                            .offset(x: sin(t * 0.25) * w * 0.15,
                                    y: cos(t * 0.18) * h * 0.15 - h * 0.22)

                        Circle()
                            .fill(Color(red: 0.992, green: 0.725, blue: 0.075).opacity(0.45))
                            .frame(width: w * 0.55, height: w * 0.55)
                            .blur(radius: w * 0.18)
                            .offset(x: cos(t * 0.30 + 1.5) * w * 0.18 + w * 0.22,
                                    y: sin(t * 0.22 + 0.5) * h * 0.12 + h * 0.18)

                        Circle()
                            .fill(Color(red: 0.831, green: 0.000, blue: 0.188).opacity(0.55))
                            .frame(width: w * 0.65, height: w * 0.65)
                            .blur(radius: w * 0.20)
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
                .fill(Color(red: 0.831, green: 0.0, blue: 0.188)) // #d40030
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

// MARK: - Marquee Text (seamless ticker)

private struct MarqueeText: View {
    let text: String
    let font: Font

    @State private var textWidth: CGFloat = 0
    @State private var textHeight: CGFloat = 28
    @State private var startDate: Date = .distantPast

    private let gap: CGFloat = 60     // Lücke zwischen den zwei Text-Kopien
    private let speed: Double = 30    // pt/s
    private let pauseSeconds: Double = 1.5

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width
            let tw = textWidth

            if tw > cw && tw > 0 {
                // Zwei Kopien nebeneinander → nahtloser Endlos-Loop
                let cycle = Double(tw + gap)
                TimelineView(.animation(minimumInterval: 1.0 / 60)) { ctx in
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
            // Unsichtbare Messung der natürlichen Textbreite via onGeometryChange
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

#Preview("MarqueeText – kurz") {
    MarqueeText(text: "Radio Wein-Welle", font: .title2.weight(.semibold))
        .foregroundStyle(.white)
        .padding()
        .background(.black)
        .frame(width: 320)
}

#Preview("MarqueeText – langer Titel") {
    MarqueeText(text: "Eine sehr lange Titelzeile die definitiv nicht mehr in die Breite passt und scrollen muss", font: .title3)
        .foregroundStyle(.white.opacity(0.70))
        .padding()
        .background(.black)
        .frame(width: 320)
}

