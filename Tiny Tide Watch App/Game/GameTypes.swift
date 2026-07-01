//
//  GameTypes.swift
//  Tiny Tide — pure value types for the game (no SwiftUI, no UIKit).
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
    case sleighRide  // a big fish is towing the boat — steer, dodge, and wear it down
    case kraken      // a sea monster surfaced — dodge its tentacle strikes and survive
    case bootBeast   // a goofy boot-monster popped up — dodge the boots it lobs at you
    case surfacing   // catch/loss transition out of the reel
    case landed      // showing the catch
    case crashing    // hit a rock — the splash effect is playing
    case gameOver    // trip over
}

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
        case .cod:      return 50
        case .salmon:   return 100
        case .tuna:     return 200
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

/// A feather knocked loose when your cast clips a passing gull — it flutters down and fades.
struct Feather: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var vx: Double            // sideways drift (normalized / s)
    var vy: Double            // vertical drift (normalized / s)
    var rot: Double           // current rotation (radians)
    var vr: Double            // spin speed (rad / s)
    var seed: Int
    var age: Double = 0
}

/// A boot the Boot Beast lobs at you: telegraphs, then drops at `x`. Driven by `age`.
struct BootThrow {
    var x: Double
    var age: Double = 0
    var resolved: Bool = false      // dodge/hit already counted
}

/// A harpoon you've thrown straight up at the kraken — flies until it hits or leaves the screen.
struct Harpoon {
    var x: Double
    var y: Double
}

/// A kraken tentacle strike: telegraphs, slams at `x`, then recedes. Driven entirely by `age`.
struct Tentacle: Identifiable {
    let id = UUID()
    var x: Double
    var age: Double = 0
    var seed: Int
}

/// A fish leaping out of the water — a brief ambient flourish.
struct Leap: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var dir: Double          // arc travels left (−1) or right (+1)
    var age: Double = 0
    var splashed = false     // played the faint re-entry plash once it drops back in
}

/// The result of a successful reel-in.
struct CaughtFish {
    let kind: FishKind
    let points: Int
}

// MARK: - Levels & game modes -------------------------------------------------

/// One entry in a weighted fish table.
struct FishOdds {
    let kind: FishKind
    let weight: Double
}

/// What can be caught in shallow vs deep ripples on a given level.
struct FishTable {
    let shallow: [FishOdds]
    let deep: [FishOdds]

    /// Pick a fish for the given depth. `r` is a 0…1 random roll. `bigBias` (≥0) skews the pick toward
    /// the end of the table — the bigger fish — which is how the night shift coaxes up trophies.
    func roll(deep: Bool, _ r: Double, bigBias: Double = 0) -> FishKind {
        let table = deep ? self.deep : self.shallow
        guard !table.isEmpty else { return .herring }
        let rr = bigBias > 0 ? pow(r, 1.0 / (1.0 + bigBias)) : r   // push the roll toward 1 (the last, biggest entries)
        let total = table.reduce(0) { $0 + $1.weight }
        var x = rr * total
        for o in table { if x < o.weight { return o.kind }; x -= o.weight }
        return table.last!.kind
    }

    /// Mostly small inshore fish.
    static let inshore = FishTable(
        shallow: [.init(kind: .herring, weight: 55), .init(kind: .mackerel, weight: 45)],
        deep:    [.init(kind: .herring, weight: 35), .init(kind: .mackerel, weight: 45), .init(kind: .cod, weight: 20)])
    /// The full default spread used by freeplay.
    static let standard = FishTable(
        shallow: [.init(kind: .boot, weight: 10), .init(kind: .herring, weight: 45),
                  .init(kind: .mackerel, weight: 33), .init(kind: .cod, weight: 12)],
        deep:    [.init(kind: .boot, weight: 8), .init(kind: .cod, weight: 27),
                  .init(kind: .salmon, weight: 35), .init(kind: .tuna, weight: 16)])
    /// Deep water, big fish — for the open-sea / trophy levels.
    static let bluewater = FishTable(
        shallow: [.init(kind: .mackerel, weight: 40), .init(kind: .cod, weight: 40), .init(kind: .salmon, weight: 20)],
        deep:    [.init(kind: .cod, weight: 18), .init(kind: .salmon, weight: 40), .init(kind: .tuna, weight: 26)])
    /// Freeplay (Open Water): like `standard`, but tuna are scarcer so the tow is a rarer treat.
    static let openWater = FishTable(
        shallow: [.init(kind: .boot, weight: 10), .init(kind: .herring, weight: 45),
                  .init(kind: .mackerel, weight: 33), .init(kind: .cod, weight: 12)],
        deep:    [.init(kind: .boot, weight: 8), .init(kind: .cod, weight: 35),
                  .init(kind: .salmon, weight: 45), .init(kind: .tuna, weight: 6)])
    /// A junky stretch full of old boots — you'll snag enough to wake the Boot Beast.
    static let flotsam = FishTable(
        shallow: [.init(kind: .boot, weight: 42), .init(kind: .herring, weight: 38), .init(kind: .mackerel, weight: 20)],
        deep:    [.init(kind: .boot, weight: 38), .init(kind: .cod, weight: 30), .init(kind: .salmon, weight: 32)])
}

