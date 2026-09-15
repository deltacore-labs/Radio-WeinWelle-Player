# Radio Wein-Welle Player

iOS/macOS Radio-App für den Stream `https://stream.radio-wein-welle.de/radioweinwelle_high`.

## Bauen & Starten

### Simulator (iPhone)

```bash
# Bauen
xcodebuild \
  -project "Radio-WeinWelle-Player.xcodeproj" \
  -scheme "Radio-WeinWelle-Player" \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -configuration Debug \
  build

# App-Pfad ermitteln
APP=$(find ~/Library/Developer/Xcode/DerivedData/Radio-WeinWelle-Player-*/Build/Products/Debug-iphonesimulator -name "Radio-WeinWelle-Player.app" -maxdepth 1 | head -1)

# UDID des gestarteten Simulators
UDID=$(xcrun simctl list devices booted -j | python3 -c "import sys,json; d=json.load(sys.stdin)['devices']; print(next(v[0]['udid'] for v in d.values() if v))")

# Installieren & starten
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" deltacorelabs.Radio-WeinWelle-Player

# Screenshot
xcrun simctl io "$UDID" screenshot /tmp/radio_screenshot.png
```

### Echtes Gerät

In Xcode öffnen und auf Gerät deployen (Signing mit Team `A4HCRKN53K`).

## Projektstruktur

- `RadioPlayer.swift` — AVPlayer-Logik, Icecast-Polling, Shazam-Fallback
- `RadioStation.swift` — Stream-URL, Icecast-API-URL, Sendername
- `PlayerView.swift` — Haupt-UI mit animiertem Hintergrund
- `ShazamRecognizer.swift` — Song-Erkennung wenn Stream keine Metadaten liefert
- `Info.plist` — NSMicrophoneUsageDescription, UIBackgroundModes: audio, ATS-Ausnahme
- `Radio-WeinWelle-Player.entitlements` — Sandbox, Netzwerk, Mikrofon

## Bundle-ID

`deltacorelabs.Radio-WeinWelle-Player`

## Bekannte Eigenheiten

- `ShazamRecognizer.swift` ist doppelt in der Build-Phase eingetragen (gleiche UUID) — Xcode ignoriert das, aber es erzeugt eine Warnung.
- Der `StreamLoader` (custom AVAssetResourceLoader) wurde entfernt — AVPlayer spielt den HTTPS-Icecast-Stream direkt ohne Workaround.
- Shazam startet automatisch 15 Sekunden nach Play, wenn die Icecast-API keinen Titel liefert.
