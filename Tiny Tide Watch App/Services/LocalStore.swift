//
//  LocalStore.swift
//  Tiny Tide — local progress (UserDefaults) mirrored to iCloud key-value storage so a player keeps
//  their best score, campaign stars, lifetime stats and chosen boat across reinstalls, a new Apple
//  Watch, and (later) an iPhone version on the same Apple ID.
//
//  Design:
//   • UserDefaults is the source of truth — every getter reads it, so the game works fully offline
//     and never blocks on the network (with no iCloud account, KVS just acts as a local cache).
//   • Every write is mirrored up to NSUbiquitousKeyValueStore.
//   • Incoming iCloud changes are merged back: growing counters and per-level stars take the MAX
//     (so nothing is ever lost when two devices played apart), settings adopt the latest value.
//   • Pure Foundation — the same store works unchanged on a future iOS target (which must use the
//     same `com.apple.developer.ubiquity-kvstore-identifier` to share this data).
//

import Foundation

enum LocalStore {
    private static let defaults = UserDefaults.standard
    private static let kvs = NSUbiquitousKeyValueStore.default

    // MARK: Keys ------------------------------------------------------------
    private static let bestKey = "wf_fish_best"
    private static let hapticsKey = "wf_fish_haptics"
    private static let soundKey = "wf_sound"
    private static let musicKey = "wf_music"
    private static let starsKey = "wf_fish_stars"
    private static let totalFishKey = "wf_total_fish"
    private static let totalScoreKey = "wf_total_score"
    private static let totalBootsKey = "wf_total_boots"
    private static let totalChestsKey = "wf_total_chests"
    private static let totalRocksKey = "wf_total_rocks"
    private static let bestRunKey = "wf_best_run"            // highest score in a single run (any mode)
    private static let boatKey = "wf_boat"
    private static let celebratedKey = "wf_celebrated_boats" // boats whose unlock cameo has already played (local)

    /// Counters that only ever grow — reconciled across devices by taking the larger value.
    private static let maxIntKeys = [bestKey, totalFishKey, totalScoreKey, totalBootsKey, totalChestsKey,
                                     totalRocksKey, bestRunKey]

    /// Posted on the main thread after an iCloud change has been merged in, so views can refresh.
    static let didChange = Notification.Name("LocalStoreDidChange")

    // MARK: iCloud sync lifecycle ------------------------------------------
    private static var started = false
    private static var observer: NSObjectProtocol?

