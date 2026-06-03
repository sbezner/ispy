# I Spy: Colors 🎨📸

A single-player **iOS / iPadOS** game for little kids (built for a 5-year-old).
The app spies a color — *"I spy something **BLUE**!"* — the child points the
camera at a real object and taps the big shutter. The app checks **on-device**
whether the photo really contains that color and whether it's a **new** object
they haven't already found this game. Match a new object → ⭐️ celebration and a
fresh color.

Built in **SwiftUI**, universal (iPhone + iPad), **iOS 17+**, **no third-party
dependencies**.

---

## Open & run

1. Open `ISpyColors.xcodeproj` in **Xcode 16 or newer**.
2. Select the **ISpyColors** scheme.
3. Pick a target device:
   - **Physical iPhone/iPad is required to actually play** — the Simulator has no
     real camera. Plug in a device, select it, set your Team under
     *Signing & Capabilities* (the bundle id is `com.example.ISpyColors`; change
     it to something unique to you), and press **⌘R**.
   - The Simulator still builds and runs the app and the unit tests; the camera
     preview just won't show a live image there.
4. First launch asks for **camera permission** — tap **Allow**.

### Run the tests

Press **⌘U** (or *Product ▸ Test*). The unit tests live in **ISpyColorsTests**:

- `ColorDetectorTests` — pure color logic (no camera/device needed): solid blue
  passes "blue", solid red fails "blue", a mixed image with a blue region passes,
  scattered blue noise fails the contiguity check, white/black via brightness, and
  every palette color matches its own swatch.
- `DuplicateDetectorTests` — Vision feature prints: the same image vs. itself is a
  duplicate; two clearly different images are not; the threshold is shown to be
  tunable.
- `GameRulesTests` — the turn-verdict truth table, plus an end-to-end check
  (real Vision) that the **same object photographed twice awards exactly one
  star** while a **different object of the same color is accepted** — driving the
  same `DuplicateDetector` + `GameRules` path the game uses, minus the camera.

---

## 🎛️ The two thresholds you'll want to tune

Both knobs are plain parameters with defaults — change the defaults, or pass new
values where the detectors are constructed in
`ISpyColors/Game/GameViewModel.swift`.

### 1. Color match % — how much of the photo must be the target color

**File:** `ISpyColors/Detection/ColorDetector.swift`

```swift
public var minMatchFraction:    Double  // default 0.03  (≈ 3% of the image)
public var minBlobFraction:     Double  // default 0.02  (largest contiguous blob)
public var minChromaSaturation: Double  // default 0.20  (how "colorful" a pixel must be)
public var minChromaValue:      Double  // default 0.18  (how bright a pixel must be)
```

These defaults are intentionally **lenient** (relaxed in response to play-testing):
a small patch of the color anywhere in a busy photo counts, and a wide range of
shades — pale pastels through deep/dark — all match.

- `minMatchFraction` is the headline "color %" knob. Raise it to demand a bigger
  splash of color; lower it to be even more forgiving.
- `minBlobFraction` is the anti-noise guard: the matching pixels must form one
  contiguous blob this big, so a room speckled with tiny dots won't pass.
- `minChromaSaturation` / `minChromaValue` set how colorful/bright a pixel must
  be to count. **Lower** them to accept more washed-out or darker shades; raise
  them if too many near-gray things match. (White uses `s ≤ 0.22, v ≥ 0.72` and
  black uses `v ≤ 0.28` — also relaxed — in `pixel(_:matches:)`.)

### 2. Duplicate distance — how different a new object must be

**File:** `ISpyColors/Detection/DuplicateDetector.swift`

```swift
public var duplicateThreshold: Float  // default 0.30
```

Vision feature-print distance is ~0 for identical photos and grows with visual
difference. If the nearest stored object is **closer** than `duplicateThreshold`,
it's treated as a duplicate ("You already found that one!"). **Lower** it to be
stricter about what counts as the same object; **raise** it to more aggressively
reject near-duplicates.

---

## Audio (designed for a 5-year-old)

- **Spoken color announcement.** Every time a new color is chosen — on first
  launch, on **New Game**, and after each win — the app says *"I spy something
  BLUE!"* out loud using Apple's built-in `AVSpeechSynthesizer` (text-to-speech,
  slightly higher pitch + slower rate). No voice clips are bundled; it works for
  all nine colors automatically.
