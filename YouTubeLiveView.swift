#if !os(tvOS)
import SwiftUI
import WebKit

struct YouTubeLiveView: View {
    let checker: YouTubeLiveChecker

    private let channelURL = URL(string: "https://www.youtube.com/@RadioWeinWelle/streams")!
    private let embedURL  = URL(string: "https://www.youtube-nocookie.com/embed/live_stream?channel=UClyAqSF-AdlRUerBG4HZf9w&autoplay=1&playsinline=1&rel=0")!
    @State private var isRefreshing = false
    @State private var webViewPaused = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if checker.isLive {
                YouTubeWebView(url: embedURL, isPaused: $webViewPaused)
                    .ignoresSafeArea(edges: .bottom)
                    .onAppear { webViewPaused = false }
            } else {
                noLivePlaceholder
            }
        }
        .onDisappear { webViewPaused = true }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isRefreshing = true
                    Task {
                        await checker.checkLiveStatus()
                        isRefreshing = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .tint(.white)
                .disabled(isRefreshing)
            }
        }
    }

    private var noLivePlaceholder: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.757, green: 0.184, blue: 0.212).opacity(0.2))
                    .frame(width: 120, height: 120)
                Image(systemName: "play.slash.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                Text("Kein Livestream aktiv")
                    .font(.title2.weight(.semibold))
                Text("Radio Wein-Welle ist gerade nicht live auf YouTube.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let lastChecked = checker.lastChecked {
                    Text("Zuletzt geprüft: \(lastChecked.formatted(date: .omitted, time: .shortened)) Uhr")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Link(destination: channelURL) {
                Label("Zum YouTube-Kanal", systemImage: "arrow.up.right.square")
                    .font(.body.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color(red: 0.757, green: 0.184, blue: 0.212))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
        .padding(32)
        .foregroundStyle(.white)
    }
}

/// Plattformübergreifender WKWebView-Wrapper für YouTube-Embeds.
private struct YouTubeWebView {
    let url: URL
    @Binding var isPaused: Bool
}

#if canImport(UIKit)
import UIKit
extension YouTubeWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if webView.url != url { webView.load(URLRequest(url: url)) }
        if isPaused { webView.pauseAllMediaPlayback { } }
    }
}
#elseif canImport(AppKit)
import AppKit
extension YouTubeWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.drawsBackground = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url { webView.load(URLRequest(url: url)) }
        if isPaused { webView.pauseAllMediaPlayback { } }
    }
}
#endif

#Preview {
    // Vorschau mit simuliertem Live-Status
    let checker = YouTubeLiveChecker()
    return NavigationStack {
        YouTubeLiveView(checker: checker)
    }
    .preferredColorScheme(.dark)
}
#endif
