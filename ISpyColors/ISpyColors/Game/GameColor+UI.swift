//
//  GameColor+UI.swift
//  ISpyColors
//
//  SwiftUI presentation for the palette. Kept OUT of ColorDetector.swift so the
//  pure color logic stays framework-free.
//

import SwiftUI

extension GameColor {
    /// The big swatch color shown to the player.
    var swatch: Color {
        switch self {
        case .red:    return Color(red: 0.90, green: 0.16, blue: 0.16)
        case .orange: return Color(red: 1.00, green: 0.55, blue: 0.00)
        case .yellow: return Color(red: 1.00, green: 0.85, blue: 0.10)
        case .green:  return Color(red: 0.16, green: 0.74, blue: 0.30)
        case .blue:   return Color(red: 0.13, green: 0.45, blue: 0.95)
        case .purple: return Color(red: 0.60, green: 0.25, blue: 0.85)
        case .pink:   return Color(red: 1.00, green: 0.45, blue: 0.70)
        case .white:  return Color.white
        case .black:  return Color.black
        }
    }

    /// A readable text/border color to pair with the swatch.
    var contrastInk: Color {
        switch self {
        case .yellow, .white, .pink: return .black
        default: return .white
        }
    }
}
