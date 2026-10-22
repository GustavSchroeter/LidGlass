# LidGlass

Native macOS-App (Swift 6 / SwiftUI, macOS 14+). Beim Zuklappen des MacBook-Deckels wird ein Bildschirmfoto des eingebauten Displays als Vollbild-Overlay gezeigt und passend zum Deckelwinkel perspektivisch gekippt, unscharf und abgedunkelt – das Bild scheint aufrecht stehen zu bleiben, während sich der Bildschirm darüber schließt. Kein Audio, kein Eingriff in den Ruhezustand.

## Ordnerstruktur

```
LidGlass/
├── .github/workflows/build.yml      CI-Build + Release (optional)
├── .gitignore
├── Info.plist                       liegt bewusst außerhalb des synchronisierten Ordners
├── README.md
├── LidGlass.xcodeproj/
│   ├── project.pbxproj              Xcode-16-Format, File-System-Synchronized-Group
│   └── project.xcworkspace/contents.xcworkspacedata
└── LidGlass/                        ← synchronisierter Ordner: neue Dateien landen automatisch im Target
    ├── LidGlassApp.swift            App, AppModel (Singleton), AppDelegate
    ├── LidAngleSensor.swift         IOKit-HID-Deckelwinkel (@Observable)
    ├── EffectSettings.swift         Einstellungen (UserDefaults)
    ├── ScreenCapturer.swift         ScreenCaptureKit-Screenshot, Built-in-Display
    ├── OverlayWindow.swift          Vollbild-Overlay mit 3D-Transform, Blur, Abdunkeln
    ├── LidEffectController.swift    State Machine idle → capturing → showing → fading
    ├── ContentView.swift            Hauptfenster (Winkel + Einstellungen)
    └── MenuBarView.swift            Menüleisten-Menü
```

## Bauen in Xcode

1. Xcode 16 oder neuer installieren (empfohlen: Xcode 26, wegen `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`; alle Klassen sind zusätzlich explizit `@MainActor`, daher baut es auch mit Xcode 16).
2. `LidGlass.xcodeproj` öffnen.
3. Signierung ist bereits auf **Sign to Run Locally** (ad hoc, `CODE_SIGN_IDENTITY = -`, kein Team) gestellt – kein Developer-Account nötig.
4. ⌘R zum Starten, oder für eine fertige App: *Product → Archive* bzw. im Terminal:

```bash
xcodebuild -project LidGlass.xcodeproj -target LidGlass -configuration Release \
  SYMROOT="$PWD/build" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
open build/Release
```

`build/Release/LidGlass.app` nach `/Applications` ziehen.

## Bauen ohne Mac (GitHub Actions)

Repository auf GitHub hochladen (Branch `main`). Der Workflow baut eine Universal-App (arm64 + x86_64), zippt sie und veröffentlicht sie als Release **latest**. Manuell starten: *Actions → Build LidGlass → Run workflow*.

## Erster Start

1. Die App ist nur ad hoc signiert, Gatekeeper blockiert sie daher beim ersten Öffnen. Entweder
   - **Systemeinstellungen → Datenschutz & Sicherheit → „Trotzdem öffnen“**, oder
   - im Terminal: `xattr -cr /Applications/LidGlass.app`
2. Im Fenster rechts **„Allow Screen Recording…“** klicken und LidGlass unter *Systemeinstellungen → Datenschutz & Sicherheit → Bildschirm- & Systemaudioaufnahme* erlauben.
3. **LidGlass beenden und neu starten** (macOS übernimmt die Berechtigung erst nach einem Neustart der App).
4. „Animate when closing the lid“ einschalten, mit **Preview** testen, dann den Deckel langsam zuklappen.

Hinweise:
- Wird „Sensor not available“ angezeigt, hat dieser Mac keinen auslesbaren Deckelwinkel-Sensor (z. B. manche M1-Modelle). Die Vorschau funktioniert trotzdem.
- Nach jedem Neubau mit ad-hoc-Signatur kann macOS die Bildschirmaufnahme-Berechtigung erneut verlangen – dann den Eintrag in den Systemeinstellungen entfernen und neu erlauben.
- Das Fenster kann geschlossen werden; LidGlass läuft über das Menüleisten-Symbol weiter (dort auch „Quit“).
- Das Bildschirmfoto wird nur im Arbeitsspeicher gehalten und nach dem Ausblenden verworfen.