/// How often a hooked catch is a special instead of a fish.
struct SpecialChances {
    let mine: Double, chest: Double, pickaxe: Double
    static let none     = SpecialChances(mine: 0, chest: 0, pickaxe: 0)
    static let standard = SpecialChances(mine: 0.05, chest: 0.07, pickaxe: 0.06)
    static let treasure = SpecialChances(mine: 0.06, chest: 0.12, pickaxe: 0.10)
}

/// A single obstacle/ripple placed at an EXACT spot — the building block for authored patterns.
enum ScriptItem {
    case rock(r: Double)
    case lighthouse
    case driftBoat(vx: Double)
    case ripple(deep: Bool)
}

/// A scripted placement: when the level has travelled `at` units of water, drop `item` at exact x.
/// (Distance-based so the pattern lands in the same place regardless of frame timing.)
struct ScriptedSpawn {
    let at: Double          // world distance into the level (0 = boating just began)
    let x: Double           // exact normalized x, 0…1
    let item: ScriptItem
}

/// A level's win condition. `nil` (on a config) means endless freeplay.
enum Objective {
    case score(Int)                       // reach this many points
    case catchAny(Int)                    // land this many scoring fish
    case catchSpecies(FishKind, Int)      // land this many of one species
    case survive(Double)                  // last this many seconds
    case combo(Int)                       // reach this combo multiplier
    case noLoss(Int)                      // land this many in a row without a miss
    case reachFinish                      // sail to the finish line (config.finishAt)
}

/// Everything that defines one playthrough — freeplay uses `.freeplay`, each campaign level its own.
struct LevelConfig {
    let id: Int                           // 0 = freeplay; 1…N = campaign
    let title: String
    let subtitle: String
    let objective: Objective?             // nil = endless
    let fixedTimeOfDay: Double?           // nil = cycle from day into night
    let dayLength: Double
    let baseScroll: Double
    let scrollRamp: Double
    let rampSeconds: Double
    let rockSpawn: ClosedRange<Double>?   // nil = no procedural rocks (script only)
    let hintSpawn: ClosedRange<Double>?   // nil = no procedural ripples
    let lethal: Bool                      // do obstacles end the run?
    let fish: FishTable
    let specials: SpecialChances
    let birds: Bool
    let predator: Bool
    let script: [ScriptedSpawn]
    var finishAt: Double? = nil            // world distance to the finish line (for .reachFinish levels)
    var kraken: Bool = false               // can the kraken surface on this level?
    var krakenFirstAt: Double? = nil       // force the first kraken at this many seconds (nil = random 55…95)

    /// The endless score-chase. Renamed "Open Water" in the menu.
    static let freeplay = LevelConfig(
        id: 0, title: "Open Water", subtitle: "Endless · chase your best",
        objective: nil, fixedTimeOfDay: nil, dayLength: 150,
        baseScroll: 0.24, scrollRamp: 0.6, rampSeconds: 90,
        rockSpawn: 1.4...2.6, hintSpawn: 1.8...3.0, lethal: true,
        fish: .openWater, specials: .standard, birds: true, predator: true, script: [], kraken: true)
}

// MARK: - Authored patterns + the campaign --------------------------------------

