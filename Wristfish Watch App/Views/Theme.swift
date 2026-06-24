//
//  Theme.swift
//  Wristfish — shared arcade styling (ocean palette).
//
//  🎨 Repaint here: every colour the game uses is defined in `Sea`. Change these and the
//  whole game re-themes. The Canvas art (GameArt.swift) and the menus both read from this.
//

import SwiftUI

enum Sea {
    static let deep   = Color(red: 0.03, green: 0.09, blue: 0.18)   // darkest water / background
    static let water  = Color(red: 0.06, green: 0.22, blue: 0.40)   // mid water
    static let shallow = Color(red: 0.10, green: 0.40, blue: 0.55)  // lighter near-surface
    static let foam   = Color(red: 0.80, green: 0.95, blue: 0.99)   // wave crests / splash
    static let teal   = Color(red: 0.22, green: 0.88, blue: 0.82)   // primary accent
    static let blue   = Color(red: 0.28, green: 0.58, blue: 0.98)   // secondary accent
    static let gold   = Color(red: 1.00, green: 0.80, blue: 0.32)   // score / big fish
    static let coral  = Color(red: 1.00, green: 0.46, blue: 0.42)   // danger / warnings
    static let rock   = Color(red: 0.42, green: 0.45, blue: 0.50)   // obstacles

    static var gradient: LinearGradient {
        LinearGradient(colors: [teal, blue], startPoint: .leading, endPoint: .trailing)
    }
    static var waterGradient: LinearGradient {
        LinearGradient(colors: [shallow, water, deep], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Buttons

/// Filled teal→blue capsule, dark text — the hero action.
struct SeaPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(Sea.gradient, in: Capsule())
            .foregroundStyle(.black)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Tinted outline capsule — secondary actions.
struct SeaSecondaryButton: ButtonStyle {
    var tint: Color = Sea.teal
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(tint.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
            .foregroundStyle(tint)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension ButtonStyle where Self == SeaPrimaryButton {
    static var seaPrimary: SeaPrimaryButton { .init() }
}
extension ButtonStyle where Self == SeaSecondaryButton {
    static func seaSecondary(_ tint: Color = Sea.teal) -> SeaSecondaryButton { .init(tint: tint) }
}
