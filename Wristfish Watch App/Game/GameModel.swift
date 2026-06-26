//
//  GameModel.swift
//  Wristfish — all the game logic and the 30 fps loop. No drawing here (see GameArt.swift).
//
//  Inputs come from GameView:
//    • Digital Crown  → steer the boat (boating) / reel the fish in (reeling)
//    • Tap            → cast out; tap again to drop the line (you control the distance)
//

import SwiftUI
import Combine

final class GameModel: ObservableObject {

    // MARK: Tunables (tweak the feel here) ----------------------------------

    private let fps = 30.0
    private let baseScroll  = 0.24      // how fast the water flows past while boating
    private let scrollRamp  = 0.6       // extra flow at full difficulty
    private let rampSeconds = 90.0      // time to reach full difficulty
    private let castScrollSlow = 0.22   // world keeps drifting at this fraction of speed while aiming
    private let scrollEase     = 0.10   // how smoothly the world speed eases in/out (the debounce)

    private let steerGain   = 0.022     // Crown → boat target sideways speed
    private let boatSmooth  = 0.22      // how quickly the boat eases toward your steer (smoothing)
    private let wakeTrailLen = 14       // how many recent positions the wake trail remembers
    private let edge        = 0.10      // boat can't go past these x margins
    let boatY: Double = 0.80            // boat sits here vertically (read by the art)
    private let boatHitR    = 0.080     // collision radius for the boat
    private let launchSpeedMult = 1.5   // harbour recede speed as a multiple of sea cruising speed
    private let launchClearDist = 1.2   // harbour scrolls this far (screen-heights), then play begins
    private let crashDuration   = 0.7   // splash effect length before the game-over card
    private let hookDuration    = 0.55  // "Fish on!" transition between the cast and the reel
    private let surfaceDuration = 0.5      // catch/loss transition out of the reel — a quick splash
    private let landedAutoTime  = 1.8   // how long the catch shows before it auto-continues

    // Casting — line up with a ripple ahead and drop (forgiving, but you do need to aim).
    private let castTol     = 0.19      // how close (x) a ripple must be to the drop point
    private let castGrow    = 0.42      // how fast the cast extends while aiming (slower = easier timing)
    private let castMaxReach = 0.66     // farthest a cast can reach (normalized, ahead of boat)
    private let depthTol    = 0.17      // how close (distance) the drop must match a ripple

    // Reeling — keep the Crown-controlled marker inside the slowly-drifting zone to land the fish.
    private let zoneHalf   = 0.15       // half-height of the safe zone (bigger = easier)
    private let zoneAmp    = 0.26       // how far from centre the zone drifts
    private let zoneSpeed  = 1.0        // zone drift speed (rad/s) — slow & steady
    private let markerGain = 0.022      // Crown → marker speed
    private let fillRate   = 0.50       // catch progress gained per second while in the zone
    private let drainRate  = 0.28       // catch progress lost per second while outside

    // A bigger fish that rarely comes to eat the one on your hook.
    private let predatorChance     = 0.16   // chance a predator targets a small/mid catch — rare
    private let predatorMinTime    = 1.4    // earliest it strikes (seconds into the reel)
    private let predatorMaxTime    = 4.0    // latest it strikes
    private let predatorAnimTime   = 1.3    // length of the attack before it resolves
    private let predatorSnapChance = 0.5    // …then 50/50: bite through the line, or hook the big one
    // The upgraded "big fish" fight — harder to balance.
    private let hardZoneHalf  = 0.10        // tighter safe zone
    private let hardZoneSpeed = 1.7         // faster drift
    private let hardFillMult  = 0.7         // fills slower

    // MARK: Published / read by the views -----------------------------------

    @Published private(set) var phase: Phase = .launching
    private(set) var boatX: Double = 0.5
    private var boatTargetX: Double = 0.5
    private(set) var scroll: Double = 0
    private var scrollFactor = 1.0      // eased world-speed multiplier (1 boating, slow while aiming)
    private(set) var wakeTrail: [Double] = []   // recent boat x positions for the wake (newest first)
    private(set) var boatSpeed = 0.0            // 0…1 forward thrust — fades the wake in as you gas up
    private(set) var rocks: [Obstacle] = []
    private(set) var hints: [Hint] = []
    private(set) var leaps: [Leap] = []          // fish leaping out of the water
    private(set) var score: Int = 0
    private(set) var elapsed: Double = 0

    // A lone gull that passes over now and then — and very rarely dives to snatch your catch.
    private(set) var birdActive = false
    private(set) var birdDir = 1.0
    private(set) var birdDive = false          // this pass is a dive to snatch a fish in front of you
    private(set) var birdDiveTargetX = 0.5     // live position of the fish it's diving at…
    private(set) var birdDiveTargetY = 0.5     // …tracked so the swoop hits it exactly
    private(set) var birdXOffset = 0.0         // horizontal shift after the gull is knocked off course
    private(set) var birdHit = false           // your cast clipped it this pass (once per pass)
    private(set) var feathers: [Feather] = []  // feathers fluttering down from a clipped gull

