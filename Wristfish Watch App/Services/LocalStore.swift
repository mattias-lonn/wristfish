//
//  LocalStore.swift
//  Wristfish — tiny UserDefaults wrapper for the best score and settings.
//

import Foundation

enum LocalStore {
    private static let bestKey = "wf_fish_best"
    private static let hapticsKey = "wf_fish_haptics"
    private static let starsKey = "wf_fish_stars"

    static func best() -> Int { UserDefaults.standard.integer(forKey: bestKey) }
    static func recordBest(_ score: Int) {
        if score > best() { UserDefaults.standard.set(score, forKey: bestKey) }
    }

    // MARK: Campaign progress (level id → best stars, 0…3) -----------------

    private static func starsMap() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: starsKey) as? [String: Int] ?? [:]
    }

    /// Best stars earned on a level (0 = not yet cleared).
    static func stars(level id: Int) -> Int { starsMap()[String(id)] ?? 0 }

    /// Keep the best star count seen for a level.
    static func recordStars(level id: Int, stars: Int) {
        var map = starsMap()
        let key = String(id)
        if stars > (map[key] ?? 0) {
            map[key] = stars
            UserDefaults.standard.set(map, forKey: starsKey)
        }
    }

    /// Level 1 is always open; later levels unlock once the previous one is cleared.
    /// In dev builds everything is unlocked so any level can be tested.
    static func isUnlocked(level id: Int) -> Bool {
        #if DEBUG
        return true
        #else
        return id <= 1 || stars(level: id - 1) > 0
        #endif
    }

    /// Total stars across the campaign (for the menu).
    static func totalStars() -> Int { starsMap().values.reduce(0, +) }

    /// Defaults to ON when never set.
    static var hapticsEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: hapticsKey) == nil
                ? true : UserDefaults.standard.bool(forKey: hapticsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
    }
}
