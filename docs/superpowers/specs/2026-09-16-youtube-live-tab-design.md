# Design: YouTube Live-Stream Tab

**Datum:** 2026-09-16  
**Ziel:** Zeige den YouTube-Livestream von Radio Wein-Welle direkt in der App an, wenn er aktiv ist.

---

## Context

Radio Wein-Welle überträgt gelegentlich Live-Events auf YouTube  
(`https://www.youtube.com/@RadioWeinWelle/streams`, Channel-ID: `UClyAqSF-AdlRUerBG4HZf9w`).  
Die App soll erkennen, ob gerade ein Livestream läuft, einen farbigen Badge auf dem Tab anzeigen, und den Stream direkt in der App abspielbar machen — ohne API-Key.

---

## Architektur

### 1. `YouTubeLiveChecker` (neues File)

`@Observable @MainActor` Klasse. Zuständig für:
- Periodisches Polling (alle **5 Minuten**) von `https://www.youtube.com/@RadioWeinWelle/live`
- HTML-Parsing: Suche nach `"isLiveNow":true` im eingebetteten JSON der Seite
- Extrahiert die `videoId` des aktiven Streams falls vorhanden
- Publiziert `isLive: Bool` und `videoID: String?`

User-Agent im Request: `"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X)"` — nötig, damit YouTube kein redirect-only ausliefert.

Erstes Polling sofort beim Init, danach alle 5 Minuten via `Task.sleep`.

### 2. `YouTubeLiveView` (neues File)

SwiftUI-View, nur für iOS/macOS (`#if !os(tvOS)`):
- Wenn `isLive == true`: WKWebView mit URL `https://www.youtube-nocookie.com/embed/live_stream?channel=UClyAqSF-AdlRUerBG4HZf9w&autoplay=1&playsinline=1&rel=0` — YouTube wählt den aktiven Stream intern aus
- Wenn `isLive == false`: Placeholder-Card im App-Stil (dunkler Hintergrund, roter Akzentkreis, Text "Kein Livestream aktiv", Link-Button zur YouTube-Seite)
- Oben: kleiner Hinweis-Text "Zuletzt geprüft: HH:MM Uhr" + Refresh-Button

WKWebView via `UIViewRepresentable`/`NSViewRepresentable` (analog zu `WebsiteView.swift`).

### 3. `ContentView.swift` (modifiziert)

Neuer 4. Tab im `TabView` (nur nicht-tvOS):
- Label: "Live", Icon: `play.rectangle.fill`
- Badge (rotes Overlay-Dot via `.badge()` oder custom Overlay) wenn `checker.isLive == true`
- `YouTubeLiveChecker` als `@State private var` in `ContentView` (lifetime = App-lifetime)

---

## Datenfluss

```
ContentView
  └── @State YouTubeLiveChecker
        ├── isLive: Bool
        └── videoID: String?
              └── YouTubeLiveView(checker:)
                    ├── [live] WKWebView(youtube-nocookie embed)
                    └── [nicht live] Placeholder + Link
```

---

## Live-Erkennung (kein API-Key nötig)

GET `https://www.youtube.com/@RadioWeinWelle/live` liefert die aktuelle Kanalseite als HTML.  
YouTube bettet strukturiertes JSON in `<script>` Tags ein. Darin suchen wir ausschließlich nach:
- `"isLiveNow":true` → Stream aktiv, `isLive = true`
- Kein Match → `isLive = false`

Für den Embed-Player brauchen wir keine Video-ID — `live_stream?channel=CHANNEL_ID` wählt den aktiven Stream intern aus.

Falls die Anfrage fehlschlägt (kein Netz, Timeout): `isLive` bleibt unverändert, kein Crash.

---

## Audio-Konflikt

Kein Auto-Pause des Radio-Streams beim Tab-Wechsel. YouTube-Embeds starten stumm (Browser-Policy für Autoplay). Der Nutzer entscheidet selbst, was er hört. Das ist das gleiche Verhalten wie im Tab "Webseite".

---

## ATS / Netzwerk

Alle URLs sind HTTPS. Keine ATS-Ausnahme nötig. Die vorhandene Entitlement `com.apple.security.network.client = true` reicht.

---

## Dateien

| Aktion | Datei |
|--------|-------|
| Neu erstellen | `YouTubeLiveChecker.swift` |
| Neu erstellen | `YouTubeLiveView.swift` |
| Modifizieren | `Radio-WeinWelle-Player/ContentView.swift` |

---

## Verifikation

1. App im Simulator starten
2. "Live"-Tab öffnen → Placeholder wird angezeigt (kein aktiver Stream)
3. Manueller Test mit Live-Stream: In `YouTubeLiveChecker` `isLive = true` und eine Test-Video-ID setzen → WKWebView lädt das YouTube-Video
4. Badge auf Tab-Icon erscheint wenn `isLive == true`
5. Kein Crash wenn offline