    // Reeling state
    private(set) var hooked: FishKind?
    private(set) var reelProgress: Double = 0   // catch progress: 0 = losing it, 1 = landed
    private(set) var marker = 0.5               // your Crown-controlled position on the gauge (0…1)
    private(set) var zoneCenter = 0.5           // centre of the slowly-drifting safe zone (0…1)
    private(set) var hardFish = false           // the upgraded big fish — harder to balance
    private(set) var predatorActive = false     // a predator is attacking the hooked fish right now
    private(set) var surfaceCaught = false      // did the surfacing transition follow a catch?
    private(set) var castReach = 0.0            // how far the current cast has reached (aiming/locked)
    private(set) var lastCatch: CaughtFish?
    private(set) var isBest = false             // this trip beat the stored best

    // Combo — consecutive catches build a multiplier; a missed cast / lost fish / crash breaks it.
    private(set) var streak = 0
    private(set) var comboMult = 1
    private(set) var lastComboMult = 1          // combo that applied to the last catch (for the card)
    private(set) var lastPerfect = false        // the last catch was a clean (perfect) reel
    // A floating "+points" that rises and fades right after a catch.
    private(set) var scorePop = 0
    private(set) var scorePopMult = 1
    private(set) var scorePopPerfect = false

    // Special hooks & their effects.
    private(set) var hookedSpecial: Special?    // a chest / pickaxe / mine is on the line
    private(set) var lastSpecial: Special?      // shown on the result card after landing one
    private(set) var doublePointsT = 0.0        // >0 → points are doubled (from a chest)
    private(set) var rockBreakT = 0.0           // >0 → boat cleaves through rocks (from a pickaxe)
    private(set) var shatters: [Shatter] = []   // rocks bursting apart
    private(set) var crashIsMine = false        // the crash is a mine going off (explosion, not splash)

    // Transient banner ("Nothing biting", "It got away!", …)
    private(set) var flash = ""
    private var flashTimer = 0.0

    // MARK: Private state
    private var timer: Timer?
    private let haptics = HapticsManager.shared
    private var rockSpawn = 1.2
    private var hintSpawn = 1.5
    private var launchT = 0.0
    private var harborScroll = 0.0
    private var hookT = 0.0
    private(set) var crashProgress = 0.0       // 0→1 during the crash splash
    private(set) var crashX = 0.5
    private(set) var crashY = 0.80
    private var reelClock = 0.0                // drives the zone drift while reeling
    private var wasInZone = false
    private var predatorT = 0.0
    private var predatorPending = false
    private var predatorAt = 0.0
    private var surfaceT = 0.0
    private var landedT = 0.0
    private var zonePhase = 0.0                // random starting phase of the zone drift
    private let chestDuration   = 30.0         // double points last this long
    private let pickaxeDuration  = 20.0        // rock-cleaving lasts this long
    let shatterDuration  = 0.55                // how long a rock-shatter burst plays
    private let mineChance    = 0.05           // chance a hooked catch is a mine…
    private let chestChance   = 0.07           // …a chest…
    private let pickaxeChance = 0.06           // …or a pickaxe (otherwise a fish)
    private let birdDuration = 6.0             // seconds for a lone gull to cross the screen
    private let birdDiveChance = 0.4           // a fraction of passes are a dive for a fish
    private var birdT = 0.0
    private var birdSpawn = Double.random(in: 8...16)
    private var birdCommitted = false          // the dive has locked onto a target
    private var birdGrabbed = false            // it has already snatched (once per dive)
    private var birdDiveHintID: UUID?          // the exact fish-ripple it's diving at
    private var birdSpeed = 1.0                 // eased flight-speed multiplier (1 normal, <1 when the line slows it)
    private var birdSpeedTarget = 1.0
    private let birdSlowFactor = 0.42          // how far the gull slows when your line is in front of it
    private let birdHitRadius  = 0.065         // how close the hook must pass to clip the gull
    let featherDuration = 1.3                   // how long a knocked-loose feather lingers
    let leapDuration = 0.85                      // how long a fish's leap lasts
    private var leapSpawn = Double.random(in: 3...7)

    // Combo + catch juice tunables.
    private let maxCombo = 5                      // the streak multiplier caps here
    private let perfectBonus = 1.5               // a perfect (clean) reel pays this much extra
    private let perfectTol = 0.45                // total out-of-zone time that still counts as perfect
    let scorePopDuration = 1.1                    // how long the floating "+points" lingers
    private var scorePopT = 99.0                 // ≥ duration → inactive
    private var reelOutTime = 0.0                // time spent outside the zone this reel (for PERFECT)