- **Win / try-again sounds.** A fun jingle on a win and a gentle sound on a miss,
  played from bundled **CC0 (public-domain)** audio in
  `ISpyColors/Resources/Sounds/` (`win.m4a`, `fail.m4a`, from
  [Kenney](https://kenney.nl/assets)). If those files are missing the app falls
  back to a built-in system sound, so it always makes noise.
- **Swap in your own:** drop a `win.m4a` / `fail.m4a` into `Resources/Sounds/`
  (great CC0 sources: [Kenney](https://kenney.nl/assets),
  [Mixkit](https://mixkit.co/free-sound-effects/),
  [Pixabay](https://pixabay.com/sound-effects/)). All audio lives in
  `Game/SoundEffects.swift`; the announcement wiring is in `GameViewModel`
  (`announceColor()`).

## How it works

```
Announce color ─▶ live camera ─▶ shutter ─▶ analyze photo
                                              ├─ COLOR CHECK  (ColorDetector, pure)
                                              └─ DUP CHECK    (DuplicateDetector, Vision)
   ┌───────────────── PASS: ⭐️ + store object + new color
   ├───────────────── FAIL color: wiggle, same color
   └───────────────── FAIL duplicate: "find a NEW one!", same color
```

- **Color check** (`ColorDetector.swift`): the photo is downsampled to ~100×100
  (`ImageAnalyzer.swift`), each pixel converted RGB→HSV, and pixels are counted
  inside the target color's hue/saturation/brightness bands. White/black/gray are
  decided by **saturation + brightness**, not hue. A PASS needs enough matching
  pixels **and** a single contiguous blob (4-connected flood fill) — not scattered
  noise.
- **Duplicate check** (`DuplicateDetector.swift`): on each color-PASS a Vision
  `VNFeaturePrintObservation` is generated and compared (`computeDistance`)
  against every feature print stored **this session**. Below threshold → duplicate;
  otherwise it's new and its print is stored.
- **Session scope:** the found-objects list and their feature prints are cleared
  by **New Game** (the ↻ button). Only the **lifetime star count** persists
  (via `@AppStorage`).
- **Camera lifecycle:** the `AVCaptureSession` is stopped when the app
  backgrounds and restarted when it returns to the foreground (see
  `ContentView`'s `scenePhase` handler and `CameraController.start()/stop()`), so
  it survives backgrounding cleanly. All session mutation runs on a dedicated
  serial queue.

---

## Project layout

```
ISpyColors/
├─ ISpyColors.xcodeproj
├─ ISpyColors/
│  ├─ ISpyColorsApp.swift            App entry (@main)
│  ├─ Game/
│  │  ├─ ContentView.swift           The single game screen (UI/layout)
│  │  ├─ GameViewModel.swift         Game loop: color + duplicate checks, scoring
│  │  ├─ GameColor+UI.swift          SwiftUI swatch colors (kept out of the pure logic)
│  │  └─ SoundEffects.swift          System sounds + haptics
│  ├─ Camera/
│  │  ├─ CameraController.swift      AVCaptureSession + photo capture (rear camera)
│  │  └─ CameraPreviewView.swift     SwiftUI live-preview wrapper
│  ├─ Detection/
│  │  ├─ ColorDetector.swift         ⭐ PURE color logic — no UIKit/Vision/CoreGraphics
│  │  ├─ ImageAnalyzer.swift         CGImage → downsample → [RGBPixel] bridge
│  │  ├─ DuplicateDetector.swift     Vision feature-print generation + distance
│  │  └─ GameRules.swift             PURE turn verdict (win/colorFail/duplicateFail)
│  └─ Resources/
│     ├─ Info.plist                  Camera usage string + portrait lock
│     ├─ Assets.xcassets             App icon / accent color
│     └─ Sounds/                     win.m4a / fail.m4a (CC0) + CREDITS.txt
└─ ISpyColorsTests/
   ├─ ColorDetectorTests.swift
   └─ DuplicateDetectorTests.swift
```

### Portability note

`ColorDetector.swift` imports **only Foundation** — no UIKit, Vision, or
CoreGraphics. All the color math (RGB→HSV, hue bands, contiguous-blob flood fill)
operates on plain `[RGBPixel]` arrays, so the algorithm could be re-implemented on
Android with minimal rework. The only Apple-specific bridge (`ImageAnalyzer.swift`)
is deliberately separate.

---

## Orientation

The app is **locked to portrait** for simplicity. To allow landscape later, add
`UIInterfaceOrientationLandscapeLeft` / `…Right` to the
`UISupportedInterfaceOrientations` arrays in
`ISpyColors/Resources/Info.plist`.

---

## Out of scope (future): multiplayer / "rooms"

Multiplayer is intentionally **not** built. The natural hook points are marked
`// MULTIPLAYER HOOK` in `GameViewModel.swift`:

- `pickNewColor()` — in a shared "room", the target color would be assigned by the
  host/session instead of chosen randomly per device.
- `registerWin(...)` — a win would also broadcast to other players, and
  `foundObjects` / `featurePrints` would sync per-player.
```
