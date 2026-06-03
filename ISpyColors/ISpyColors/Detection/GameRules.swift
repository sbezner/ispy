//
//  GameRules.swift
//  ISpyColors
//
//  PURE turn-outcome logic, deliberately separate from GameViewModel (which is
//  tied to UIKit/Vision). Keeping the decision here makes the core game rule —
//  "a turn is a win only if the color matches AND it's not a duplicate" —
//  unit-testable without a camera or a view model, and reusable if the loop is
//  ever ported elsewhere.
//

import Foundation

/// The result of evaluating one captured photo.
public enum TurnOutcome: Equatable, Sendable {
    case win
    case colorFail
    case duplicateFail
}

public enum GameRules {
    /// The single source of truth for what a turn yields.
    ///
    /// - A failed color check is always a `colorFail` (the duplicate check never
    ///   even runs in that case — you can't "already have found" something that
    ///   doesn't match).
    /// - A passing color check that matches an object already found this session
    ///   is a `duplicateFail`.
    /// - Otherwise it's a `win`.
    ///
    /// Only `.win` awards a star and stores the object, which is what guarantees
    /// "the same object photographed twice awards exactly one star".
    public static func outcome(colorPassed: Bool, isDuplicate: Bool) -> TurnOutcome {
        guard colorPassed else { return .colorFail }
        return isDuplicate ? .duplicateFail : .win
    }

    /// Convenience: does this outcome award a star / get stored?
    public static func awardsStar(_ outcome: TurnOutcome) -> Bool {
        outcome == .win
    }
}
