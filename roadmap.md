# I Spy: Colors — Roadmap

Ideas for where to take the app next, grouped by effort. Nothing here is started yet —
this is a parking lot to come back to. Code lives in `ISpyColors/`; see
`ISpyColors/README.md` for architecture and tuning knobs.

---

## ⚠️ First, a clarification: "does it save the photos?"

Not to disk, and **not to the Photos library**. Here's exactly what happens today:

- When you find a new object, the app keeps an in-memory `UIImage` thumbnail and a
  Vision "feature print" of that photo (`GameViewModel.foundObjects` and
  `featurePrints`).
- These exist **only for the current game session** and are **cleared by New Game**
  (the ↻ button). They are never written to the filesystem, UserDefaults, or the
  camera roll.
- Their only purpose right now is the **duplicate check** ("you already found that
  one!"). The thumbnails are stored but **not shown anywhere** — see "Found-objects
  gallery" below.

So: no privacy concern (nothing leaves the device or persists), but also nothing to
look at yet. The opportunity is to surface those thumbnails. If you ever *do* want to
persist them, that's a deliberate feature to add (and worth a parent-facing note).

---

## Quick wins (small, high reward)

- [ ] **Found-objects gallery.** Show the thumbnails already stored in
      `GameViewModel.foundObjects` as a filmstrip at the bottom — "look what I found!"
      Highest delight for the least work.
- [ ] **Show the photo + what it saw.** After a snap, briefly display the captured
      picture with the matched color region highlighted ("I see BLUE here!"). Makes the
      detection visible and teaches the color.
- [ ] **Flash/torch toggle.** Dim rooms hurt color detection; add a big sun button to
      turn on the torch (`AVCaptureDevice.torchMode`).
- [ ] **"Too hard — skip" button.** Let a kid get a new color without frustration if
      they can't find the current one.

## Bigger features

- [ ] **Parent settings screen.** Gear (hidden behind a tap-and-hold so a 5-year-old
      can't wander in) with: difficulty (wire up the already-tunable color thresholds),
      mute toggle, reset stars.
- [ ] **Game modes.** "Find 3 blue things," a gentle timer mode, or shapes instead of
      colors. The `GameRules` / `GameViewModel` loop is clean enough to extend.
- [ ] **Celebration variety.** Rotate win jingles and spoken lines ("You got it!",
      "Amazing!") so it doesn't get repetitive (`SoundEffects.swift`).
- [ ] **Multiplayer / "rooms."** Scoped out for now, but the hook points are already
      marked `// MULTIPLAYER HOOK` in `GameViewModel.swift` (pass-and-play or two phones).

## Ship-it polish (if it ever goes to the App Store)

- [ ] **GitHub Actions CI.** Auto-run the test suite on every push. (Note: Vision
      feature-print tests skip on the simulator and only run on a device — see
      `VisionTestSupport.swift` — so CI on a simulator will skip those, which is expected.)
- [ ] **Accessibility pass.** VoiceOver labels, Dynamic Type, larger-text support.
- [ ] **Launch screen + App Store assets.** Real launch screen (currently blank) and
      screenshots.
- [ ] **Localization.** TTS already supports other languages; the few UI strings could
      be localized.

---

## Where to tune things (quick reference)

| Want to change… | File |
|---|---|
| How lenient color matching is (area %, shades) | `Detection/ColorDetector.swift` (`minMatchFraction`, `minBlobFraction`, `minChromaSaturation`, `minChromaValue`) |
| How different a "new" object must be | `Detection/DuplicateDetector.swift` (`duplicateThreshold`) |
| Win/fail sounds, spoken voice (rate/pitch) | `Game/SoundEffects.swift` (+ swap files in `Resources/Sounds/`) |
| The win/fail/announce wiring | `Game/GameViewModel.swift` |
| Layout / UI | `Game/ContentView.swift` |

My top three picks for impact-per-effort: **found-objects gallery**, **flash/torch
toggle**, **GitHub Actions CI**.