extension LevelConfig {
    /// A left-right slalom of rocks: `count` rocks spaced `gap` apart, starting at distance `start`.
    private static func slalom(start: Double, gap: Double, count: Int, r: Double = 0.075) -> [ScriptedSpawn] {
        (0..<count).map { i in
            ScriptedSpawn(at: start + Double(i) * gap, x: i % 2 == 0 ? 0.28 : 0.72, item: .rock(r: r))
        }
    }
    /// A narrow gate (two rocks) to thread between, centred on `centerX`.
    private static func gate(at d: Double, centerX: Double, half: Double) -> [ScriptedSpawn] {
        [ScriptedSpawn(at: d, x: max(0.08, centerX - half), item: .rock(r: 0.07)),
         ScriptedSpawn(at: d, x: min(0.92, centerX + half), item: .rock(r: 0.07))]
    }
    /// A barrier of rocks across the lane with a single gap at `gapCenter` (±`gapHalf`) to aim for.
    private static func wall(at d: Double, gapCenter: Double, gapHalf: Double, r: Double = 0.058) -> [ScriptedSpawn] {
        stride(from: 0.10, through: 0.90, by: 0.13).compactMap { x in
            abs(x - gapCenter) > gapHalf ? ScriptedSpawn(at: d, x: x, item: .rock(r: r)) : nil
        }
    }