    /// Call once at launch. Starts mirroring local progress to iCloud and merging changes back.
    /// Safe to call with no iCloud account — it simply keeps everything local.
    static func startCloudSync() {
        guard !started else { return }
        started = true
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs, queue: .main) { _ in mergeFromCloud() }
        kvs.synchronize()        // pull whatever iCloud already cached for this account
        mergeFromCloud()         // reconcile both ways now (first launch, warm cache, or a fresh restore)
    }

    /// Two-way reconcile. iCloud → local: counters and per-level stars move to their max, settings
    /// adopt iCloud's value. local → iCloud: push the merged maxima back so every device converges.
    private static func mergeFromCloud() {
        var pushed = false

        // Growing counters: both sides move to the larger value.
        for key in maxIntKeys {
            let local = defaults.integer(forKey: key)
            let cloud = Int(kvs.longLong(forKey: key))
            let merged = max(local, cloud)
            if merged != local { defaults.set(merged, forKey: key) }
            if merged != cloud { kvs.set(Int64(merged), forKey: key); pushed = true }
        }

        // Per-level stars: union the levels, keep the best star count on each.
        let cloudStars = (kvs.dictionary(forKey: starsKey) as? [String: Int]) ?? [:]
        var stars = starsMap()
        var starsChanged = false, starsNeedPush = false
        for level in Set(stars.keys).union(cloudStars.keys) {
            let merged = max(stars[level] ?? 0, cloudStars[level] ?? 0)
            if stars[level] != merged { stars[level] = merged; starsChanged = true }
            if cloudStars[level] != merged { starsNeedPush = true }
        }
        if starsChanged { defaults.set(stars, forKey: starsKey) }
        if starsNeedPush { kvs.set(stars, forKey: starsKey); pushed = true }

        // Settings (boat, haptics): adopt iCloud's value when it has one — the latest device wins.
        if kvs.object(forKey: boatKey) != nil {
            let cloudBoat = Int(kvs.longLong(forKey: boatKey))
            if defaults.integer(forKey: boatKey) != cloudBoat { defaults.set(cloudBoat, forKey: boatKey) }
        }
        if kvs.object(forKey: hapticsKey) != nil {
            let cloudHaptics = kvs.bool(forKey: hapticsKey)
            if defaults.object(forKey: hapticsKey) == nil || defaults.bool(forKey: hapticsKey) != cloudHaptics {
                defaults.set(cloudHaptics, forKey: hapticsKey)
            }
        }
        if kvs.object(forKey: soundKey) != nil {
            let cloudSound = kvs.bool(forKey: soundKey)
            if defaults.object(forKey: soundKey) == nil || defaults.bool(forKey: soundKey) != cloudSound {
                defaults.set(cloudSound, forKey: soundKey)
            }
        }
        if kvs.object(forKey: musicKey) != nil {
            let cloudMusic = kvs.bool(forKey: musicKey)
            if defaults.object(forKey: musicKey) == nil || defaults.bool(forKey: musicKey) != cloudMusic {
                defaults.set(cloudMusic, forKey: musicKey)
            }
        }

        if pushed { kvs.synchronize() }
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Mirror one integer up to iCloud.
    private static func mirror(_ value: Int, _ key: String) {
        kvs.set(Int64(value), forKey: key)
        kvs.synchronize()
    }

    // MARK: Best score -----------------------------------------------------
    static func best() -> Int { defaults.integer(forKey: bestKey) }
    static func recordBest(_ score: Int) {
        if score > best() { defaults.set(score, forKey: bestKey); mirror(score, bestKey) }
    }

    // MARK: Campaign progress (level id → best stars, 0…3) -----------------
    private static func starsMap() -> [String: Int] {
        defaults.dictionary(forKey: starsKey) as? [String: Int] ?? [:]
    }

    /// Best stars earned on a level (0 = not yet cleared).
    static func stars(level id: Int) -> Int { starsMap()[String(id)] ?? 0 }

    /// Keep the best star count seen for a level.
    static func recordStars(level id: Int, stars: Int) {
        var map = starsMap()
        let key = String(id)
        if stars > (map[key] ?? 0) {
            map[key] = stars
            defaults.set(map, forKey: starsKey)
            kvs.set(map, forKey: starsKey); kvs.synchronize()
        }
    }

    /// Level 1 is always open; later levels unlock once the previous one is cleared. Gated for real
    /// (no dev override), so the lock experience matches what players see in Debug and Release alike.
    static func isUnlocked(level id: Int) -> Bool {
        id <= 1 || stars(level: id - 1) > 0
    }

    /// Total stars across the campaign (for the menu).
    static func totalStars() -> Int { starsMap().values.reduce(0, +) }

    // MARK: Lifetime stats + boat selection (cosmetic unlocks) -------------
    static func totalFish() -> Int { defaults.integer(forKey: totalFishKey) }
    static func totalScore() -> Int { defaults.integer(forKey: totalScoreKey) }
    static func totalBoots() -> Int { defaults.integer(forKey: totalBootsKey) }
    static func totalChests() -> Int { defaults.integer(forKey: totalChestsKey) }
    static func totalRocks() -> Int { defaults.integer(forKey: totalRocksKey) }
    /// Highest score reached in a single run (any mode) — drives the golden boat.
    static func bestRun() -> Int { defaults.integer(forKey: bestRunKey) }

    static func addFish(_ n: Int = 1)  { let v = totalFish() + n;   defaults.set(v, forKey: totalFishKey);   mirror(v, totalFishKey) }
    static func addBoot(_ n: Int = 1)  { let v = totalBoots() + n;  defaults.set(v, forKey: totalBootsKey);  mirror(v, totalBootsKey) }
    static func addChest(_ n: Int = 1) { let v = totalChests() + n; defaults.set(v, forKey: totalChestsKey); mirror(v, totalChestsKey) }
    static func addRock(_ n: Int = 1)  { let v = totalRocks() + n;  defaults.set(v, forKey: totalRocksKey);  mirror(v, totalRocksKey) }
    static func addScore(_ n: Int) {
        guard n > 0 else { return }
        let v = totalScore() + n; defaults.set(v, forKey: totalScoreKey); mirror(v, totalScoreKey)
    }
    /// Record a finished run's score; keeps the all-time single-run best.
    static func recordRun(_ score: Int) {
        if score > bestRun() { defaults.set(score, forKey: bestRunKey); mirror(score, bestRunKey) }
    }

    // MARK: Boat-unlock cameo bookkeeping ----------------------------------
    /// Boats whose unlock cameo has already played. Lazily seeded with everything currently unlocked,
    /// so existing progress never re-celebrates — only genuinely new unlocks get a lap. (Local-only.)
    private static func celebratedSet() -> Set<Int> {
        if let arr = defaults.array(forKey: celebratedKey) as? [Int] { return Set(arr) }
        let initial = Set(BoatModel.all.filter { $0.isUnlocked }.map { $0.id })
        defaults.set(Array(initial), forKey: celebratedKey)
        return initial
    }
    static func isCelebrated(_ id: Int) -> Bool { celebratedSet().contains(id) }
    static func markCelebrated(_ id: Int) {
        var s = celebratedSet(); s.insert(id); defaults.set(Array(s), forKey: celebratedKey)
    }

    /// The chosen boat id (defaults to 0 = the starter Skiff). Clamped to an unlocked boat so the
    /// menu highlight and the gameplay boat always agree even if a stored boat is no longer available.
    static func selectedBoat() -> Int {
        let id = defaults.integer(forKey: boatKey)
        return BoatModel.all.first(where: { $0.id == id })?.isUnlocked == true ? id : 0
    }
    static func setSelectedBoat(_ id: Int) { defaults.set(id, forKey: boatKey); mirror(id, boatKey) }

    /// Defaults to ON when never set.
    static var hapticsEnabled: Bool {
        get {
            defaults.object(forKey: hapticsKey) == nil
                ? true : defaults.bool(forKey: hapticsKey)
        }
        set {
            defaults.set(newValue, forKey: hapticsKey)
            kvs.set(newValue, forKey: hapticsKey); kvs.synchronize()
        }
    }

    /// Sound effects. Defaults to ON when never set.
    static var soundEnabled: Bool {
        get {
            defaults.object(forKey: soundKey) == nil
                ? true : defaults.bool(forKey: soundKey)
        }
        set {
            defaults.set(newValue, forKey: soundKey)
            kvs.set(newValue, forKey: soundKey); kvs.synchronize()
        }
    }

    /// Background music. Defaults to OFF — on the watch, silence-in-public is the norm and the music is
    /// a value-add for players with AirPods; SFX + haptics carry the game on their own.
    static var musicEnabled: Bool {
        get {
            defaults.object(forKey: musicKey) == nil
                ? false : defaults.bool(forKey: musicKey)
        }
        set {
            defaults.set(newValue, forKey: musicKey)
            kvs.set(newValue, forKey: musicKey); kvs.synchronize()
        }
    }
}
