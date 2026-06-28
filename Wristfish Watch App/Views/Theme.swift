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

// MARK: - Boats (cosmetic only — no gameplay advantage) -----------------------

/// What you must rack up (across all trips) to unlock a boat.
enum BoatUnlock {
    case none
    case fish(Int)
    case score(Int)
    case boots(Int)
    case chests(Int)

    var label: String {
        switch self {
        case .none:          return "Starter boat"
        case .fish(let n):   return "Catch \(n) fish"
        case .score(let n):  return "Earn \(n) points"
        case .boots(let n):  return "Catch \(n) boots"
        case .chests(let n): return "Catch \(n) chests"
        }
    }
    /// A compact metric word for tight tiles.
    var metric: String {
        switch self {
        case .none:   return ""
        case .fish:   return "Fish"
        case .score:  return "Pts"
        case .boots:  return "Boots"
        case .chests: return "Chests"
        }
    }
    var current: Int {
        switch self {
        case .none:   return 1
        case .fish:   return LocalStore.totalFish()
        case .score:  return LocalStore.totalScore()
        case .boots:  return LocalStore.totalBoots()
        case .chests: return LocalStore.totalChests()
        }
    }
    var target: Int {
        switch self {
        case .none: return 1
        case .fish(let n), .score(let n), .boots(let n), .chests(let n): return n
        }
    }
    var met: Bool { current >= target }
}

/// Distinct hull silhouettes so each boat reads differently, not just recoloured.
enum BoatStyle { case skiff, motorboat, trawler, voyager, speedboat, sailboat, yacht, boot, barge }

/// A selectable boat. Looks differ (shape + details); gameplay is identical for every boat.
struct BoatModel: Identifiable {
    let id: Int
    let name: String
    let hull: Color
    let accent: Color          // trim / the angler's gear
    let style: BoatStyle
    let unlock: BoatUnlock

    var isUnlocked: Bool {
        #if DEBUG
        return true             // dev: all boats pickable so we can see every skin
        #else
        return unlock.met
        #endif
    }

    static let all: [BoatModel] = [
        .init(id: 0, name: "Skiff",          hull: Sea.gold,                                  accent: Sea.coral,                                 style: .skiff,     unlock: .none),
        .init(id: 1, name: "Mariner",        hull: Color(red: 0.28, green: 0.55, blue: 0.92), accent: Color(white: 0.95),                        style: .motorboat, unlock: .fish(100)),
        .init(id: 2, name: "Trawler",        hull: Color(red: 0.30, green: 0.52, blue: 0.34), accent: Sea.gold,                                  style: .trawler,   unlock: .fish(500)),
        .init(id: 3, name: "Voyager",        hull: Color(red: 0.16, green: 0.62, blue: 0.60), accent: Color(white: 0.96),                        style: .voyager,   unlock: .fish(1500)),
        .init(id: 4, name: "Cruiser",        hull: Color(red: 0.86, green: 0.24, blue: 0.26), accent: Color(red: 0.98, green: 0.92, blue: 0.78), style: .speedboat, unlock: .score(25_000)),
        .init(id: 5, name: "Clipper",        hull: Color(red: 0.90, green: 0.91, blue: 0.94), accent: Sea.blue,                                  style: .sailboat,  unlock: .score(70_000)),
        .init(id: 6, name: "Flagship",       hull: Color(red: 0.15, green: 0.16, blue: 0.20), accent: Sea.gold,                                  style: .yacht,     unlock: .score(150_000)),
        .init(id: 7, name: "Old Boot",       hull: Color(red: 0.46, green: 0.29, blue: 0.16), accent: Color(red: 0.26, green: 0.16, blue: 0.10), style: .boot,      unlock: .boots(100)),
        .init(id: 8, name: "Treasure Barge", hull: Color(red: 0.40, green: 0.27, blue: 0.16), accent: Sea.gold,                                  style: .barge,     unlock: .chests(100)),
    ]

    static var selected: BoatModel {
        let id = LocalStore.selectedBoat()
        return all.first { $0.id == id && $0.isUnlocked } ?? all[0]
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
