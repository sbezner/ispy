//
//  SoundEffects.swift
//  ISpyColors
//
//  Audio + haptic feedback for a 5-year-old:
//   • A spoken "I spy something BLUE!" via AVSpeechSynthesizer (text-to-speech),
//     so every color is announced out loud with no bundled voice clips.
//   • A fun win jingle and a gentle "try again" sound, played from bundled CC0
//     audio (Resources/Sounds/win.m4a, fail.m4a). If those files aren't found,
//     it falls back to a built-in system sound, so the app always makes noise.
//
//  @MainActor-isolated: it owns UIKit feedback generators + AVFoundation players
//  and is only ever called from main-actor UI/game code. That isolation also
//  makes the shared singleton concurrency-safe under Swift 6.
//

import AVFoundation
import AudioToolbox
import UIKit

@MainActor
final class SoundEffects {
    static let shared = SoundEffects()

    private let synthesizer = AVSpeechSynthesizer()
    private var players: [String: AVAudioPlayer] = [:]

    private init() {
        configureAudioSession()
        preload("win")
        preload("fail")
    }

    // MARK: Session

    private func configureAudioSession() {
        // .playback so feedback is heard even with the ring/silent switch off;
        // .duckOthers politely lowers any background music while we speak/chime.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            // Non-fatal — sounds may still play, or fall back to system sounds.
        }
    }

    // MARK: Bundled clips

    private func preload(_ name: String) {
        guard let url = soundURL(name) else { return }
        if let player = try? AVAudioPlayer(contentsOf: url) {
            player.prepareToPlay()
            players[name] = player
        }
    }

    /// Resources may be flattened into the bundle root or kept under "Sounds/"
    /// depending on how Xcode copies them — try both.
    private func soundURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "m4a", subdirectory: "Sounds")
            ?? Bundle.main.url(forResource: name, withExtension: "m4a")
    }

    private func play(_ name: String, systemFallback: SystemSoundID) {
        if let player = players[name] {
            player.currentTime = 0
            player.play()
        } else {
            AudioServicesPlaySystemSound(systemFallback)
        }
    }

    // MARK: Public feedback

    /// Fun jingle + success haptic for a win.
    func playWin() {
        play("win", systemFallback: 1025)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Gentle sound + soft haptic for a miss / duplicate.
    func playFail() {
        play("fail", systemFallback: 1053)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Shutter click on capture.
    func playShutter() {
        AudioServicesPlaySystemSound(1108)
    }

    // MARK: Spoken announcements

    /// Says "I spy something BLUE!" out loud in a friendly, slightly playful voice.
    func announce(color: GameColor) {
        speak("I spy something \(color.displayName)!")
    }

    private func speak(_ text: String) {
        // Cancel any in-flight utterance so colors don't pile up.
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.44            // a touch slower than default for a 5-year-old
        utterance.pitchMultiplier = 1.3  // higher + playful
        utterance.preUtteranceDelay = 0.05
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}