    // Day → night: the trip slides from daylight through sunset into night over this many seconds.
    private let dayLength = 150.0

    var ramp: Double { min(1, elapsed / rampSeconds) }

    /// 0 = bright day → 1 = deep night. Drives the water palette and lighting.
    var timeOfDay: Double { min(1, elapsed / dayLength) }

    /// The streak multiplier is worth showing once it's ≥ 2×.
    var comboActive: Bool { comboMult >= 2 }
    /// The floating "+points" is still on screen.
    var scorePopActive: Bool { scorePopT < scorePopDuration }
    var scorePopProgress: Double { min(1, scorePopT / scorePopDuration) }

    /// How far the gull is across its flyover (0…1) — read by the art.
    var birdProgress: Double { min(1, birdT / birdDuration) }

    // Active power-ups (read by the HUD).
    var doublePoints: Bool { doublePointsT > 0 }
    var rockBreak: Bool { rockBreakT > 0 }
    var doublePointsLeft: Int { Int(doublePointsT.rounded(.up)) }
    var rockBreakLeft: Int { Int(rockBreakT.rounded(.up)) }
    private var scoreMultiplier: Int { doublePoints ? 2 : 1 }

    /// Normalized hook position the art draws the line to. Valid while casting & reeling.
    var hookPoint: CGPoint {
        switch phase {
        case .casting:
            return CGPoint(x: boatX, y: boatY - castReach)
        case .reeling:
            let castY = boatY - castReach
            return CGPoint(x: boatX, y: castY + (boatY - castY) * reelProgress)
        default:
            return CGPoint(x: boatX, y: boatY)
        }
    }

    /// Cast power 0…1 for the HUD distance meter while aiming.
    var castReachFraction: Double { min(1, castReach / castMaxReach) }

    /// While boating, is a ripple roughly lined up ahead of the boat? (HUD "Tap to cast" prompt.)
    var targetAhead: Bool {
        guard phase == .boating else { return false }
        return hints.contains { $0.y < boatY && $0.y > boatY - castMaxReach && abs($0.x - boatX) < castTol }
    }

    /// While aiming, is the line currently over a catchable ripple? Drives the "TAP!" lock-on cue.
    var castLocked: Bool {
        guard phase == .casting else { return false }
        let castY = boatY - castReach
        return hints.contains { abs($0.x - boatX) < castTol && abs($0.y - castY) < depthTol }
    }

    /// How far the harbour has scrolled away (screen-heights). Read by the art.
    var harborOffset: Double { harborScroll }

    /// "Fish on!" transition progress 0…1.
    var hookProgress: Double { min(1, hookT / hookDuration) }

    // Gauge difficulty — tighter & faster once a big fish is on.
    private var curZoneHalf: Double  { hardFish ? hardZoneHalf : zoneHalf }
    private var curZoneSpeed: Double { hardFish ? hardZoneSpeed : zoneSpeed }
    private var curFillRate: Double  { hardFish ? fillRate * hardFillMult : fillRate }

    /// Half-height of the fight zone (for the gauge art).
    var zoneHalfWidth: Double { curZoneHalf }

    /// Is the marker inside the moving zone right now? (Catch meter fills when true.)
    var markerInZone: Bool { phase == .reeling && !predatorActive && abs(marker - zoneCenter) < curZoneHalf }

    /// Predator attack progress 0…1 (for the art).
    var predatorProgress: Double { min(1, predatorT / predatorAnimTime) }

    /// Catch/loss transition progress 0…1 (for the art & overlay).
    var surfaceProgress: Double { min(1, surfaceT / surfaceDuration) }

    // MARK: Lifecycle -------------------------------------------------------

