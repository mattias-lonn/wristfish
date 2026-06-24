//
//  GameTypes.swift
//  Wristfish — pure value types for the game (no SwiftUI, no UIKit).
//
//  The flow:  boating ──tap──▶ casting ──bite──▶ reeling ──land──▶ landed ──tap──▶ boating
//             (hit a rock at any time during boating ▶ gameOver)
//

import Foundation

/// The current step of a fishing trip.
enum Phase {
    case launching   // intro — the boat is pulling away from the dock
    case boating     // steer the boat, dodge rocks, read the ripples
    case casting     // aiming — the line is extending; tap again to drop it
    case hooking     // brief "Fish on!" flash between the cast and the reel
    case reeling     // fish on the hook — work the balance gauge!
    case surfacing   // catch/loss transition out of the reel
    case landed      // showing the catch
    case crashing    // hit a rock — the splash effect is playing
    case gameOver    // trip over
}

/// A short flick (single tap) reaches shallow ripples; a double tap reaches the deep ones.
enum CastKind { case short, deep }

/// The fish you can land. Bigger fish = more points, but they fight harder.
enum FishKind: CaseIterable {
    case herring, mackerel, cod, salmon, tuna, boot

    var name: String {
        switch self {
        case .herring:  return "Herring"
        case .mackerel: return "Mackerel"
        case .cod:      return "Cod"
        case .salmon:   return "Salmon"
        case .tuna:     return "Tuna"
        case .boot:     return "Old Boot"
        }
    }

    var points: Int {
        switch self {
        case .herring:  return 10
        case .mackerel: return 25
        case .cod:      return 45
        case .salmon:   return 90
        case .tuna:     return 175
        case .boot:     return 0
        }
    }

    /// Reel difficulty — how hard it pulls and how long it takes to land (1.0 ≈ average).
    var fight: Double {
        switch self {
        case .herring:  return 0.6
        case .mackerel: return 0.8
        case .cod:      return 1.1
        case .salmon:   return 1.5
        case .tuna:     return 2.1
        case .boot:     return 0.5
        }
    }
}

/// What kind of obstacle this is. Most are rocks; lighthouses and drifting boats are rarer.
enum ObstacleKind { case rock, lighthouse, boat }

/// An obstacle to dodge. Positions are normalized 0…1 (x across, y down the screen).
struct Obstacle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var r: Double          // radius (normalized)
    var seed: Int = Int.random(in: 0..<100_000)   // drives its (stable) irregular shape
    var kind: ObstacleKind = .rock
    var vx: Double = 0      // sideways drift speed (the wandering boat only)
}

/// A ripple on the water that tells you fish are near. `deep` ripples need a long (double-tap) cast.
struct Hint: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var deep: Bool
    var phase: Double = 0  // animation clock for the pulsing rings
}

/// A rare thing you can hook instead of a fish.
///  • chest   — landing it doubles your points for a while
///  • pickaxe — landing it lets you cleave straight through rocks for a while
///  • mine    — landing it blows you up; let it get away to stay safe
enum Special {
    case chest, pickaxe, mine

    var title: String {
        switch self {
        case .chest:   return "Treasure!"
        case .pickaxe: return "Pickaxe!"
        case .mine:    return "Sea mine!"
        }
    }
    var blurb: String {
        switch self {
        case .chest:   return "Double points · 30s"
        case .pickaxe: return "Cleave rocks · 20s"
        case .mine:    return "Cut it loose!"
        }
    }
}

/// A rock bursting apart when you cleave it with the pickaxe.
struct Shatter: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var r: Double
    var seed: Int
    var age: Double = 0
}

/// A fish leaping out of the water — a brief ambient flourish.
struct Leap: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var dir: Double          // arc travels left (−1) or right (+1)
    var age: Double = 0
}

/// The result of a successful reel-in.
struct CaughtFish {
    let kind: FishKind
    let points: Int
}
