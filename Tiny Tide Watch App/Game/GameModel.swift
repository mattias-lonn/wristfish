//
//  GameModel.swift
//  Tiny Tide — all the game logic and the 30 fps loop. No drawing here (see GameArt.swift).
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
    private var baseScroll  = 0.24      // how fast the water flows past while boating (per level)
    private var scrollRamp  = 0.6       // extra flow at full difficulty (per level)
    private var rampSeconds = 90.0      // time to reach full difficulty (per level)
    private let castScrollSlow = 0.22   // world keeps drifting at this fraction of speed while aiming
    private let scrollEase     = 0.10   // how smoothly the world speed eases in/out (the debounce)

    private let steerGain   = 0.017     // Crown → boat target sideways speed (gentler)
    private let boatSmooth  = 0.22      // how quickly the boat eases toward your steer (smoothing)
    private let wakeTrailLen = 14       // how many recent positions the wake trail remembers
    private let edge        = 0.10      // boat can't go past these x margins
    // Boat's vertical home. On the tall iPhone it sits low (0.80); on the near-square watch it rides a
    // bit higher so the bottom prompt/meter ("Tap to cast/harpoon") fits clearly BELOW the boat, like iPhone.
    var boatY: Double { renderAspect > designAspect + 0.05 ? 0.80 : 0.72 }
    private let boatHitR    = 0.080     // collision radius for the boat (vertical / general)
    /// The hull is drawn narrower than it is tall (half-width 0.066·W vs the 0.080 hit radius), so on a wide
    /// landscape screen (iPad) the sides crash slightly early. There we match the side hit radius to the hull;
    /// the bow/stern stay at boatHitR (the thin tips feel right). Watch, iPhone and iPad-portrait are unchanged.
    private var boatHitRx: Double { renderAspect < 1.0 ? 0.066 : boatHitR }
    /// Screen height ÷ width, set by the view each session. Collisions weight vertical distance by this
    /// (relative to the watch's shape) so the hit box matches the on-screen art on a tall iPhone, while
    /// staying identical on the watch. Defaults to the watch aspect the art was tuned for.
    private let designAspect: Double = 251.0 / 205.0
    var renderAspect: Double = 251.0 / 205.0
    /// Weights a vertical distance so Euclidean x/y hit checks stay isotropic in pixels (matching the
    /// drawn art). 1 on the watch (unchanged); the true aspect on any screen that deviates from the watch
    /// shape — taller (iPhone portrait) OR wider (iPad landscape), where 1.0 would squish the hit circle
    /// vertically. Same basis as collides().
    private var yFactor: Double { abs(renderAspect - designAspect) > 0.05 ? renderAspect : 1.0 }
    /// The world scrolls in normalized height/second, so on a tall iPhone the same value covers far more
    /// pixels/second and reads as much faster. Ease it back a notch on iPhone; the watch is unchanged.
    private var scrollPlatformFactor: Double { renderAspect > designAspect + 0.05 ? 0.74 : 1.0 }
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
    let castWindup  = 0.22              // the rod winds back this long before the line flies out (art mirrors this)
    private let depthTol    = 0.17      // how close (distance) the drop must match a ripple

    // Reeling — keep the Crown-controlled marker inside the slowly-drifting zone to land the fish.
    private let zoneHalf   = 0.15       // half-height of the safe zone (bigger = easier)
    private let zoneAmp    = 0.26       // how far from centre the zone drifts
    private let zoneSpeed  = 1.0        // zone drift speed (rad/s) — slow & steady
    private let markerGain = 0.017      // Crown → marker speed (gentler)
    private let fillRate   = 0.50       // catch progress gained per second while in the zone
    private let drainRate  = 0.28       // catch progress lost per second while outside

    // Sleigh ride — a hooked monster tows the boat: steer to stay on its tail and wear it down.
    private let sleighSpeedMul   = 2.1     // world rushes past while you're being towed
    private let sleighFishY      = 0.30    // the towed fish rides up here
    private let sleighWeaveSpeed = 1.6     // how fast it cuts side to side
    private let sleighWeaveAmp   = 0.30    // how wide it swings
    private let sleighAlignTol   = 0.13    // within this x-gap you're "on its tail"
    private let sleighDrainRate  = 0.16    // fish stamina lost per second while on its tail
    private let sleighRegenRate  = 0.05    // stamina it recovers while you're off its line
    private let sleighStrainRate = 1.3     // line strain gained per second per unit of misalignment
    private let sleighStrainFall = 0.8     // strain shed per second while on its tail
    private let sleighHaulDrain  = 0.07    // a tap yanks this much stamina…
    private let sleighHaulStrain = 0.12    // …at the cost of this much strain
    private let sleighBonus      = 1.6     // a towed catch is worth this much more — it's a fight

    // The Kraken — a rare set-piece: a monster surfaces and you dodge tentacle slams.
    private let krakenIntro    = 2.6       // a build-up (darkening, bubbles, the body rising) before any strikes
    private let krakenDuration = 14.0      // how long you must survive once it's fully up
    private let krakenHitR     = 0.10      // how close a slam must land to grab you
    let krakenTeleT    = 1.1               // a strike telegraphs for this long (earlier warning)…
    let krakenStrikeT  = 0.35             // …then slams (the dangerous window)…
    let krakenRecedeT  = 0.5              // …then sinks back
    private let krakenBonus    = 150       // points for surviving the whole thing (mostly dodging)
    private let krakenDriveOffBonus = 400  // extra for driving it off — the big, skill-gated prize
    // Harpooning the kraken — steer under a target and tap to fire straight up.
    private let harpoonSpeed   = 1.5       // how fast a harpoon flies up (normalized / s)
    private let harpoonReload  = 0.45      // min time between throws
    private let harpoonReachY  = 0.24      // a harpoon connects once it reaches this y (the body band)
    private let harpoonEyeR    = 0.055     // x-tolerance for an eye hit
    private let harpoonBodyHalf = 0.24     // x half-width of the body for a glancing hit
    private let harpoonEyeDmg  = 0.18      // resolve drained by an eye hit…
    private let harpoonBodyDmg = 0.06      // …and by a body hit
    private let harpoonEyePts  = 25        // points for an eye hit…
    private let harpoonBodyPts = 10        // …and a body hit

    // The Boot Beast — every couple of boots, a goofy boot-monster pops up and pelts you with boots.
    private let bootBeastEvery    = 2      // summon it every N boots landed this trip
    private let bootBeastIntro    = 1.8    // it rises for this long (a kraken-style build-up) before lobbing boots
    private let bootBeastDuration = 6.0    // how long the boot barrage lasts
    let bootThrowTele             = 0.6    // a throw telegraphs (warning ring) for this long…
    let bootThrowDrop             = 0.4    // …then the boot falls & lands
    private let bootThrowHitR     = 0.10   // how close a landing boot must be to bonk you
    private let bootDodgePts      = 25     // each dodged boot adds this to the payout…
    private let bootHitPenalty    = 20     // …each bonk takes this off
    private let bootBeastBase     = 80     // the payout starts here

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
    private(set) var displayScore: Double = 0   // HUD score, eased toward `score` for a satisfying count-up
    private var scoreBumpT = 1.0                 // ≥ scoreBumpDur → inactive (one-shot scale punch on a gain)
    private let scoreBumpDur = 0.32
    private(set) var elapsed: Double = 0
    private(set) var hasSteered = false              // player has used the Crown at least once this trip
    private var boatingStartElapsed: Double? = nil   // when the boat first became steerable (after the launch)
    private(set) var shakeAmp = 0.0                  // camera-shake magnitude (pt), kicked by impacts, decays each tick
    private func shake(_ a: Double) { shakeAmp = max(shakeAmp, a) }

    // A lone gull that passes over now and then — and very rarely dives to snatch your catch.
    private(set) var birdActive = false
    private(set) var birdDir = 1.0
    private(set) var birdDive = false          // this pass is a dive to snatch a fish in front of you
    private(set) var birdDiveTargetX = 0.5     // live position of the fish it's diving at…
    private(set) var birdDiveTargetY = 0.5     // …tracked so the swoop hits it exactly
    private(set) var birdXOffset = 0.0         // horizontal shift after the gull is knocked off course
    private(set) var birdHit = false           // your cast clipped it this pass (once per pass)
    private var birdCryAt = 0.5                 // progress (0–1) at which it cries — set per pass, well on-screen
    private var birdCried = false              // it has cried once this pass
    private(set) var feathers: [Feather] = []  // feathers fluttering down from a clipped gull

    // Sleigh-ride state (read by the art & HUD).
    private(set) var sleighStamina = 1.0       // 1 → 0; the fish tires, you land it at 0
    private(set) var sleighStrain  = 0.0       // 0 → 1; the line snaps at 1
    private(set) var towFishX = 0.5            // the towing fish's position…
    private(set) var towFishY = 0.30           // …ahead of the boat
    private var sleighClock = 0.0
    private var landingViaSleigh = false        // the catch being landed came in on a tow
    /// Catch progress for the HUD while being towed (fish worn down so far).
    var sleighCatchProgress: Double { 1 - sleighStamina }

    // Kraken state (read by the art & HUD).
    private(set) var tentacles: [Tentacle] = []
    private(set) var krakenT = 0.0
    private var krakenNextStrike = 0.0
    private var krakenEmerged = false
    private var krakenSpawn = Double.random(in: 55...95)
    private(set) var krakenHP = 1.0            // its resolve; drive it to 0 with harpoons to scare it off
    private(set) var harpoons: [Harpoon] = []
    private var harpoonCool = 0.0
    private(set) var harpoonHitX = 0.5         // last impact point + clock, for the hit burst
    private(set) var harpoonHitY = 0.0
    private(set) var harpoonHitT = 99.0
    /// 0→1 as the monster rises during the intro (drives the build-up visuals).
    var krakenEmerge: Double { min(1, krakenT / krakenIntro) }
    /// Combat progress for the survive meter — stays 0 through the intro.
    var krakenProgress: Double { min(1, max(0, (krakenT - krakenIntro) / krakenDuration)) }
    /// How worn down the kraken is (drives the HUD meter): 0 fresh → 1 driven off.
    var krakenDamage: Double { 1 - krakenHP }
    /// Briefly true at the start of combat (for the "tap to harpoon" hint).
    var krakenJustStarted: Bool { krakenProgress > 0 && krakenProgress < 0.16 }
    var harpoonHitActive: Bool { harpoonHitT < 0.35 }

    // Boot Beast state.
    private(set) var bootsThisTrip = 0
    private var pendingBootBeast = false
    private(set) var bootBeastT = 0.0
    private(set) var bootThrows: [BootThrow] = []
    private var bootThrowNext = 0.0
    private var bootBeastRevealed = false
    private(set) var bootBeastBonus = 0
    /// 0→1 as the boot beast rises (for the build-up visuals).
    var bootBeastEmerge: Double { min(1, bootBeastT / bootBeastIntro) }
    var bootBeastRising: Bool { bootBeastT < bootBeastIntro }
    /// How far through the boot barrage you are (for the slim HUD meter).
    var bootBeastProgress: Double { min(1, max(0, (bootBeastT - bootBeastIntro) / bootBeastDuration)) }

    // Reeling state
    private(set) var hooked: FishKind?
    private(set) var reelProgress: Double = 0   // catch progress: 0 = losing it, 1 = landed
    private(set) var marker = 0.5               // your Crown-controlled position on the gauge (0…1)
    private(set) var zoneCenter = 0.5           // centre of the slowly-drifting safe zone (0…1)
    private(set) var hardFish = false           // the upgraded big fish — harder to balance
    private(set) var predatorActive = false     // a predator is attacking the hooked fish right now
    private(set) var surfaceCaught = false      // did the surfacing transition follow a catch?
    private(set) var castReach = 0.0            // how far the current cast has reached (aiming/locked)
    private(set) var castT = 0.0                // seconds since the cast began (drives the rod animation)
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
    private(set) var flashGold = false        // reward-style flash (gold, centered) vs the usual coral
    private var flashTimer = 0.0

    // MARK: Private state
    private var timer: Timer?
    private let haptics = HapticsManager.shared
    private var rockSpawn = 1.2
    private var hintSpawn = 1.5
    private var worldDist = 0.0                 // water travelled since boating began (drives the script)
    private var scriptIndex = 0                 // next entry in the (sorted) scripted-spawn list
    private var sortedScript: [ScriptedSpawn] = []
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
    private let rockSmashPts      = 5          // points for cleaving a rock with the pickaxe
    let shatterDuration  = 0.55                // how long a rock-shatter burst plays
    private var mineChance    = 0.05           // chance a hooked catch is a mine…   (per level)
    private var chestChance   = 0.07           // …a chest…                          (per level)
    private var pickaxeChance = 0.06           // …or a pickaxe (otherwise a fish)   (per level)
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
    private let birdHitPts     = 15            // a small reward for the skill shot of clipping a gull
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
    private var dayLength = 150.0

    // The level being played (freeplay by default).
    private(set) var config = LevelConfig.freeplay

    // The chosen (cosmetic) boat for this trip.
    private(set) var boat = BoatModel.selected

    // Boat-unlock cameo: a newly-unlocked boat races past, weaving through the obstacles, flying a
    // pennant — celebrated in-world. "Already celebrated" is tracked in LocalStore so a boat unlocked at
    // a run's end (stars / single-run score) gets its lap at the start of the next run.
    private var cameoQueue: [BoatModel] = []
    private(set) var cameoBoat: BoatModel? = nil
    private(set) var cameoX = 0.5
    private(set) var cameoY = 1.3
    private var cameoT = 0.0
    private var cameoBoost = 1.0                       // eased speed multiplier — guns it when cornered
    private let cameoDuration = 5.0                    // leisurely lap (lower = faster)
    var cameoActive: Bool { cameoBoat != nil }
    var cameoName: String { cameoBoat?.name ?? "" }

    // Objective tracking (campaign).
    private(set) var fishCount = 0              // scoring fish landed this level
    private var caught: [FishKind: Int] = [:]   // per-species tally
    private(set) var levelTime = 0.0           // seconds of actual play (after the launch)
    private(set) var levelLosses = 0           // fish lost on the line this level
    private(set) var levelHadPerfect = false
    private(set) var bestComboReached = 0
    private(set) var levelWon = false
    private(set) var levelStars = 0
    private(set) var autoSail = false          // win card up → the boat keeps sailing, harmlessly, behind it
    private var pendingWin = false             // objective met — show the win card at the next stable moment

    var ramp: Double { min(1, elapsed / rampSeconds) }

    /// 0 = bright day → 1 = deep night. Fixed per campaign level, or cycles in freeplay.
    var timeOfDay: Double { config.fixedTimeOfDay ?? min(1, elapsed / dayLength) }

    /// True for a campaign level (has a goal), false for endless freeplay.
    var isCampaign: Bool { config.objective != nil }

    /// A short HUD line describing the level goal & progress.
    var objectiveText: String {
        guard let o = config.objective else { return "" }
        switch o {
        case .score(let n):              return "\(score) / \(n)"
        case .catchAny(let n):           return "\(fishCount) / \(n) fish"
        case .catchSpecies(let k, let n):return "\(caught[k] ?? 0) / \(n) \(k.name)"
        case .survive(let t):            return "\(max(0, Int((t - levelTime).rounded(.up))))s left"
        case .combo(let n):              return "Combo \(bestComboReached)× / \(n)×"
        case .noLoss(let n):             return "\(streak) / \(n) clean"
        case .reachFinish:               return "Reach the finish"
        }
    }

    /// Goal completion 0…1 (for the HUD meter).
    var objectiveProgress: Double {
        guard let o = config.objective else { return 0 }
        switch o {
        case .score(let n):              return clamp01(Double(score) / Double(n))
        case .catchAny(let n):           return clamp01(Double(fishCount) / Double(n))
        case .catchSpecies(let k, let n):return clamp01(Double(caught[k] ?? 0) / Double(n))
        case .survive(let t):            return clamp01(levelTime / t)
        case .combo(let n):              return clamp01(Double(bestComboReached) / Double(n))
        case .noLoss(let n):             return clamp01(Double(streak) / Double(n))
        case .reachFinish:               return clamp01(worldDist / (config.finishAt ?? 1))
        }
    }

    private func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// Screen-normalized y of the finish line — a fixed spot in the level that scrolls in with the
    /// water. nil until it has drifted into view (and on levels without one). It reaches the boat
    /// exactly when `worldDist` hits `config.finishAt`, so you literally sail across it.
    var finishLineY: Double? {
        guard let fa = config.finishAt else { return nil }
        let y = boatY - (fa - worldDist)        // at the top when far off, at the boat on arrival
        return (y > -0.06 && y < 1.1) ? y : nil
    }

    private func objectiveMet() -> Bool {
        guard let o = config.objective else { return false }
        switch o {
        case .score(let n):              return score >= n
        case .catchAny(let n):           return fishCount >= n
        case .catchSpecies(let k, let n):return (caught[k] ?? 0) >= n
        case .survive(let t):            return levelTime >= t
        case .combo(let n):              return bestComboReached >= n
        case .noLoss(let n):             return streak >= n
        case .reachFinish:               return worldDist >= (config.finishAt ?? .infinity)
        }
    }

    private func checkObjective() {
        guard isCampaign, !levelWon, !pendingWin else { return }
        if objectiveMet() { pendingWin = true }
    }

    /// Wrap up a cleared level: tally stars, save them, and show the win card.
    private func winLevel() {
        levelWon = true
        pendingWin = false
        levelStars = computeStars()
        LocalStore.recordStars(level: config.id, stars: levelStars)
        LocalStore.recordRun(score)         // single-run best → the golden boat
        flash = ""; flashTimer = 0          // clear any lingering banner so the card is clean
        haptics.play(.catchBig)
        phase = .gameOver
        autoSail = true                     // keep the loop running so the boat drifts on behind the card
    }

    /// 1 star for clearing, +1 for losing no fish, +1 for a perfect reel or a 3× combo.
    private func computeStars() -> Int {
        var s = 1
        if levelLosses == 0 { s += 1 }
        if levelHadPerfect || bestComboReached >= 3 { s += 1 }
        return min(3, s)
    }

    /// The streak multiplier is worth showing once it's ≥ 2×.
    var comboActive: Bool { comboMult >= 2 }
    /// The floating "+points" is still on screen.
    var scorePopActive: Bool { scorePopT < scorePopDuration }
    var scorePopProgress: Double { min(1, scorePopT / scorePopDuration) }

    /// The HUD score, counting up toward the real total.
    var hudScore: Int { Int(displayScore.rounded()) }
    /// A brief scale punch on the score the moment points land (1 → ~1.28 → 1).
    var scoreBumpScale: Double {
        guard scoreBumpT < scoreBumpDur else { return 1 }
        return 1 + 0.28 * sin(scoreBumpT / scoreBumpDur * .pi)
    }

    /// How far into night we are (0 day … 1 deep night) — matches the visual GameArt.nightAmount.
    /// Drives the night fish bias in rollFish (the night leans toward bigger / deep fish).
    var nightLevel: Double { max(0, min(1, (timeOfDay - 0.6) / 0.4)) }

    /// Show the "Crown to steer" nudge only once input is actually live — for the first ~4s of boating,
    /// before the player has steered and before they've scored. (Not during the launch, when the Crown
    /// is ignored, which previously made the hint look broken.)
    var showSteerHint: Bool {
        guard phase == .boating, !hasSteered, score == 0, let t0 = boatingStartElapsed else { return false }
        return elapsed - t0 < 4
    }

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

    // Gauge difficulty — tighter & faster once a big fish is on. The safe zone (the blue band you keep the
    // marker inside) is a touch smaller on the larger iPhone screen so landing a fish is a bit harder;
    // the watch is unchanged. Drives both the catch logic and the drawn zone, so they stay in sync.
    private var zonePlatformFactor: Double { renderAspect > designAspect + 0.05 ? 0.80 : 1.0 }
    private var curZoneHalf: Double  { (hardFish ? hardZoneHalf : zoneHalf) * zonePlatformFactor }
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

    /// Start (or restart) a playthrough of the given level. Defaults to endless freeplay.
    func start(_ config: LevelConfig = .freeplay) {
        self.config = config
        boat = BoatModel.selected            // pick up the player's chosen boat for this trip
        baseScroll = config.baseScroll
        scrollRamp = config.scrollRamp
        rampSeconds = config.rampSeconds
        dayLength = config.dayLength
        mineChance = config.specials.mine
        chestChance = config.specials.chest
        pickaxeChance = config.specials.pickaxe
        sortedScript = config.script.sorted { $0.at < $1.at }
        resetState()
        startTimer()
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Pause the loop without losing state — for when the app backgrounds (wrist down, a notification)
    /// so a reel/dodge isn't lost to an interruption. `resume()` picks up exactly where it left off.
    func pause() { timer?.invalidate(); timer = nil }
    func resume() { if timer == nil { startTimer() } }

    private func resetState() {
        phase = .launching
        boatX = 0.5; boatTargetX = 0.5; scroll = 0; score = 0; displayScore = 0; scoreBumpT = 1; elapsed = 0
        hasSteered = false; boatingStartElapsed = nil; shakeAmp = 0
        cameoQueue = []; cameoBoat = nil; cameoT = 0; cameoY = 1.3; cameoX = 0.5
        checkBoatUnlocks()   // a boat unlocked at the previous run's end gets its cameo as this run begins
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
        worldDist = 0; scriptIndex = 0
        sleighStamina = 1; sleighStrain = 0; sleighClock = 0; towFishX = 0.5; towFishY = sleighFishY
        landingViaSleigh = false
        tentacles = []; krakenT = 0; krakenNextStrike = 0; krakenEmerged = false
        krakenHP = 1; harpoons = []; harpoonCool = 0; harpoonHitT = 99
        krakenSpawn = config.krakenFirstAt ?? Double.random(in: 55...95)
        bootsThisTrip = 0; pendingBootBeast = false; bootBeastT = 0; bootBeastRevealed = false
        bootThrows = []; bootThrowNext = 0; bootBeastBonus = 0
        fishCount = 0; caught = [:]; levelTime = 0; levelLosses = 0
        levelHadPerfect = false; bestComboReached = 0; levelWon = false; levelStars = 0
        pendingWin = false; autoSail = false
    }

    /// A lone gull drifts across every so often. Your cast can now interact with it: a line dropped
    /// in front of it slows it down (like a banana on the track), and a line that clips it knocks
    /// feathers loose and sends it veering off the other way.
    private func updateBird(_ dt: Double) {
        if birdActive {
            updateBirdInteraction()                       // line in front slows it / a clip knocks it about
            birdSpeed += (birdSpeedTarget - birdSpeed) * 0.18
            birdT += dt * birdSpeed
            if !birdCried && birdProgress >= birdCryAt {  // now it's well on-screen → let it cry, once
                birdCried = true
                SoundManager.shared.play(.gull)
            }
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
            guard config.birds else { return }            // some levels have no gulls
            birdSpawn -= dt
            if birdSpawn <= 0 {
                birdActive = true; birdT = 0
                birdDir = Bool.random() ? 1 : -1
                birdDive = Double.random(in: 0...1) < birdDiveChance   // sometimes it dives, sometimes not
                birdCommitted = false; birdGrabbed = false; birdDiveHintID = nil
                birdDiveTargetX = boatX; birdDiveTargetY = boatY - 0.28
                birdXOffset = 0; birdHit = false
                // It crosses the screen over progress ~0.13→0.95; cry once well inside that window
                // (≈0.5s after it enters to ≈0.5s before it leaves), never while still off-screen.
                birdCried = false; birdCryAt = Double.random(in: 0.22...0.86)
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
        let dx = hook.x - bp.x, dy = (hook.y - bp.y) * yFactor
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
        let pts = birdHitPts * scoreMultiplier
        award(pts)
        showFlash("Bonk! +\(pts)")
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
        case .boating, .sleighRide, .kraken, .bootBeast:
            if delta != 0 { hasSteered = true }
            boatTargetX = min(max(boatTargetX + delta * steerGain, edge), 1 - edge)
        case .reeling:
            marker = min(max(marker + delta * markerGain, 0), 1)   // move your gauge marker
        default:
            break
        }
    }

    func tap() {
        switch phase {
        case .boating:    startAim()         // first tap — the line starts going out
        case .casting:    if castReach > 0 { dropCast() }   // drop once the line is actually out (past the wind-up)
        case .sleighRide: sleighHaul()       // yank to tire it faster — but it strains the line
        case .kraken:     fireHarpoon()      // throw a harpoon straight up at the monster
        default:          break              // reeling / landed / gameOver: ignore (the catch card auto-continues)
        }
    }

    /// Launch a harpoon up from the boat (only once the kraken is up and the line has reloaded).
    private func fireHarpoon() {
        guard krakenEmerged, harpoonCool <= 0 else { return }
        harpoons.append(Harpoon(x: boatX, y: boatY - 0.06))
        harpoonCool = harpoonReload
        haptics.play(.cast)
    }

    /// A desperate yank during the tow: tires the fish faster, but spikes line strain.
    private func sleighHaul() {
        sleighStamina = max(0, sleighStamina - sleighHaulDrain)
        sleighStrain = min(1, sleighStrain + sleighHaulStrain)
        haptics.play(.tug)
    }

    /// Called by the result card's Play-again / Retry button — replays the current level.
    func restart() { start(config) }

    // MARK: The loop --------------------------------------------------------

    private func tick() {
        let dt = 1.0 / fps
        elapsed += dt
        if phase != .launching && phase != .gameOver && !levelWon { levelTime += dt }
        if flashTimer > 0 { flashTimer -= dt; if flashTimer <= 0 { flash = ""; flashGold = false } }
        if phase != .surfacing && phase != .landed {                          // power-ups freeze behind the
            if doublePointsT > 0 { doublePointsT = max(0, doublePointsT - dt) } // catch card — you don't lose
            if rockBreakT > 0 { rockBreakT = max(0, rockBreakT - dt) }          // pickaxe/double-points seconds
        }                                                                       // while reading what you got
        updateFeathers(dt)                                                    // knocked-loose feathers settle & fade
        if scorePopT < scorePopDuration { scorePopT += dt }                   // the floating "+points" rises & fades
        if harpoonHitT < 0.35 { harpoonHitT += dt }                           // the harpoon hit-burst fades
        if scoreBumpT < scoreBumpDur { scoreBumpT += dt }                     // the score's scale-punch settles
        shakeAmp = shakeAmp > 0.05 ? shakeAmp * 0.84 : 0                       // camera shake decays out quickly
        if displayScore != Double(score) {                                    // HUD score counts up toward the real total
            displayScore += (Double(score) - displayScore) * 0.28
            if abs(Double(score) - displayScore) < 0.5 { displayScore = Double(score) }
        }

        // Ease world speed: full while boating, a slow drift while aiming, a calm drift behind the win card.
        let targetFactor = (phase == .casting) ? castScrollSlow : (phase == .gameOver ? 0.45 : 1.0)
        scrollFactor += (targetFactor - scrollFactor) * scrollEase

        // Record the boat's path for the wake (while it's on the water — including the showcase sail).
        if phase == .launching || phase == .boating || phase == .casting || phase == .sleighRide
            || phase == .kraken || phase == .bootBeast || (phase == .gameOver && autoSail) {
            wakeTrail.insert(boatX, at: 0)
            if wakeTrail.count > wakeTrailLen { wakeTrail.removeLast() }
        }

        switch phase {
        case .launching: tickLaunch(dt)
        case .boating:   tickBoating(dt)
        case .casting:   tickCasting(dt)
        case .hooking:   tickHooking(dt)
        case .reeling:   tickReeling(dt)
        case .sleighRide: tickSleigh(dt)
        case .kraken:    tickKraken(dt)
        case .bootBeast: tickBootBeast(dt)
        case .surfacing: tickSurfacing(dt)
        case .crashing:  tickCrash(dt)
        case .landed:    tickLanded(dt)
        case .gameOver:  if autoSail { tickShowcase(dt) }
        }

        // A newly-unlocked boat does a cameo lap — only while the top-down world is on screen.
        if isWorldPhase {
            if cameoBoat == nil, !cameoQueue.isEmpty { startCameo(cameoQueue.removeFirst()) }
            if cameoBoat != nil { tickCameo(dt) }
        }

        // Campaign: claim the win at a calm moment (for finish-line levels that's the crossing itself).
        checkObjective()
        if pendingWin && !levelWon && (phase == .boating || phase == .casting || phase == .landed) {
            winLevel()
        }
        if pendingBootBeast && phase == .boating { startBootBeast() }   // a couple of boots → the beast
        objectWillChange.send()
    }

    // MARK: Boat-unlock cameo -----------------------------------------------

    /// Where a boat-unlock cameo may run. Excludes `.landed` so a cameo never overlaps the "what you
    /// caught" card — it waits until that card clears and play resumes.
    private var isWorldPhase: Bool {
        switch phase {
        case .boating, .casting, .sleighRide, .kraken, .bootBeast: return true
        default: return false
        }
    }

    /// Queue a cameo lap for any unlocked boat that hasn't been celebrated yet (mid-run crossings and
    /// run-end unlocks alike). Marking happens immediately so it only ever laps once.
    private func checkBoatUnlocks() {
        for b in BoatModel.all where b.isUnlocked && !LocalStore.isCelebrated(b.id) {
            LocalStore.markCelebrated(b.id)
            cameoQueue.append(b)
        }
    }

    private func startCameo(_ b: BoatModel) {
        cameoBoat = b
        cameoT = 0
        cameoBoost = 1.0
        cameoY = 1.3                 // just below the screen
        cameoX = min(max(boatX + 0.2, 0.2), 0.8)   // come in a lane over from the player
        showFlash("New boat unlocked\n\(b.name) is now in your harbor", gold: true, duration: 2.6)
        SoundManager.shared.play(.unlock)          // a little fanfare
        haptics.play(.catchBig, sound: false)
    }

    private func tickCameo(_ dt: Double) {
        guard cameoBoat != nil else { return }
        cameoT += dt

        // --- Steer: a smooth avoidance field. Every nearby rock and the player's boat exert a soft
        // sideways push that ramps up with proximity — no on/off target snapping, so the path is smooth.
        var push = 0.0
        func repel(x ox: Double, y oy: Double, radius r: Double, strength: Double) {
            let vIn = 1 - min(1, abs(oy - cameoY) / (0.32 + r))      // 0…1 vertical nearness
            guard vIn > 0 else { return }
            let dx = cameoX - ox
            let hIn = 1 - min(1, abs(dx) / (0.24 + r))               // 0…1 horizontal nearness
            guard hIn > 0 else { return }
            let dir = abs(dx) < 0.03 ? (ox <= 0.5 ? 1.0 : -1.0)      // head-on: peel toward open water
                                     : (dx >= 0 ? 1.0 : -1.0)
            push += dir * vIn * hIn * hIn * strength                 // hIn² → gentle far, firmer up close
        }
        for o in rocks { repel(x: o.x, y: o.y, radius: o.r, strength: 0.55) }
        repel(x: boatX, y: boatY, radius: 0.05, strength: 0.7)       // dodge the player's boat too

        let targetX = min(max(0.5 + sin(cameoT * 1.3) * 0.16 + push, 0.1), 0.9)
        cameoX += (targetX - cameoX) * 0.16                          // gentle ease → smooth weaving

        // --- Climb: steady, but gun it when pinned against the player (no room, or they charge us) ---
        var cornered = false
        if abs(boatY - cameoY) < 0.14 && abs(cameoX - boatX) < 0.12 {
            let away = cameoX >= boatX ? 1.0 : -1.0
            let pinnedToEdge = cameoX + away * 0.12 < 0.1 || cameoX + away * 0.12 > 0.9
            let charging = (boatTargetX - boatX) * away > 0
            cornered = pinnedToEdge || charging
        }
        cameoBoost += ((cornered ? 2.6 : 1.0) - cameoBoost) * 0.18
        cameoY -= (1.6 / cameoDuration) * cameoBoost * dt            // up the screen, overtaking the world
        if cameoY < -0.35 { cameoBoat = nil }                       // sailed off the top
    }

    private func tickBoating(_ dt: Double) {
        boatX += (boatTargetX - boatX) * boatSmooth     // smooth / debounced steering
        boatSpeed = 1
        advanceWorld(dt)
        updateBird(dt)

        if config.rockSpawn != nil {
            rockSpawn -= dt
            if rockSpawn <= 0 { spawnRock(); rockSpawn = Double.random(in: rockGap()) }
        }
        if let hr = config.hintSpawn {
            hintSpawn -= dt
            if hintSpawn <= 0 { spawnHint(); hintSpawn = Double.random(in: hr) }
        }
        leapSpawn -= dt
        if leapSpawn <= 0 {
            // A fish leaps where the fish are — at one of the ripple spots ahead.
            if let h = hints.filter({ $0.y > 0.08 && $0.y < 0.66 }).randomElement() {
                leaps.append(Leap(x: h.x, y: h.y, dir: Bool.random() ? 1 : -1))
            }
            leapSpawn = Double.random(in: 4...8)
        }

        if config.kraken {
            krakenSpawn -= dt
            if krakenSpawn <= 0 { startKraken(); return }
        }

        if checkCollision() { return }
    }

    /// Handle the boat hitting an obstacle. With a pickaxe active, plain rocks burst apart and the
    /// boat sails on; everything else (and lighthouses/boats) still crashes. Returns true on a crash.
    private func checkCollision() -> Bool {
        guard config.lethal, !pendingWin else { return false }   // relaxed levels & the victory lap are safe
        guard let hit = rocks.first(where: { collides($0) }) else { return false }
        if rockBreakT > 0 && hit.kind == .rock {
            shatters.append(Shatter(x: hit.x, y: hit.y, r: hit.r, seed: hit.seed))
            rocks.removeAll { $0.id == hit.id }
            award(rockSmashPts * scoreMultiplier)          // cleaving a rock pays a little
            LocalStore.addRock()                           // lifetime tally (the Stonebreaker boat)
            checkBoatUnlocks()                             // 50 rocks → cameo
            haptics.play(.tug)
            return false
        }
        crash()
        return true
    }

    /// Scrolls the water and drifts the rocks/ripples by the current (eased) world speed.
    /// `speedMul` lets the sleigh ride rush the world past faster.
    private func advanceWorld(_ dt: Double, speedMul: Double = 1) {
        let speed = baseScroll * (1 + scrollRamp * ramp) * scrollFactor * speedMul * scrollPlatformFactor
        scroll += speed * dt
        worldDist += speed * dt
        processScript()
        for i in rocks.indices { rocks[i].y += speed * dt }
        for i in hints.indices { hints[i].y += speed * dt; hints[i].phase += dt }
        for i in leaps.indices {
            leaps[i].y += speed * dt; leaps[i].age += dt
            if !leaps[i].splashed && leaps[i].age >= leapDuration * 0.78 {   // it drops back in → a faint plip
                leaps[i].splashed = true
                SoundManager.shared.play(.leapSplash)
            }
        }
        for i in shatters.indices { shatters[i].y += speed * dt; shatters[i].age += dt }
        updateDriftingBoats(dt)
        rocks.removeAll { $0.y > 1.15 }
        hints.removeAll { $0.y > 1.10 }
        leaps.removeAll { $0.age > leapDuration }
        shatters.removeAll { $0.age > shatterDuration }
    }

    /// Behind the win card: the boat keeps sailing on a gentle weave, alive but harmless (no crashes,
    /// no new rocks). Existing obstacles just drift past the invulnerable boat.
    private func tickShowcase(_ dt: Double) {
        boatTargetX = 0.5 + sin(elapsed * 0.45) * 0.16            // slow, calm weave
        boatX += (boatTargetX - boatX) * boatSmooth
        boatSpeed = 1
        advanceWorld(dt)                                          // calm drift (scrollFactor eased to 0.45)
        updateBird(dt)
        leapSpawn -= dt
        if leapSpawn <= 0 {
            if let h = hints.filter({ $0.y > 0.08 && $0.y < 0.66 }).randomElement() {
                leaps.append(Leap(x: h.x, y: h.y, dir: Bool.random() ? 1 : -1))
            }
            leapSpawn = Double.random(in: 4...8)
        }
    }

    private func tickCasting(_ dt: Double) {
        boatSpeed = 1
        castT += dt
        advanceWorld(dt)                                          // boat still drifts slowly while you aim
        updateBird(dt)
        if castT >= castWindup {                                  // hold the line in while the rod winds back
            castReach = min(castMaxReach, castReach + castGrow * dt)
        }
        if checkCollision() { return }                           // you can still hit a rock while aiming
        if castReach >= castMaxReach { dropCast() }              // auto-drop once the line is fully out
    }

    private func tickLaunch(_ dt: Double) {
        launchT += dt
        let accel = min(1, launchT / 0.8)
        let ease = accel * accel * (3 - 2 * accel)          // smoothstep: gentle slow departure…
        let speed = baseScroll * launchSpeedMult * ease * scrollPlatformFactor   // …then cruises at ~sea speed
        harborScroll += speed * dt
        scroll += speed * dt                                // waves drift in lock-step → same feel
        // The wake only builds once the shore has slid off-screen, so nothing splashes on the beach.
        let cleared = max(0, min(1, (harborScroll - 0.18) / 0.30))
        boatSpeed = cleared * cleared * (3 - 2 * cleared)
        if harborScroll >= launchClearDist {
            phase = .boating
            if boatingStartElapsed == nil { boatingStartElapsed = elapsed }   // start the steer-hint window now (input is live)
        }
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
            // The big fish is now on your hook — and it's strong enough to tow you. Hang on!
            startSleighRide(.tuna)
        }
    }

    // MARK: Sleigh ride -----------------------------------------------------

    /// A big fish takes off, towing the boat. Steer to stay on its tail and wear it down.
    private func startSleighRide(_ kind: FishKind) {
        hooked = kind
        hookedSpecial = nil
        hardFish = false
        predatorActive = false; predatorPending = false; predatorT = 0
        sleighStamina = 1.0
        sleighStrain = 0.0
        sleighClock = 0
        towFishX = boatX
        towFishY = sleighFishY
        phase = .sleighRide
        showFlash("HANG ON!")
        haptics.play(.bite)
    }

    private func tickSleigh(_ dt: Double) {
        sleighClock += dt
        boatX += (boatTargetX - boatX) * boatSmooth            // you still steer the boat
        boatSpeed = 1
        advanceWorld(dt, speedMul: sleighSpeedMul)             // the world rushes past

        if config.rockSpawn != nil {                           // rocks to dodge while you're dragged
            rockSpawn -= dt
            if rockSpawn <= 0 { spawnRock(); rockSpawn = Double.random(in: rockGap()) }
        }

        // The fish cuts side to side ahead of you (two sines so it's not a clean metronome).
        let target = 0.5 + sin(sleighClock * sleighWeaveSpeed) * sleighWeaveAmp
                         + sin(sleighClock * 0.7 + 1.3) * (sleighWeaveAmp * 0.35)
        towFishX += (min(max(target, edge), 1 - edge) - towFishX) * 0.10
        towFishY = sleighFishY

        // On its tail → drain its stamina & ease the line; off its line → it recovers & strain builds.
        let gap = abs(boatX - towFishX)
        if gap <= sleighAlignTol {
            sleighStamina = max(0, sleighStamina - sleighDrainRate * dt)
            sleighStrain  = max(0, sleighStrain  - sleighStrainFall * dt)
        } else {
            sleighStamina = min(1, sleighStamina + sleighRegenRate * dt)
            sleighStrain  = min(1, sleighStrain  + sleighStrainRate * (gap - sleighAlignTol) * dt)
        }

        // A rock at this speed tears the hook free — you lose the fish, but the trip sails on.
        if let hit = rocks.first(where: { collides($0) }) {
            if hit.kind == .rock {
                shatters.append(Shatter(x: hit.x, y: hit.y, r: hit.r, seed: hit.seed))   // it bursts apart
            }
            rocks.removeAll { $0.id == hit.id }
            loseSleigh("It pulled free!")
            return
        }
        if sleighStrain >= 1 { loseSleigh("The line snapped!"); return }
        if sleighStamina <= 0 { landSleigh(); return }
    }

    private func loseSleigh(_ reason: String) {
        streak = 0; comboMult = 1                     // a snapped tow loses the fish — the combo resets
        levelLosses += 1
        showFlash(reason)
        haptics.play(.miss)
        hooked = nil
        phase = .boating
    }

    private func landSleigh() {
        reelProgress = 1                 // it's at the surface
        reelOutTime = perfectTol + 1     // a tow isn't a "perfect" balance reel
        landingViaSleigh = true          // …but it earns the tow bonus
        land()                           // score it, build combo, surface → landed
    }

    // MARK: The Kraken ------------------------------------------------------

    /// A monster begins to surface. The field clears gently (no new spawns; old rocks drift off) while
    /// the deep darkens and the body rises — then the tentacles come.
    private func startKraken() {
        phase = .kraken
        krakenT = 0
        tentacles = []
        krakenEmerged = false
        krakenHP = 1; harpoons = []; harpoonCool = 0
        hints.removeAll(); leaps.removeAll()    // ripples fade; rocks just drift off during the build-up
        birdActive = false                      // no gull frozen mid-flight during the encounter
        haptics.play(.tug)                      // a distant rumble as it stirs below
    }

    private func tickKraken(_ dt: Double) {
        krakenT += dt
        boatX += (boatTargetX - boatX) * boatSmooth
        boatSpeed = 1
        advanceWorld(dt, speedMul: 0.4)              // slow, ominous drift (no spawns)

        // Build-up: the monster is still rising — no strikes yet, just the dread.
        guard krakenT >= krakenIntro else { return }
        if !krakenEmerged {                          // the moment it breaks the surface
            krakenEmerged = true
            krakenNextStrike = 0.5
            SoundManager.shared.play(.kraken)        // a low groan from the deep
            haptics.play(.crash, sound: false)
        }

        for i in tentacles.indices { tentacles[i].age += dt }
        tentacles.removeAll { $0.age >= krakenTeleT + krakenStrikeT + krakenRecedeT }

        krakenNextStrike -= dt
        if krakenNextStrike <= 0 {
            spawnTentacle()
            let prog = krakenProgress                 // it rages faster as it goes
            krakenNextStrike = (1.6 - 0.85 * prog) * Double.random(in: 0.85...1.15)
        }

        // Harpoons fly up; resolve any that reach the body band.
        if harpoonCool > 0 { harpoonCool -= dt }
        for i in harpoons.indices { harpoons[i].y -= harpoonSpeed * dt }
        harpoons.removeAll { resolveHarpoon($0) || $0.y < -0.05 }
        if krakenHP <= 0 { endKraken(drivenOff: true); return }

        // Grabbed if a tentacle slams where the boat is, during its strike window.
        for tnt in tentacles where tnt.age >= krakenTeleT && tnt.age < krakenTeleT + krakenStrikeT {
            if abs(boatX - tnt.x) < krakenHitR {
                showFlash("GRABBED!")
                crash()
                return
            }
        }

        if krakenT >= krakenIntro + krakenDuration { endKraken(drivenOff: false) }
    }

    /// True (consume the harpoon) if it lands on the body or an eye; applies damage & points.
    private func resolveHarpoon(_ h: Harpoon) -> Bool {
        guard h.y <= harpoonReachY else { return false }
        let cx = 0.5
        let dEye = min(abs(h.x - (cx - 0.088)), abs(h.x - (cx + 0.088)))
        if dEye < harpoonEyeR {
            krakenHP = max(0, krakenHP - harpoonEyeDmg)
            award(harpoonEyePts * scoreMultiplier)
            harpoonHitX = h.x; harpoonHitY = h.y; harpoonHitT = 0
            shake(2.5)
            haptics.play(.tug)
            return true
        } else if abs(h.x - cx) < harpoonBodyHalf {
            krakenHP = max(0, krakenHP - harpoonBodyDmg)
            award(harpoonBodyPts * scoreMultiplier)
            harpoonHitX = h.x; harpoonHitY = h.y; harpoonHitT = 0
            haptics.play(.reel)
            return true
        }
        return false       // flew past the body — let it sail off the top
    }

    private func spawnTentacle() {
        // Most slams aim near you (forcing a dodge); some land wide.
        let aimed = Double.random(in: 0...1) < 0.6
        let x = aimed ? boatX + Double.random(in: -0.18...0.18) : Double.random(in: 0.12...0.88)
        tentacles.append(Tentacle(x: min(0.9, max(0.1, x)), seed: Int.random(in: 0..<100_000)))
    }

    private func endKraken(drivenOff: Bool) {
        tentacles = []; harpoons = []
        let bonus = (krakenBonus + (drivenOff ? krakenDriveOffBonus : 0)) * scoreMultiplier
        award(bonus)
        triggerScorePop(bonus, mult: 1, perfect: false)
        showFlash(drivenOff ? "DROVE IT OFF!" : "SURVIVED!")
        haptics.play(.catchBig)
        checkObjective()
        phase = .boating
        krakenSpawn = Double.random(in: 90...150)        // long cooldown before it returns
    }

    // MARK: The Boot Beast --------------------------------------------------

    /// A goofy monster made of boots pops up and lobs boots at you — dodge them to build a payout.
    private func startBootBeast() {
        phase = .bootBeast
        pendingBootBeast = false
        bootBeastT = 0
        bootThrows = []
        bootThrowNext = bootBeastIntro + 0.3
        bootBeastBonus = bootBeastBase
        rocks.removeAll(); hints.removeAll(); leaps.removeAll()
        birdActive = false
        bootBeastRevealed = false
        haptics.play(.tug)                                   // a rumble as it stirs (like the kraken)
    }

    private func tickBootBeast(_ dt: Double) {
        bootBeastT += dt
        boatX += (boatTargetX - boatX) * boatSmooth
        boatSpeed = 1
        advanceWorld(dt, speedMul: 0.4)

        guard bootBeastT >= bootBeastIntro else { return }   // still rising
        if !bootBeastRevealed {                                                   // it breaks the surface
            bootBeastRevealed = true
            SoundManager.shared.play(.bootBeast)                                  // a comedic boing
            haptics.play(.bite, sound: false)
        }

        // Lob boots, faster as it goes.
        bootThrowNext -= dt
        if bootThrowNext <= 0 {
            let aimed = Double.random(in: 0...1) < 0.6
            let x = aimed ? boatX + Double.random(in: -0.18...0.18) : Double.random(in: 0.12...0.88)
            bootThrows.append(BootThrow(x: min(0.9, max(0.1, x))))
            let prog = min(1, (bootBeastT - bootBeastIntro) / bootBeastDuration)
            bootThrowNext = (0.9 - 0.35 * prog) * Double.random(in: 0.85...1.15)
        }

        // Resolve each boot as it lands: a near miss pays, a bonk costs (no crash — it's all in fun).
        let resolveAt = bootThrowTele + bootThrowDrop * 0.65
        for i in bootThrows.indices where !bootThrows[i].resolved && bootThrows[i].age + dt >= resolveAt {
            bootThrows[i].resolved = true
            if abs(boatX - bootThrows[i].x) < bootThrowHitR {
                bootBeastBonus = max(0, bootBeastBonus - bootHitPenalty)
                shake(4)
                haptics.play(.miss)
            } else {
                bootBeastBonus += bootDodgePts
                haptics.play(.reel)
            }
        }
        for i in bootThrows.indices { bootThrows[i].age += dt }
        bootThrows.removeAll { $0.age >= bootThrowTele + bootThrowDrop + 0.15 }

        if bootBeastT >= bootBeastIntro + bootBeastDuration { endBootBeast() }
    }

    private func endBootBeast() {
        bootThrows = []
        let bonus = bootBeastBonus * scoreMultiplier
        award(bonus)
        triggerScorePop(bonus, mult: 1, perfect: false)
        showFlash("BEAST BUSTED!")
        haptics.play(.catchBig)
        checkObjective()
        phase = .boating
    }

    // MARK: Casting / reeling resolution -----------------------------------

    private func startAim() {
        phase = .casting
        castReach = 0
        castT = 0
        haptics.play(.cast)
    }

    /// Drop the line where the cast has reached and see what's there.
    private func dropCast() {
        SoundManager.shared.play(.plop)          // the lure hits the water
        let castY = boatY - castReach
        let target = hints
            .filter { abs($0.x - boatX) < castTol && abs($0.y - castY) < depthTol }
            .min(by: { a, b in
                let dyA = (a.y - castY) * yFactor, dyB = (b.y - castY) * yFactor
                let da = (a.x - boatX) * (a.x - boatX) + dyA * dyA
                let db = (b.x - boatX) * (b.x - boatX) + dyB * dyB
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

        // A tuna is strong enough to tow the boat — that hooks into the sleigh ride, not the gauge.
        if special == nil, hooked == .tuna {
            startSleighRide(.tuna)
            return
        }

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
        let upgradeable = config.predator && special == nil && hooked != .tuna && hooked != .boot
        predatorPending = upgradeable && Double.random(in: 0...1) < predatorChance
        predatorAt = Double.random(in: predatorMinTime...predatorMaxTime)
        phase = .hooking            // brief "On the line!" transition → reeling
        haptics.play(.bite)
    }

    /// Deep water leans toward the big, valuable fish; shallow toward the small ones.
    /// The exact odds come from the level's fish table.
    private func rollFish(deep: Bool) -> FishKind {
        let n = nightLevel
        // The night shift leans toward trophies: a chance to draw on the deep (big-fish) table even on a
        // shallow cast, plus a bias toward the larger end of whichever table.
        let useDeep = deep || (n > 0.15 && Double.random(in: 0...1) < n * 0.25)
        return config.fish.roll(deep: useDeep, Double.random(in: 0...1), bigBias: n * 0.55)
    }

    private func land() {
        if let sp = hookedSpecial { landSpecial(sp); return }
        guard let kind = hooked else { return }

        // A scoring fish extends the streak; an old boot lands but neither builds nor breaks it.
        let scoring = kind.points > 0
        let prevCombo = comboMult
        if scoring { streak += 1; comboMult = min(maxCombo, streak) }
        if kind == .boot {                                   // boots pile up → summon the Boot Beast
            bootsThisTrip += 1
            LocalStore.addBoot()                             // lifetime tally (boat unlocks)
            if bootsThisTrip % bootBeastEvery == 0 { pendingBootBeast = true }
        }
        let perfect = scoring && reelOutTime <= perfectTol      // never (really) left the zone

        let mult = scoreMultiplier * (scoring ? comboMult : 1)  // chest × combo streak
        var pts = kind.points * mult
        if perfect { pts = Int((Double(pts) * perfectBonus).rounded()) }
        if landingViaSleigh { pts = Int((Double(pts) * sleighBonus).rounded()) }   // a hard-won tow pays extra
        landingViaSleigh = false
        award(pts)

        if scoring {
            fishCount += 1
            LocalStore.addFish()                            // lifetime tally (boat unlocks)
            caught[kind, default: 0] += 1
            bestComboReached = max(bestComboReached, comboMult)
            if perfect { levelHadPerfect = true }
        }

        lastCatch = CaughtFish(kind: kind, points: pts)
        lastSpecial = nil
        lastComboMult = scoring ? comboMult : 1
        lastPerfect = perfect
        if scoring { triggerScorePop(pts, mult: comboMult, perfect: perfect) }

        surfaceCaught = true
        surfaceT = 0
        phase = .surfacing           // splash/flash transition → the result card
        if scoring && comboMult > prevCombo && comboMult >= 2 { SoundManager.shared.play(.combo) }   // streak stepped up
        if perfect {
            SoundManager.shared.play(.perfect)            // a clean reel rings out
            haptics.play(.catchBig, sound: false)         // (the perfect chime replaces the generic catch sound)
        } else {
            haptics.play(kind.points >= 90 || comboMult >= 3 ? .catchBig : .catchSmall)
        }
        checkBoatUnlocks()           // a fish/boot lifetime tally may have crossed a boat threshold
        checkObjective()
    }

    private func triggerScorePop(_ value: Int, mult: Int, perfect: Bool) {
        scorePop = value; scorePopMult = mult; scorePopPerfect = perfect; scorePopT = 0
    }

    /// Add to the run score and to the lifetime tally (which drives boat unlocks).
    private func award(_ pts: Int) {
        guard pts != 0 else { return }      // a 0-point boot shouldn't bump the counter
        score += pts
        scoreBumpT = 0                       // kick the scale punch
        LocalStore.addScore(pts)
        checkBoatUnlocks()                   // a score boat may have just crossed its threshold
    }

    /// Reeled a special all the way up: claim the chest/pickaxe — or set off the mine.
    private func landSpecial(_ sp: Special) {
        switch sp {
        case .mine:
            blowUp()
            return
        case .chest:
            doublePointsT = chestDuration
            LocalStore.addChest()                           // lifetime tally (boat unlocks)
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
        checkBoatUnlocks()           // a chest lifetime tally may have crossed a boat threshold
    }

    /// The hooked mine reaches the boat and detonates — game over.
    private func blowUp() {
        phase = .crashing
        crashIsMine = true
        crashProgress = 0
        crashX = boatX; crashY = boatY
        hooked = nil; hookedSpecial = nil
        if !isCampaign {
            isBest = score > 0 && score > LocalStore.best()
            LocalStore.recordBest(score)
        }
        LocalStore.recordRun(score)         // single-run best (any mode) → the golden boat
        shake(9)
        showFlash("MINE!")
        haptics.play(.crash)
    }

    private func lose(_ reason: String) {
        // Losing a real fish on the line breaks the streak. A boot, a bailed mine, and an empty cast
        // (no fish was hooked at all) leave the combo untouched.
        if phase == .reeling && hookedSpecial == nil {
            levelLosses += 1                                        // failed a reel
            if hooked != .boot { streak = 0; comboMult = 1 }       // a lost fish resets the combo
        }
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
        if !isCampaign {
            isBest = score > 0 && score > LocalStore.best()
            LocalStore.recordBest(score)
        }
        LocalStore.recordRun(score)         // single-run best (any mode) → the golden boat
        shake(7)
        haptics.play(.crash)
        // The timer keeps running so the splash can animate; tickCrash flips to .gameOver.
    }

    // MARK: Spawning --------------------------------------------------------

    private func rockGap() -> ClosedRange<Double> {
        guard let base = config.rockSpawn else { return 999...1000 }
        let tight = 0.55 * ramp        // rocks come faster as difficulty ramps
        return max(0.3, base.lowerBound - tight)...max(0.5, base.upperBound - tight)
    }

    private func spawnRock() {
        let roll = Double.random(in: 0...1)
        // Decide what it is (and its size) first, then pick a lane that won't drop it onto an existing
        // vak — so a fish never ends up under a rock, and no vak ever has to be removed (which made them pop).
        let y: Double, r: Double, kind: ObstacleKind
        if roll < 0.035      { y = -0.15; r = 0.052; kind = .boat }         // very rare wandering boat
        else if roll < 0.14  { y = -0.15; r = 0.085; kind = .lighthouse }   // rarer lighthouse skerry
        else                 { y = -0.10; r = Double.random(in: 0.06...0.10); kind = .rock }

        var x = Double.random(in: edge...(1 - edge))
        var tries = 0
        while !rockSpotOpen(x: x, y: y, r: r) && tries < 8 {     // dodge existing vakar (no popping)
            x = Double.random(in: edge...(1 - edge)); tries += 1
        }

        var o = Obstacle(x: x, y: y, r: r, kind: kind)
        if kind == .boat { o.vx = Double.random(in: 0.06...0.10) * (Bool.random() ? 1 : -1) }  // drifts sideways
        rocks.append(o)
    }

    /// The rare wandering boat: drifts slowly sideways, nudging away from rocks, bouncing off the edges.
    private func updateDriftingBoats(_ dt: Double) {
        for i in rocks.indices where rocks[i].kind == .boat {
            var vx = rocks[i].vx
            for j in rocks.indices where rocks[j].kind != .boat {
                let dx = rocks[i].x - rocks[j].x, dy = (rocks[i].y - rocks[j].y) * yFactor
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
        let deep = Bool.random()
        // A vak may sit right next to a rock, but never on one. Hints and rocks scroll in lockstep, so a
        // spot that clears the rocks at spawn stays clear forever — find an open lane, else skip this one.
        for _ in 0..<8 {
            let x = Double.random(in: 0.16...0.84)
            if vakSpotOpen(x: x, y: -0.08, deep: deep) {
                hints.append(Hint(x: x, y: -0.08, deep: deep)); return
            }
        }
    }

    /// A vak's solid core (shadow + glint) radius. The faint outer rings may lap a nearby rock ("near"),
    /// but this small core must not sit on the rock body ("not in") — so vakar can still hug rocks closely.
    private func vakCore(_ deep: Bool) -> Double { deep ? 0.04 : 0.026 }

    /// Open spot for a vak: no rock body overlaps its core at (x, y). A circular test (not a box), so the
    /// exclusion zone is just the rock radius plus the vak's small core — vakar can sit close, not on top.
    private func vakSpotOpen(x: Double, y: Double, deep: Bool) -> Bool {
        let core = vakCore(deep)
        return !rocks.contains { let dx = $0.x - x, dy = ($0.y - y) * yFactor, c = $0.r + core; return dx * dx + dy * dy < c * c }
    }

    /// Open spot for a rock: it won't cover the core of an existing vak (so we never have to delete one).
    private func rockSpotOpen(x: Double, y: Double, r: Double) -> Bool {
        return !hints.contains { let dx = $0.x - x, dy = ($0.y - y) * yFactor, c = r + vakCore($0.deep); return dx * dx + dy * dy < c * c }
    }

    /// Drop any scripted placements whose distance the level has now reached — at their exact x.
    private func processScript() {
        while scriptIndex < sortedScript.count, sortedScript[scriptIndex].at <= worldDist {
            let s = sortedScript[scriptIndex]
            let x = min(0.95, max(0.05, s.x))
            switch s.item {
            case .rock(let r):        rocks.append(Obstacle(x: x, y: -0.1, r: r, kind: .rock))
            case .lighthouse:         rocks.append(Obstacle(x: x, y: -0.15, r: 0.085, kind: .lighthouse))
            case .driftBoat(let vx):  rocks.append(Obstacle(x: x, y: -0.15, r: 0.052, kind: .boat, vx: vx))
            case .ripple(let deep):   hints.append(Hint(x: x, y: -0.08, deep: deep))
            }
            scriptIndex += 1
        }
    }

    // MARK: Helpers ---------------------------------------------------------

    private func collides(_ r: Obstacle) -> Bool {
        // Rocks are drawn with a width-based radius, so the hit box must measure vertical distance in the
        // same units. On the watch (near-square) we keep the original hand-tuned feel (factor 1). On a
        // taller screen (iPhone) we use the real aspect, making the hit box pixel-accurate — you crash on
        // actual contact, not with a gap above/below. The watch is left exactly as before.
        // In landscape the art zooms out (GameArt sizes by width × renderAspect/designAspect), so the hit
        // box shrinks by the same factor to keep matching the drawn rocks/hull. 1 elsewhere (inert).
        let f = renderAspect < 1 ? renderAspect / designAspect : 1
        let dx = (r.x - boatX), dy = (r.y - boatY) * yFactor
        let rx = (r.r + boatHitRx) * f, ry = (r.r + boatHitR) * f   // elliptical: narrower across the hull's sides
        let nx = dx / rx, ny = dy / ry
        return nx * nx + ny * ny < 1
    }

    private func showFlash(_ text: String, gold: Bool = false, duration: Double = 1.1) {
        flash = text; flashGold = gold; flashTimer = duration
    }
}