    /// The 20-level campaign — a cosy ramp: learn one idea at a time, then combine them, then the
    /// bosses. Each level ends the moment its goal is met.
    static let campaign: [LevelConfig] = [
        // 1 — just steer, cast, reel. Calm morning, no danger.
        LevelConfig(id: 1, title: "First Cast", subtitle: "Catch 3 fish",
            objective: .catchAny(3), fixedTimeOfDay: 0.06, dayLength: 150,
            baseScroll: 0.16, scrollRamp: 0.2, rampSeconds: 120,
            rockSpawn: nil, hintSpawn: 1.1...1.8, lethal: false,
            fish: .inshore, specials: .none, birds: false, predator: false, script: []),

        // 2 — first rocks, taught with two wide gates.
        LevelConfig(id: 2, title: "Harbour Mouth", subtitle: "Reach 200 points",
            objective: .score(200), fixedTimeOfDay: 0.14, dayLength: 150,
            baseScroll: 0.20, scrollRamp: 0.3, rampSeconds: 120,
            rockSpawn: 2.6...4.0, hintSpawn: 1.3...2.2, lethal: true,
            fish: .standard, specials: .none, birds: false, predator: false,
            script: gate(at: 3, centerX: 0.5, half: 0.26) + gate(at: 7, centerX: 0.42, half: 0.24)),

        // 3 — deep water: read & reach the deep ripples for a salmon.
        LevelConfig(id: 3, title: "Into the Blue", subtitle: "Land a salmon",
            objective: .catchSpecies(.salmon, 1), fixedTimeOfDay: 0.50, dayLength: 150,
            baseScroll: 0.20, scrollRamp: 0.3, rampSeconds: 120,
            rockSpawn: 2.8...4.2, hintSpawn: 1.2...2.0, lethal: true,
            fish: .bluewater, specials: .none, birds: false, predator: false, script: []),

        // 4 — a skerry slalom past a lighthouse, then cross the finish line.
        LevelConfig(id: 4, title: "Skerry Slalom", subtitle: "Reach the finish",
            objective: .reachFinish, fixedTimeOfDay: 0.20, dayLength: 150,
            baseScroll: 0.26, scrollRamp: 0.4, rampSeconds: 90,
            rockSpawn: 2.6...3.8, hintSpawn: 2.0...3.2, lethal: true,
            fish: .standard, specials: .none, birds: true, predator: false,
            script: slalom(start: 2, gap: 1.4, count: 12) + [ScriptedSpawn(at: 9, x: 0.5, item: .lighthouse)],
            finishAt: 13),

        // 5 — find your rhythm at sunset: a 3x combo.
        LevelConfig(id: 5, title: "Finding Rhythm", subtitle: "Reach a 3x combo",
            objective: .combo(3), fixedTimeOfDay: 0.56, dayLength: 150,
            baseScroll: 0.22, scrollRamp: 0.3, rampSeconds: 110,
            rockSpawn: 2.6...3.8, hintSpawn: 1.1...1.9, lethal: true,
            fish: .standard, specials: .none, birds: true, predator: false, script: []),

        // 6 — gulls overhead: cast near them to slow them, clip them for points.
        LevelConfig(id: 6, title: "Gulls Overhead", subtitle: "Reach 350 points",
            objective: .score(350), fixedTimeOfDay: 0.30, dayLength: 150,
            baseScroll: 0.23, scrollRamp: 0.4, rampSeconds: 100,
            rockSpawn: 2.2...3.4, hintSpawn: 1.3...2.1, lethal: true,
            fish: .standard, specials: .none, birds: true, predator: false, script: []),

        // 7 — salvage: chests, pickaxes and the odd sea mine appear.
        LevelConfig(id: 7, title: "Salvage", subtitle: "Reach 500 points",
            objective: .score(500), fixedTimeOfDay: 0.46, dayLength: 150,
            baseScroll: 0.24, scrollRamp: 0.4, rampSeconds: 100,
            rockSpawn: 2.0...3.2, hintSpawn: 1.3...2.1, lethal: true,
            fish: .standard, specials: .treasure, birds: true, predator: false, script: []),

        // 8 — night shift: trophies bite after dark — build a 4x combo.
        LevelConfig(id: 8, title: "Night Shift", subtitle: "Reach a 4x combo",
            objective: .combo(4), fixedTimeOfDay: 0.88, dayLength: 150,
            baseScroll: 0.22, scrollRamp: 0.3, rampSeconds: 110,
            rockSpawn: 2.6...3.8, hintSpawn: 1.1...1.8, lethal: true,
            fish: .standard, specials: .none, birds: true, predator: false, script: []),

        // 9 — big game: a tuna will tow you — hang on for the ride.
        LevelConfig(id: 9, title: "Big Game", subtitle: "Land a tuna",
            objective: .catchSpecies(.tuna, 1), fixedTimeOfDay: 0.36, dayLength: 150,
            baseScroll: 0.24, scrollRamp: 0.4, rampSeconds: 100,
            rockSpawn: 2.2...3.4, hintSpawn: 1.3...2.1, lethal: true,
            fish: .bluewater, specials: .standard, birds: true, predator: true, script: []),

        // 10 — a long run: slalom, a gate and a walled barrier to the finish.
        LevelConfig(id: 10, title: "The Long Haul", subtitle: "Reach the finish",
            objective: .reachFinish, fixedTimeOfDay: 0.22, dayLength: 150,
            baseScroll: 0.28, scrollRamp: 0.5, rampSeconds: 90,
            rockSpawn: 2.0...3.0, hintSpawn: 2.2...3.4, lethal: true,
            fish: .standard, specials: .standard, birds: true, predator: true,
            script: slalom(start: 2, gap: 1.2, count: 16) + gate(at: 9, centerX: 0.5, half: 0.18)
                + wall(at: 14, gapCenter: 0.4, gapHalf: 0.16),
            finishAt: 18),

        // 11 — flotsam: snag old boots until the Boot Beast wakes up.
        LevelConfig(id: 11, title: "Flotsam & Jetsam", subtitle: "Land 3 boots",
            objective: .catchSpecies(.boot, 3), fixedTimeOfDay: 0.40, dayLength: 150,
            baseScroll: 0.22, scrollRamp: 0.3, rampSeconds: 110,
            rockSpawn: 2.4...3.6, hintSpawn: 1.0...1.7, lethal: true,
            fish: .flotsam, specials: .none, birds: true, predator: false, script: []),

        // 12 — tight quarters: just stay afloat for a minute in a dense field.
        LevelConfig(id: 12, title: "Tight Quarters", subtitle: "Survive 60s",
            objective: .survive(60), fixedTimeOfDay: 0.62, dayLength: 150,
            baseScroll: 0.26, scrollRamp: 0.5, rampSeconds: 80,
            rockSpawn: 1.6...2.6, hintSpawn: 2.2...3.2, lethal: true,
            fish: .standard, specials: .standard, birds: true, predator: false, script: []),

        // 13 — lighthouse row: sweeping beacons + a wandering boat, race to the finish.
        LevelConfig(id: 13, title: "Lighthouse Row", subtitle: "Reach the finish",
            objective: .reachFinish, fixedTimeOfDay: 0.58, dayLength: 150,
            baseScroll: 0.28, scrollRamp: 0.5, rampSeconds: 85,
            rockSpawn: 2.2...3.4, hintSpawn: 2.2...3.4, lethal: true,
            fish: .standard, specials: .none, birds: true, predator: false,
            script: slalom(start: 2, gap: 1.5, count: 10)
                + [ScriptedSpawn(at: 6, x: 0.30, item: .lighthouse), ScriptedSpawn(at: 12, x: 0.70, item: .lighthouse),
                   ScriptedSpawn(at: 9, x: 0.20, item: .driftBoat(vx: 0.08)), ScriptedSpawn(at: 15, x: 0.80, item: .driftBoat(vx: -0.07))],
            finishAt: 20),

        // 14 — trophy hunt: two salmon from the night-time deep, predators about.
        LevelConfig(id: 14, title: "Trophy Hunt", subtitle: "Land 2 salmon",
            objective: .catchSpecies(.salmon, 2), fixedTimeOfDay: 0.90, dayLength: 150,
            baseScroll: 0.24, scrollRamp: 0.4, rampSeconds: 100,
            rockSpawn: 2.4...3.6, hintSpawn: 1.1...1.8, lethal: true,
            fish: .bluewater, specials: .standard, birds: true, predator: true, script: []),

        // 15 — flawless: five clean lands in a row, no misses.
        LevelConfig(id: 15, title: "Flawless", subtitle: "Land 5 in a row, no misses",
            objective: .noLoss(5), fixedTimeOfDay: 0.50, dayLength: 150,
            baseScroll: 0.24, scrollRamp: 0.4, rampSeconds: 100,
            rockSpawn: 2.6...3.8, hintSpawn: 1.2...1.9, lethal: true,
            fish: .standard, specials: .standard, birds: true, predator: true, script: []),

        // 16 — deep dread: the kraken surfaces early — survive it, and the night.
        LevelConfig(id: 16, title: "Deep Dread", subtitle: "Survive 80s",
            objective: .survive(80), fixedTimeOfDay: 0.92, dayLength: 150,
            baseScroll: 0.26, scrollRamp: 0.5, rampSeconds: 80,
            rockSpawn: 2.2...3.4, hintSpawn: 1.4...2.2, lethal: true,
            fish: .bluewater, specials: .standard, birds: true, predator: false,
            script: [], kraken: true, krakenFirstAt: 22),

        // 17 — storm run: a fast, dense gauntlet of everything, to a distant finish.
        LevelConfig(id: 17, title: "Storm Run", subtitle: "Reach the finish",
            objective: .reachFinish, fixedTimeOfDay: 0.30, dayLength: 150,
            baseScroll: 0.32, scrollRamp: 0.6, rampSeconds: 75,
            rockSpawn: 1.6...2.6, hintSpawn: 2.4...3.6, lethal: true,
            fish: .standard, specials: .standard, birds: true, predator: true,
            script: slalom(start: 2, gap: 1.0, count: 22)
                + gate(at: 8, centerX: 0.5, half: 0.15) + gate(at: 14, centerX: 0.55, half: 0.14)
                + wall(at: 18, gapCenter: 0.45, gapHalf: 0.14)
                + [ScriptedSpawn(at: 5, x: 0.2, item: .driftBoat(vx: 0.09)), ScriptedSpawn(at: 11, x: 0.8, item: .lighthouse)],
            finishAt: 22),

        // 18 — the kraken's lair: drive it off and bank a big score.
        LevelConfig(id: 18, title: "Kraken's Lair", subtitle: "Reach 800 points",
            objective: .score(800), fixedTimeOfDay: 0.88, dayLength: 150,
            baseScroll: 0.28, scrollRamp: 0.5, rampSeconds: 85,
            rockSpawn: 2.0...3.0, hintSpawn: 1.3...2.0, lethal: true,
            fish: .bluewater, specials: .treasure, birds: true, predator: true,
            script: [], kraken: true, krakenFirstAt: 30),

        // 19 — no quarter: a blistering night chase for a 5x combo.
        LevelConfig(id: 19, title: "No Quarter", subtitle: "Reach a 5x combo",
            objective: .combo(5), fixedTimeOfDay: 0.84, dayLength: 150,
            baseScroll: 0.30, scrollRamp: 0.6, rampSeconds: 75,
            rockSpawn: 1.6...2.6, hintSpawn: 1.1...1.8, lethal: true,
            fish: .standard, specials: .treasure, birds: true, predator: true, script: []),

        // 20 — master angler: everything, at speed, in the dead of night, kraken and all.
        LevelConfig(id: 20, title: "Master Angler", subtitle: "Reach 1200 points",
            objective: .score(1200), fixedTimeOfDay: 0.95, dayLength: 150,
            baseScroll: 0.34, scrollRamp: 0.75, rampSeconds: 70,
            rockSpawn: 1.3...2.2, hintSpawn: 1.1...1.8, lethal: true,
            fish: .standard, specials: .treasure, birds: true, predator: true,
            script: slalom(start: 3, gap: 1.6, count: 10), kraken: true, krakenFirstAt: 45),
    ]
}
