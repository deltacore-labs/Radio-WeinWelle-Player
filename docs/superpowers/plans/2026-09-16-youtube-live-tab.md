# YouTube Live Tab — Implementierungsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Einen vierten Tab "Live" in der App einbauen, der einen YouTube-Livestream von Radio Wein-Welle anzeigt, sobald einer aktiv ist — mit Tab-Badge und automatischem Polling alle 5 Minuten.

**Architecture:** `YouTubeLiveChecker` ist eine `@Observable @MainActor`-Klasse, die `https://www.youtube.com/@RadioWeinWelle/live` per HTML-Parsing auf `"isLiveNow":true` prüft. `ContentView` erstellt den Checker als `@State` und steuert das Polling per `.task`. `YouTubeLiveView` zeigt entweder einen YouTube-Embed via WKWebView oder einen Placeholder.

**Tech Stack:** SwiftUI, WebKit (WKWebView), Foundation (URLSession), `@Observable` (iOS 17+ Macro), Deployment Target iOS 18.6

---

## Dateiübersicht

| Aktion | Datei | Verantwortung |
|--------|-------|---------------|
| Neu erstellen | `YouTubeLiveChecker.swift` | HTTP-Polling, Live-Status-Erkennung |
| Neu erstellen | `YouTubeLiveView.swift` | UI: WKWebView-Embed + Placeholder |
| Modifizieren | `Radio-WeinWelle-Player/ContentView.swift` | 4. Tab + Checker-State + Polling-Task |

---

## Task 1: YouTubeLiveChecker erstellen

**Files:**
- Create: `YouTubeLiveChecker.swift` (Projektroot, neben `RadioPlayer.swift`)

- [ ] **Step 1: Datei erstellen**

Neue Datei `YouTubeLiveChecker.swift` im Projektroot anlegen:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class YouTubeLiveChecker {
    private(set) var isLive = false
    private(set) var lastChecked: Date?

    func checkLiveStatus() async {
        guard let url = URL(string: "https://www.youtube.com/@RadioWeinWelle/live") else { return }
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 15
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let html = String(data: data, encoding: .utf8) ?? ""
            isLive = html.contains("\"isLiveNow\":true")
            lastChecked = Date()
        } catch {
            // Netz nicht erreichbar — vorherigen Status behalten
        }
    }
}
```

- [ ] **Step 2: Datei in Xcode-Projekt einbinden**

In Xcode: `File → Add Files to "Radio-WeinWelle-Player"...` → `YouTubeLiveChecker.swift` auswählen → Target `Radio-WeinWelle-Player` ankreuzen → Add.

Alternativ per `pbxproj`-Eintrag: Da das Projekt andere Swift-Dateien als explizite `PBXFileReference` im Root hat (nicht als `PBXFileSystemSynchronizedRootGroup`), muss die Datei manuell eingebunden werden. Am sichersten in Xcode.

- [ ] **Step 3: Build-Test**

```bash
xcodebuild \
  -project "Radio-WeinWelle-Player.xcodeproj" \
  -scheme "Radio-WeinWelle-Player" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -configuration Debug \
  build 2>&1 | grep -E "(error:|warning:|BUILD)"
```

Erwartetes Ergebnis: `BUILD SUCCEEDED` ohne neue Fehler.

- [ ] **Step 4: Commit**

```bash
git add YouTubeLiveChecker.swift Radio-WeinWelle-Player.xcodeproj/project.pbxproj
git commit -m "feat: add YouTubeLiveChecker for YouTube live stream detection"
```

---

## Task 2: YouTubeLiveView erstellen

**Files:**
- Create: `YouTubeLiveView.swift` (Projektroot, neben `WebsiteView.swift`)

- [ ] **Step 1: Datei erstellen**

Neue Datei `YouTubeLiveView.swift` im Projektroot anlegen:

```swift
#if !os(tvOS)
import SwiftUI
import WebKit

struct YouTubeLiveView: View {
    let checker: YouTubeLiveChecker

    private let channelURL = URL(string: "https://www.youtube.com/@RadioWeinWelle/streams")!
    private let embedURL  = URL(string: "https://www.youtube-nocookie.com/embed/live_stream?channel=UClyAqSF-AdlRUerBG4HZf9w&autoplay=1&playsinline=1&rel=0")!

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if checker.isLive {
                YouTubeWebView(url: embedURL)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                noLivePlaceholder
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await checker.checkLiveStatus() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .tint(.white)
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
    }
}
#elseif canImport(AppKit)
import AppKit
extension YouTubeWebView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: config)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url { webView.load(URLRequest(url: url)) }
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
```

- [ ] **Step 2: Datei in Xcode einbinden**

In Xcode: `File → Add Files to "Radio-WeinWelle-Player"...` → `YouTubeLiveView.swift` auswählen → Target ankreuzen → Add.

- [ ] **Step 3: Build-Test**

```bash
xcodebuild \
  -project "Radio-WeinWelle-Player.xcodeproj" \
  -scheme "Radio-WeinWelle-Player" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -configuration Debug \
  build 2>&1 | grep -E "(error:|warning:|BUILD)"
```

Erwartetes Ergebnis: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add YouTubeLiveView.swift Radio-WeinWelle-Player.xcodeproj/project.pbxproj
git commit -m "feat: add YouTubeLiveView with WKWebView embed and no-live placeholder"
```

---

## Task 3: ContentView um 4. Tab erweitern

**Files:**
- Modify: `Radio-WeinWelle-Player/ContentView.swift`

- [ ] **Step 1: ContentView anpassen**

Die Datei `Radio-WeinWelle-Player/ContentView.swift` komplett ersetzen:

