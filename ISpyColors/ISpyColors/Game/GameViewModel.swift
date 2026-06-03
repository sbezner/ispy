//
//  GameViewModel.swift
//  ISpyColors
//
//  The game loop brain. Announces a target color, analyzes each captured photo
//  for (1) color match and (2) session-uniqueness, and drives celebration /
//  try-again feedback.
//
//  SESSION SCOPE: foundObjects and featurePrints are cleared by newGame().
//  Lifetime stars are persisted separately via @AppStorage in the view layer;
//  this view model just signals a win through `onAwardStar`.
//
//  MULTIPLAYER HOOK (future): a "room" would wrap this model — the target color
//  would be assigned by a shared session/host instead of pickNewColor(), and
//  foundObjects/featurePrints would sync per-player. See pickNewColor() and
//  registerWin() for the natural seams.
//

import Combine
import Foundation
import SwiftUI
import Vision

@MainActor
final class GameViewModel: ObservableObject {

    /// One object the player has successfully found this session.
    struct FoundObject: Identifiable {
        let id = UUID()
        let color: GameColor
        let thumbnail: UIImage
    }

    /// What happened on the last capture attempt. The cases live in the pure,
    /// testable `GameRules` module; this typealias keeps call sites concise.
    typealias Outcome = TurnOutcome

    // MARK: Published state

    @Published private(set) var targetColor: GameColor
    @Published private(set) var foundObjects: [FoundObject] = []
    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastOutcome: Outcome?
    @Published var message: String = ""

    /// Pulsed true briefly to trigger the celebration animation.
    @Published var celebrate = false
    /// Toggled to trigger the "try again" wiggle.
    @Published var wiggle = false

    // MARK: Collaborators

    let camera: CameraController
    private let analyzer: ImageAnalyzer
    private let duplicateDetector: DuplicateDetector

    /// Session-scoped feature prints, parallel to successful foundObjects.
    private var featurePrints: [VNFeaturePrintObservation] = []

    /// Called once per win so the view can bump the @AppStorage lifetime star count.
    var onAwardStar: () -> Void = {}

    /// Forward the camera's @Published changes (e.g. permission/status) up to
    /// this view model so SwiftUI re-renders when the nested object changes.
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init(camera: CameraController? = nil,
         analyzer: ImageAnalyzer = ImageAnalyzer(),
         duplicateDetector: DuplicateDetector = DuplicateDetector()) {
        // CameraController is @MainActor-isolated, so it must be constructed in a
        // main-actor context. This init body IS main-actor-isolated (the class is
        // @MainActor), but a DEFAULT ARGUMENT like `camera = CameraController()`
        // would be evaluated in a nonisolated context and fail to compile under
        // Swift 6. So we default the parameter to nil and build it here, while
        // still allowing a camera to be injected for tests.
        let camera = camera ?? CameraController()
        self.camera = camera
        self.analyzer = analyzer
        self.duplicateDetector = duplicateDetector
        // Deterministic-free first color.
        self.targetColor = GameColor.allCases.randomElement() ?? .blue
        self.message = Self.spyMessage(for: targetColor)

        // Re-publish whenever the camera's observable state changes.
        camera.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: Game lifecycle

    /// Clears all SESSION state and starts fresh.
    func newGame() {
        foundObjects.removeAll()
        featurePrints.removeAll()
        lastOutcome = nil
        celebrate = false
        wiggle = false
        pickNewColor()
        announceColor()
    }

    /// Speak the current target color out loud ("I spy something BLUE!").
    /// Called on first appearance, on New Game, and (after the jingle) on a win.
    func announceColor() {
        SoundEffects.shared.announce(color: targetColor)
    }

    /// Speak the current color after a short delay, so it follows the win jingle
    /// instead of talking over it.
    private func announceColorAfterWin() {
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self.announceColor()
        }
    }

    /// MULTIPLAYER HOOK: replace with host-assigned color in a room.
    private func pickNewColor() {
        // Avoid immediately repeating the same color.
        var next = GameColor.allCases.randomElement() ?? .blue
        if GameColor.allCases.count > 1 {
            while next == targetColor {
                next = GameColor.allCases.randomElement() ?? next
            }
        }
        targetColor = next
        message = Self.spyMessage(for: targetColor)
    }

    // MARK: The core turn

    /// Capture a photo and run color + duplicate checks. Updates published state
    /// and returns the outcome.
    @discardableResult
    func takePhoto() async -> Outcome {
        guard !isAnalyzing else { return lastOutcome ?? .colorFail }
        isAnalyzing = true
        defer { isAnalyzing = false }

        guard let cgImage = await camera.capturePhoto() else {
            lastOutcome = .colorFail
            message = "Oops! Let's try that again."
            triggerWiggle()
            return .colorFail
        }

        // 1. COLOR CHECK (pure, on-device).
        let colorPassed = analyzer.analyze(cgImage, target: targetColor)?.passed ?? false

        // 2. DUPLICATE CHECK (Vision feature print) — only meaningful on a color pass.
        // If Vision fails entirely we treat it as "not a duplicate" rather than
        // punish the kid.
        let candidate = colorPassed ? try? duplicateDetector.generateFeaturePrint(for: cgImage) : nil
        let isDuplicate = candidate.map {
            duplicateDetector.evaluate(candidate: $0, against: featurePrints).isDuplicate
        } ?? false

        // 3. Single source of truth for the verdict.
        let outcome = GameRules.outcome(colorPassed: colorPassed, isDuplicate: isDuplicate)
        lastOutcome = outcome

        switch outcome {
        case .colorFail:
            message = "Hmm, I don't see \(targetColor.displayName). Try again!"
            triggerWiggle()
            SoundEffects.shared.playFail()
        case .duplicateFail:
            message = "You already found that one!\nFind a NEW \(targetColor.displayName) thing!"
            triggerWiggle()
            SoundEffects.shared.playFail()
        case .win:
            // New object -> remember its print for the rest of the session.
            if let candidate { featurePrints.append(candidate) }
            registerWin(image: cgImage)
        }
        return outcome
    }

    /// MULTIPLAYER HOOK: in a room, a win would also broadcast to other players.
    private func registerWin(image: CGImage) {
        let thumb = UIImage(cgImage: image)
        foundObjects.append(FoundObject(color: targetColor, thumbnail: thumb))
        lastOutcome = .win
        message = "You found \(targetColor.displayName)! ⭐️"
        onAwardStar()
        SoundEffects.shared.playWin()
        triggerCelebrate()
        pickNewColor()
        announceColorAfterWin()
    }

    // MARK: Feedback pulses

    private func triggerCelebrate() {
        celebrate = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run { self.celebrate = false }
        }
    }

    private func triggerWiggle() {
        wiggle.toggle()
    }

    // MARK: Copy

    static func spyMessage(for color: GameColor) -> String {
        "I spy something\n\(color.displayName)!"
    }
}