    func start() {
        resetState()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func resetState() {
        phase = .launching
        boatX = 0.5; boatTargetX = 0.5; scroll = 0; score = 0; elapsed = 0
        rocks = []; hints = []; leaps = []
        leapSpawn = Double.random(in: 3...7)
        hooked = nil; reelProgress = 0; marker = 0.5; zoneCenter = 0.5
        hardFish = false; predatorActive = false; predatorPending = false; predatorT = 0
        surfaceCaught = false; surfaceT = 0; landedT = 0; zonePhase = 0
        lastCatch = nil; flash = ""; flashTimer = 0; isBest = false
        streak = 0; comboMult = 1; lastComboMult = 1; lastPerfect = false
        scorePop = 0; scorePopMult = 1; scorePopPerfect = false; scorePopT = 99; reelOutTime = 0
        hookedSpecial = nil; lastSpecial = nil; doublePointsT = 0; rockBreakT = 0
        shatters = []; crashIsMine = false
        rockSpawn = 1.6; hintSpawn = 1.0; castReach = 0
        launchT = 0; harborScroll = 0; hookT = 0; crashProgress = 0
        reelClock = 0; wasInZone = false; scrollFactor = 1; wakeTrail = []; boatSpeed = 0
        birdActive = false; birdT = 0; birdDive = false; birdCommitted = false; birdGrabbed = false
        birdSpawn = Double.random(in: 8...16)
        birdXOffset = 0; birdHit = false; birdSpeed = 1; birdSpeedTarget = 1; feathers = []
    }

    /// A lone gull drifts across every so often. Your cast can now interact with it: a line dropped
    /// in front of it slows it down (like a banana on the track), and a line that clips it knocks
    /// feathers loose and sends it veering off the other way.
    private func updateBird(_ dt: Double) {
        if birdActive {
            updateBirdInteraction()                       // line in front slows it / a clip knocks it about
            birdSpeed += (birdSpeedTarget - birdSpeed) * 0.18
            birdT += dt * birdSpeed
            if birdDive {
                // Lock onto a real fish far ahead just before the swoop — or call it off if none.
                if !birdCommitted && birdProgress > 0.54 {
                    birdCommitted = true
                    if let h = fishToDiveAt() {
                        birdDiveHintID = h.id
                        birdDiveTargetX = h.x; birdDiveTargetY = h.y
                    } else {
                        birdDive = false                      // nothing to dive for → a plain flyover
                    }
                }
                // Track that exact fish (it keeps drifting) so the swoop lands right on it.
                if birdDive, let id = birdDiveHintID, let h = hints.first(where: { $0.id == id }) {
                    birdDiveTargetX = h.x; birdDiveTargetY = h.y
                }
                // Snatch it high up the screen, near the topmost ripple.
                if birdDive && !birdGrabbed && birdProgress >= 0.62 {
                    birdGrabbed = true
                    if let id = birdDiveHintID, let idx = hints.firstIndex(where: { $0.id == id }) {
                        hints.remove(at: idx)
                        showFlash("A gull stole a fish!")
                        haptics.play(.miss)
                    }
                }
            }
            if birdT >= birdDuration {
                birdActive = false; birdSpawn = Double.random(in: 18...34)
                birdSpeed = 1; birdSpeedTarget = 1
            }
        } else {
            birdSpeed = 1; birdSpeedTarget = 1
            birdSpawn -= dt
            if birdSpawn <= 0 {
                birdActive = true; birdT = 0
                birdDir = Bool.random() ? 1 : -1
                birdDive = Double.random(in: 0...1) < birdDiveChance   // sometimes it dives, sometimes not
                birdCommitted = false; birdGrabbed = false; birdDiveHintID = nil
                birdDiveTargetX = boatX; birdDiveTargetY = boatY - 0.28
                birdXOffset = 0; birdHit = false
            }
        }
    }

    /// The gull's normalized position for gameplay — mirrors the art's flight path in GameArt.drawBird.
    private func birdPos(_ p: Double) -> CGPoint {
        let x0 = birdDir > 0 ? -0.15 : 1.15
        let x1 = birdDir > 0 ?  1.05 : -0.05
        let y0 = 0.70, y1 = 0.04
        let bx = x0 + (x1 - x0) * p + birdXOffset
        let by = y0 + (y1 - y0) * p + 0.012 * sin(elapsed * 1.4)
        guard birdDive else { return CGPoint(x: bx, y: by) }
        let pd = 0.62, halfWin = 0.07
        let d = abs(p - pd)
        var k = 0.0
        if d < halfWin { let u = 1 - d / halfWin; k = u * u * (3 - 2 * u) }
        return CGPoint(x: bx + (birdDiveTargetX - bx) * k, y: by + (birdDiveTargetY - by) * k)
    }

    /// While you're aiming, see whether the line is in front of the gull (slow it) or clips it (bonk it).
    private func updateBirdInteraction() {
        guard !birdHit, phase == .casting, castReach > 0 else { birdSpeedTarget = 1; return }
        let hook = CGPoint(x: boatX, y: boatY - castReach)
        let bp = birdPos(birdProgress)
        let dx = hook.x - bp.x, dy = hook.y - bp.y
        if dx * dx + dy * dy < birdHitRadius * birdHitRadius {     // the hook caught it
            hitBird(at: bp)
            birdSpeedTarget = 1
            return
        }
        // "In front" = the hook sits ahead of it up the screen, within its lane — it slows to approach.
        let gap = bp.y - hook.y
        let ahead = gap > 0 && gap < 0.32 && abs(dx) < 0.20
        birdSpeedTarget = ahead ? birdSlowFactor : 1
    }

    /// Your cast clipped the gull: feathers burst loose and it veers off the opposite way.
    private func hitBird(at bp: CGPoint) {
        birdHit = true
        birdDive = false           // a clipped gull abandons any dive (so it can't steal a fish)
        birdGrabbed = true         // …and never grabs
        // Reverse its horizontal direction while keeping the on-screen position continuous (no teleport).
        let p = birdProgress
        let curBaseX = (0.5 - 0.65 * birdDir) + (1.20 * birdDir) * p + birdXOffset
        birdDir = -birdDir
        birdXOffset = curBaseX - ((0.5 - 0.65 * birdDir) + (1.20 * birdDir) * p)
        spawnFeathers(at: bp)
        showFlash("Bonk!")
        haptics.play(.tug)
    }

    private func spawnFeathers(at p: CGPoint) {
        for _ in 0..<8 {
            let ang = Double.random(in: 0..<(2 * .pi))
            let spd = Double.random(in: 0.05...0.14)
            feathers.append(Feather(
                x: p.x + Double.random(in: -0.012...0.012),
                y: p.y + Double.random(in: -0.012...0.012),
                vx: cos(ang) * spd,
                vy: sin(ang) * spd - 0.03,                 // a touch of initial lift before they settle
                rot: Double.random(in: 0..<(2 * .pi)),
                vr: Double.random(in: -3.5...3.5),
                seed: Int.random(in: 0..<100_000)))
        }
    }

    /// Feathers drift sideways, ease into a gentle fall, spin, and fade out.
    private func updateFeathers(_ dt: Double) {
        guard !feathers.isEmpty else { return }
        for i in feathers.indices {
            feathers[i].age += dt
            feathers[i].x += feathers[i].vx * dt
            feathers[i].y += feathers[i].vy * dt
            feathers[i].vy += 0.16 * dt              // settle into a fall
            feathers[i].vx *= (1 - 0.7 * dt)         // air drag
            feathers[i].rot += feathers[i].vr * dt
        }
        feathers.removeAll { $0.age >= featherDuration }
    }

    /// The topmost fish-ripple ahead of the boat to dive at, if any (within the boat's lane).
    private func fishToDiveAt() -> Hint? {
        let ahead = hints.filter { $0.y > 0.18 && $0.y < boatY - 0.25 && abs($0.x - boatX) < 0.40 }
        return ahead.min(by: { $0.y < $1.y })          // the one furthest up the screen
    }

    // MARK: Inputs ----------------------------------------------------------

    func crown(delta: Double) {
        switch phase {
        case .boating:
            boatTargetX = min(max(boatTargetX + delta * steerGain, edge), 1 - edge)
        case .reeling:
            marker = min(max(marker + delta * markerGain, 0), 1)   // move your gauge marker
        default:
            break
        }
    }

    func tap() {
        switch phase {
        case .boating: startAim()            // first tap — the line starts going out
        case .casting: dropCast()            // second tap — drop it at the reached distance
        case .landed:  phase = .boating      // continue the trip
        default:       break                 // reeling / gameOver: ignore
        }
    }

    /// Called by the menu's Play-again button.
    func restart() { start() }

    // MARK: The loop --------------------------------------------------------

    private func tick() {
        let dt = 1.0 / fps
        elapsed += dt
        if flashTimer > 0 { flashTimer -= dt; if flashTimer <= 0 { flash = "" } }
        if doublePointsT > 0 { doublePointsT = max(0, doublePointsT - dt) }   // power-ups tick in real time
        if rockBreakT > 0 { rockBreakT = max(0, rockBreakT - dt) }
        updateFeathers(dt)                                                    // knocked-loose feathers settle & fade
        if scorePopT < scorePopDuration { scorePopT += dt }                   // the floating "+points" rises & fades

        // Ease world speed: full while boating, a slow drift while aiming (debounce in & out).
        let targetFactor = (phase == .casting) ? castScrollSlow : 1.0
        scrollFactor += (targetFactor - scrollFactor) * scrollEase

        // Record the boat's path for the wake (only while it's on the water).
        if phase == .launching || phase == .boating || phase == .casting {
            wakeTrail.insert(boatX, at: 0)
            if wakeTrail.count > wakeTrailLen { wakeTrail.removeLast() }
        }

        switch phase {
        case .launching: tickLaunch(dt)
        case .boating:   tickBoating(dt)
        case .casting:   tickCasting(dt)
        case .hooking:   tickHooking(dt)
        case .reeling:   tickReeling(dt)
        case .surfacing: tickSurfacing(dt)
        case .crashing:  tickCrash(dt)
        case .landed:    tickLanded(dt)
        case .gameOver:  break
        }
        objectWillChange.send()
    }

    private func tickBoating(_ dt: Double) {
        boatX += (boatTargetX - boatX) * boatSmooth     // smooth / debounced steering
        boatSpeed = 1
        advanceWorld(dt)
        updateBird(dt)

        rockSpawn -= dt
        if rockSpawn <= 0 { spawnRock(); rockSpawn = Double.random(in: rockGap()) }
        hintSpawn -= dt
        if hintSpawn <= 0 { spawnHint(); hintSpawn = Double.random(in: 1.8...3.0) }
        leapSpawn -= dt
        if leapSpawn <= 0 {
            // A fish leaps where the fish are — at one of the ripple spots ahead.
            if let h = hints.filter({ $0.y > 0.08 && $0.y < 0.66 }).randomElement() {
                leaps.append(Leap(x: h.x, y: h.y, dir: Bool.random() ? 1 : -1))
            }
            leapSpawn = Double.random(in: 4...8)
        }

        if checkCollision() { return }
    }

    /// Handle the boat hitting an obstacle. With a pickaxe active, plain rocks burst apart and the
    /// boat sails on; everything else (and lighthouses/boats) still crashes. Returns true on a crash.
    private func checkCollision() -> Bool {
        guard let hit = rocks.first(where: { collides($0) }) else { return false }
        if rockBreakT > 0 && hit.kind == .rock {
            shatters.append(Shatter(x: hit.x, y: hit.y, r: hit.r, seed: hit.seed))
            rocks.removeAll { $0.id == hit.id }
            haptics.play(.tug)
            return false
        }
        crash()
        return true
    }

    /// Scrolls the water and drifts the rocks/ripples by the current (eased) world speed.
    private func advanceWorld(_ dt: Double) {
        let speed = baseScroll * (1 + scrollRamp * ramp) * scrollFactor
        scroll += speed * dt
        for i in rocks.indices { rocks[i].y += speed * dt }
        for i in hints.indices { hints[i].y += speed * dt; hints[i].phase += dt }
        for i in leaps.indices { leaps[i].y += speed * dt; leaps[i].age += dt }
        for i in shatters.indices { shatters[i].y += speed * dt; shatters[i].age += dt }
        updateDriftingBoats(dt)
        rocks.removeAll { $0.y > 1.15 }
        hints.removeAll { $0.y > 1.10 }
        leaps.removeAll { $0.age > leapDuration }
        shatters.removeAll { $0.age > shatterDuration }
    }

    private func tickCasting(_ dt: Double) {
        boatSpeed = 1
        advanceWorld(dt)                                          // boat still drifts slowly while you aim
        updateBird(dt)
        castReach = min(castMaxReach, castReach + castGrow * dt)  // line keeps extending until you tap
        if checkCollision() { return }                           // you can still hit a rock while aiming
        if castReach >= castMaxReach { dropCast() }              // auto-drop once the line is fully out
    }

    private func tickLaunch(_ dt: Double) {
        launchT += dt
        let accel = min(1, launchT / 0.8)
        let ease = accel * accel * (3 - 2 * accel)          // smoothstep: gentle slow departure…
        let speed = baseScroll * launchSpeedMult * ease     // …then cruises at ~sea speed
        harborScroll += speed * dt
        scroll += speed * dt                                // waves drift in lock-step → same feel
        // The wake only builds once the shore has slid off-screen, so nothing splashes on the beach.
        let cleared = max(0, min(1, (harborScroll - 0.18) / 0.30))
        boatSpeed = cleared * cleared * (3 - 2 * cleared)
        if harborScroll >= launchClearDist { phase = .boating }
    }

    private func tickHooking(_ dt: Double) {
        hookT += dt
        if hookT >= hookDuration { phase = .reeling }
    }

    private func tickSurfacing(_ dt: Double) {
        surfaceT += dt
        if surfaceT >= surfaceDuration {
            hooked = nil
            hookedSpecial = nil
            phase = surfaceCaught ? .landed : .boating
            landedT = 0
        }
    }

    private func tickLanded(_ dt: Double) {
        landedT += dt
        if landedT >= landedAutoTime { phase = .boating }   // auto-continue (or tap to skip)
    }

    private func tickCrash(_ dt: Double) {
        crashProgress = min(1, crashProgress + dt / crashDuration)
        if crashProgress >= 1 { phase = .gameOver; stop() }
    }

    private func tickReeling(_ dt: Double) {
        reelClock += dt

        // Predator attack in progress — cinematic; resolves at the end.
        if predatorActive {
            predatorT += dt
            if predatorT >= predatorAnimTime { resolvePredator() }
            return
        }
        // A predator strikes — rare, and not once you've basically landed the fish.
        if predatorPending && reelClock >= predatorAt && reelProgress < 0.9 {
            predatorPending = false
            predatorActive = true
            predatorT = 0
            showFlash("A BIG ONE!")
            haptics.play(.tug)
            return
        }

        // The safe zone drifts slowly — starting from a random point (not always the middle).
        zoneCenter = 0.5 + sin(reelClock * curZoneSpeed + zonePhase) * zoneAmp

        let inZone = abs(marker - zoneCenter) < curZoneHalf
        if inZone && !wasInZone { haptics.play(.reel) }   // little tick as you catch the zone
        wasInZone = inZone
        if !inZone { reelOutTime += dt }                  // drifting out costs your PERFECT

        reelProgress += (inZone ? curFillRate : -drainRate) * dt

        if reelProgress >= 1 { land(); return }
        if reelProgress <= 0 { lose("It got away!"); return }
        reelProgress = min(1, max(0, reelProgress))
    }

    private func resolvePredator() {
        predatorActive = false
        if Double.random(in: 0...1) < predatorSnapChance {
            lose("It bit through the line!")
        } else {
            // The big fish is now on your hook — bigger points, much harder to balance.
            hooked = .tuna
            hardFish = true
            reelProgress = 0.2
            marker = 0.5
            zonePhase = Double.random(in: 0...(2 * .pi))
            reelClock = 0
            wasInZone = false
            reelOutTime = 0
            showFlash("It took the bait!")
            haptics.play(.bite)
        }
    }

    // MARK: Casting / reeling resolution -----------------------------------

    private func startAim() {
        phase = .casting
        castReach = 0
        haptics.play(.cast)
    }

    /// Drop the line where the cast has reached and see what's there.
    private func dropCast() {
        let castY = boatY - castReach
        let target = hints
            .filter { abs($0.x - boatX) < castTol && abs($0.y - castY) < depthTol }
            .min(by: { a, b in
                let da = (a.x - boatX) * (a.x - boatX) + (a.y - castY) * (a.y - castY)
                let db = (b.x - boatX) * (b.x - boatX) + (b.y - castY) * (b.y - castY)
                return da < db
            })
        if let t = target {
            hints.removeAll { $0.id == t.id }
            hookFish(deep: t.deep)
        } else {
            lose("Nothing there")
        }
    }

    private func hookFish(deep: Bool) {
        // Occasionally you hook a special instead of a fish — you'll see what it is as you reel it up.
        let r = Double.random(in: 0...1)
        let special: Special? = r < mineChance ? .mine
            : r < mineChance + chestChance ? .chest
            : r < mineChance + chestChance + pickaxeChance ? .pickaxe : nil
        hookedSpecial = special
        hooked = special == nil ? rollFish(deep: deep) : nil

        reelProgress = 0.25
        marker = 0.5
        zonePhase = Double.random(in: 0...(2 * .pi))   // zone starts at a random spot
        zoneCenter = 0.5 + sin(zonePhase) * zoneAmp
        reelClock = 0
        wasInZone = false
        reelOutTime = 0
        hookT = 0
        hardFish = false
        predatorActive = false
        predatorT = 0
        // A predator may target a plain small/mid fish (not a special, boot or an already-big one).
        let upgradeable = special == nil && hooked != .tuna && hooked != .boot
        predatorPending = upgradeable && Double.random(in: 0...1) < predatorChance
        predatorAt = Double.random(in: predatorMinTime...predatorMaxTime)
        phase = .hooking            // brief "On the line!" transition → reeling
        haptics.play(.bite)
    }

    /// Deep water leans toward the big, valuable fish; shallow toward the small ones.
    private func rollFish(deep: Bool) -> FishKind {
        let roll = Double.random(in: 0...1)
        if deep {
            switch roll {
            case ..<0.08: return .boot
            case ..<0.35: return .cod
            case ..<0.70: return .salmon
            default:      return .tuna
            }
        } else {
            switch roll {
            case ..<0.10: return .boot
            case ..<0.55: return .herring
            case ..<0.88: return .mackerel
            default:      return .cod
            }
        }
    }

    private func land() {
        if let sp = hookedSpecial { landSpecial(sp); return }
        guard let kind = hooked else { return }

        // A scoring fish extends the streak; an old boot lands but neither builds nor breaks it.
        let scoring = kind.points > 0
        if scoring { streak += 1; comboMult = min(maxCombo, streak) }
        let perfect = scoring && reelOutTime <= perfectTol      // never (really) left the zone

        let mult = scoreMultiplier * (scoring ? comboMult : 1)  // chest × combo streak
        var pts = kind.points * mult
        if perfect { pts = Int((Double(pts) * perfectBonus).rounded()) }
        score += pts

        lastCatch = CaughtFish(kind: kind, points: pts)
        lastSpecial = nil
        lastComboMult = scoring ? comboMult : 1
        lastPerfect = perfect
        if scoring { triggerScorePop(pts, mult: comboMult, perfect: perfect) }

        surfaceCaught = true
        surfaceT = 0
        phase = .surfacing           // splash/flash transition → the result card
        haptics.play(kind.points >= 90 || comboMult >= 3 || perfect ? .catchBig : .catchSmall)
    }

    private func triggerScorePop(_ value: Int, mult: Int, perfect: Bool) {
        scorePop = value; scorePopMult = mult; scorePopPerfect = perfect; scorePopT = 0
    }

    /// Reeled a special all the way up: claim the chest/pickaxe — or set off the mine.
    private func landSpecial(_ sp: Special) {
        switch sp {
        case .mine:
            blowUp()
            return
        case .chest:
            doublePointsT = chestDuration
            showFlash("DOUBLE POINTS!")
            haptics.play(.catchBig)
        case .pickaxe:
            rockBreakT = pickaxeDuration
            showFlash("CLEAVE ROCKS!")
            haptics.play(.catchBig)
        }
        lastSpecial = sp
        lastCatch = nil
        surfaceCaught = true
        surfaceT = 0
        phase = .surfacing
    }

    /// The hooked mine reaches the boat and detonates — game over.
    private func blowUp() {
        phase = .crashing
        crashIsMine = true
        crashProgress = 0
        crashX = boatX; crashY = boatY
        hooked = nil; hookedSpecial = nil
        isBest = score > 0 && score > LocalStore.best()
        LocalStore.recordBest(score)
        showFlash("MINE!")
        haptics.play(.crash)
    }

    private func lose(_ reason: String) {
        if hookedSpecial != .mine { streak = 0; comboMult = 1 }   // a whiff or lost fish breaks the streak (a mine bail doesn't)
        showFlash(hookedSpecial == .mine ? "Phew — let it go!" : reason)   // bailing a mine is the smart play
        haptics.play(.miss)
        if phase == .reeling {       // we had something on — play the transition out
            surfaceCaught = false
            surfaceT = 0
            phase = .surfacing
        } else {                     // a plain missed cast
            hooked = nil
            hookedSpecial = nil
            phase = .boating
        }
    }

    private func crash() {
        phase = .crashing
        crashIsMine = false
        crashProgress = 0
        crashX = boatX; crashY = boatY
        isBest = score > 0 && score > LocalStore.best()
        LocalStore.recordBest(score)
        haptics.play(.crash)
        // The timer keeps running so the splash can animate; tickCrash flips to .gameOver.
    }

    // MARK: Spawning --------------------------------------------------------

    private func rockGap() -> ClosedRange<Double> {
        let tight = 0.55 * ramp        // rocks come faster as difficulty ramps
        return (1.4 - tight)...(2.6 - tight)
    }

    private func spawnRock() {
        let x = Double.random(in: edge...(1 - edge))
        let roll = Double.random(in: 0...1)
        if roll < 0.035 {
            // Very rare: a slow boat wandering the water, steering around the rocks.
            var o = Obstacle(x: x, y: -0.15, r: 0.052, kind: .boat)
            o.vx = Double.random(in: 0.06...0.10) * (Bool.random() ? 1 : -1)
            rocks.append(o)
        } else if roll < 0.14 {
            // Rarer: a lighthouse on a skerry, sweeping its beam around.
            rocks.append(Obstacle(x: x, y: -0.15, r: 0.085, kind: .lighthouse))
        } else {
            rocks.append(Obstacle(x: x, y: -0.1, r: Double.random(in: 0.06...0.10), kind: .rock))
        }
    }

    /// The rare wandering boat: drifts slowly sideways, nudging away from rocks, bouncing off the edges.
    private func updateDriftingBoats(_ dt: Double) {
        for i in rocks.indices where rocks[i].kind == .boat {
            var vx = rocks[i].vx
            for j in rocks.indices where rocks[j].kind != .boat {
                let dx = rocks[i].x - rocks[j].x, dy = rocks[i].y - rocks[j].y
                let near = rocks[i].r + rocks[j].r + 0.05
                if dx * dx + dy * dy < near * near {
                    vx += (dx >= 0 ? 1.0 : -1.0) * 0.20 * dt    // steer away from the rock
                }
            }
            vx = min(max(vx, -0.11), 0.11)                       // slow, but visibly working the water
            var x = rocks[i].x + vx * dt
            if x < edge       { x = edge;      vx = abs(vx) }    // bounce off the sides
            if x > 1 - edge   { x = 1 - edge;  vx = -abs(vx) }
            rocks[i].x = x
            rocks[i].vx = vx
        }
    }

    private func spawnHint() {
        hints.append(Hint(x: Double.random(in: 0.16...0.84),
                          y: -0.08,
                          deep: Bool.random()))
    }

    // MARK: Helpers ---------------------------------------------------------

    private func collides(_ r: Obstacle) -> Bool {
        let dx = (r.x - boatX), dy = (r.y - boatY)
        let rr = r.r + boatHitR
        return dx * dx + dy * dy < rr * rr
    }

    private func showFlash(_ text: String) { flash = text; flashTimer = 1.1 }
}
