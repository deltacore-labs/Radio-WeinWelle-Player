# Radio Wein-Welle Player

iOS/macOS-App zum Hören von [Radio Wein-Welle](https://www.radio-wein-welle.de) — mit animiertem Hintergrund, Song-Anzeige und Lock-Screen-Integration.

## Features

- **Livestream** über HTTPS-Icecast (`radioweinwelle_high`)
- **Now Playing** — Titel und Künstler aus der Icecast-API (alle 15 s), als Fallback per ICY-Metadaten im Stream
- **ShazamKit-Fallback** — erkennt den Song direkt aus dem Stream-Audio via `MTAudioProcessingTap`, wenn weder API noch ICY-Metadaten einen Titel liefern
- **Cover-Art** via iTunes-Search-API (600×600 px)
- **Lock Screen / Control Center** — NowPlaying-Framework auf iOS/macOS 27+, `MPNowPlayingInfoCenter` auf älteren Versionen
- **Animierter Hintergrund** — weinrote Orbs, die sich beim Abspielen in Bewegung setzen; blurred Artwork-Hintergrund à la Apple Music
- **Marquee-Text** für lange Titel

## Voraussetzungen

| | Minimum |
|---|---|
| iOS | 17 |
| macOS | 14 |
| Xcode | 16 |
| Swift | 5.10 |

## Bauen & Starten

### Simulator

```bash
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
xcrun simctl launch  "$UDID" deltacorelabs.Radio-WeinWelle-Player
```

### Echtes Gerät

In Xcode öffnen, Signing-Team `A4HCRKN53K` auswählen und auf Gerät deployen.

## Projektstruktur

| Datei | Inhalt |
|---|---|
| `RadioPlayer.swift` | `AVPlayer`-Logik, Icecast-Polling, ICY-Metadaten, ShazamKit-Fallback, Lock-Screen-Integration |
| `RadioStation.swift` | Stream-URL, Website-URL, Icecast-API-URL |
| `PlayerView.swift` | Haupt-UI — Glasskarte, animierter Hintergrund, Marquee-Text, LIVE-Badge |
| `ShazamRecognizer.swift` | Song-Erkennung via `MTAudioProcessingTap` ohne Mikrofon |
| `NowPlayingInfo.swift` | Datenmodell für Titel, Künstler und Artwork-URL |
| `PlatformImage.swift` | `UIImage`/`NSImage`-Typaliase für Cross-Platform-Code |
| `LegalInfoView.swift` | Impressum / Rechtliches |
| `WebsiteView.swift` | In-App-Browser für die Senderwebsite |
| `Info.plist` | `NSMicrophoneUsageDescription`, `UIBackgroundModes: audio`, ATS-Ausnahme |
| `Radio-WeinWelle-Player.entitlements` | Sandbox, Netzwerk, Mikrofon |

## Metadaten-Pipeline

```
Stream startet
    │
    ├─► Icecast-API (alle 15 s) ──► Titel gefunden → Cover-Art via iTunes
    │
    ├─► ICY-Metadaten im Stream  ──► Titel gefunden → Cover-Art via iTunes
    │
    └─► nach 15 s ohne Titel:
        ShazamKit (MTAudioProcessingTap) ──► Match → Cover-Art via iTunes
```

## Bundle-ID

`deltacorelabs.Radio-WeinWelle-Player`

## Bekannte Eigenheiten

- `ShazamRecognizer.swift` ist doppelt in der Xcode-Build-Phase eingetragen (gleiche UUID) — funktioniert, erzeugt aber eine Warnung.
- Icecast-Encoding-Bug: Manche Titel werden als Mojibake (UTF-8 als Latin-1 gelesen) geliefert — `fixEncoding()` in `RadioPlayer.swift` korrigiert das.