```swift
import SwiftUI

struct ContentView: View {
    @Environment(RadioPlayer.self) private var player
    @State private var liveChecker = YouTubeLiveChecker()

    var body: some View {
        #if os(tvOS)
        PlayerView()
        #else
        TabView {
            PlayerView()
                .tabItem { Label("Player", systemImage: "dot.radiowaves.left.and.right") }

            WebsiteView(url: player.station.websiteURL)
                .tabItem { Label("Webseite", systemImage: "globe") }

            NavigationStack {
                YouTubeLiveView(checker: liveChecker)
                    .navigationTitle("YouTube Live")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem { Label("Live", systemImage: "play.rectangle.fill") }
            .badge(liveChecker.isLive ? "LIVE" : nil)

            LegalInfoView()
                .tabItem { Label("Info", systemImage: "info.circle") }
        }
        .tint(Color(red: 0.757, green: 0.184, blue: 0.212))
        .task {
            await liveChecker.checkLiveStatus()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await liveChecker.checkLiveStatus()
            }
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environment(RadioPlayer(station: .weinWelle))
}
```

**Hinweis:** `YouTubeLiveView` wird nur auf Nicht-tvOS-Plattformen kompiliert (`#if !os(tvOS)` in der Datei). Da der Tab ebenfalls im `#else`-Zweig steht, gibt es keinen Kompilierfehler auf tvOS.

- [ ] **Step 2: Build-Test**

```bash
xcodebuild \
  -project "Radio-WeinWelle-Player.xcodeproj" \
  -scheme "Radio-WeinWelle-Player" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -configuration Debug \
  build 2>&1 | grep -E "(error:|warning:|BUILD)"
```

Erwartetes Ergebnis: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add "Radio-WeinWelle-Player/ContentView.swift"
git commit -m "feat: add YouTube Live tab with live badge and 5-min polling"
```

---

## Task 4: Manueller Test im Simulator

- [ ] **Step 1: App starten**

```bash
# Simulator booten falls nötig
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null; open -a Simulator

# Build & install
xcodebuild \
  -project "Radio-WeinWelle-Player.xcodeproj" \
  -scheme "Radio-WeinWelle-Player" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -configuration Debug \
  build

APP=$(find ~/Library/Developer/Xcode/DerivedData/Radio-WeinWelle-Player-*/Build/Products/Debug-iphonesimulator \
  -name "Radio-WeinWelle-Player.app" -maxdepth 1 | head -1)
UDID=$(xcrun simctl list devices booted -j | \
  python3 -c "import sys,json; d=json.load(sys.stdin)['devices']; print(next(v[0]['udid'] for v in d.values() if v))")

xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" deltacorelabs.Radio-WeinWelle-Player
```

- [ ] **Step 2: Placeholder prüfen**

"Live"-Tab antippen → Placeholder "Kein Livestream aktiv" mit Link-Button muss erscheinen (kein aktiver Stream gerade).

```bash
xcrun simctl io "$UDID" screenshot /tmp/live_placeholder.png && open /tmp/live_placeholder.png
```

Erwartetes Ergebnis: Dunkler Hintergrund, roter Kreis mit `play.slash.fill`-Icon, Text "Kein Livestream aktiv", Link-Button.

- [ ] **Step 3: Live-Simulation testen**

In `YouTubeLiveChecker.swift` temporär `isLive = true` setzen:

```swift
func checkLiveStatus() async {
    // TEMPORÄR für Test:
    isLive = true
    lastChecked = Date()
    return
    // ... restlicher Code
}
```

App neu bauen, "Live"-Tab öffnen → YouTube-Embed muss laden.

```bash
xcodebuild -project "Radio-WeinWelle-Player.xcodeproj" -scheme "Radio-WeinWelle-Player" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" -configuration Debug build 2>&1 | tail -5
xcrun simctl install "$UDID" "$APP" && xcrun simctl launch "$UDID" deltacorelabs.Radio-WeinWelle-Player
```

Screenshot:
```bash
xcrun simctl io "$UDID" screenshot /tmp/live_youtube.png && open /tmp/live_youtube.png
```

Erwartetes Ergebnis: WKWebView lädt `youtube-nocookie.com` Embed (ggf. "Kein Stream verfügbar" vom YouTube-Player selbst — das ist korrekt, da kein Stream aktiv).

- [ ] **Step 4: Testcode zurücksetzen**

Die temporäre `isLive = true` Zeile aus `YouTubeLiveChecker.swift` entfernen und neu bauen.

- [ ] **Step 5: Badge-Test**

Temporär `isLive = true` im Checker-Init setzen, App starten → Tab-Leiste muss "LIVE"-Badge auf dem "Live"-Tab zeigen.

Nach Verifikation zurücksetzen.

- [ ] **Step 6: Finaler Build & Commit**

```bash
git add YouTubeLiveChecker.swift
git commit -m "test: verify YouTube live tab — placeholder, embed, and badge all working"
```

---

## Notizen

- **YouTube-Channel-ID:** `UClyAqSF-AdlRUerBG4HZf9w`
- **Embed-URL nutzt `live_stream?channel=`:** YouTube wählt den aktiven Stream intern aus; bei keinem aktiven Stream zeigt der Embed eine eigene "Kein Livestream"-Meldung.
- **Polling nur per `.task` in ContentView:** Kein Retain-Cycle, korrekte SwiftUI-Lifecycle-Bindung.
- **tvOS:** Kein YouTube-Tab — `YouTubeLiveView.swift` ist komplett mit `#if !os(tvOS)` umgeben, der Tab ist nur im `#else`-Zweig von ContentView.
- **Audio-Konflikt:** Kein automatisches Pausieren des Radiostreams beim Tab-Wechsel — gleiche Verhalten wie "Webseite"-Tab.
