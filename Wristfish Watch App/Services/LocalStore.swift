//
//  LocalStore.swift
//  Wristfish — tiny UserDefaults wrapper for the best score and settings.
//

import Foundation

enum LocalStore {
    private static let bestKey = "wf_fish_best"
    private static let hapticsKey = "wf_fish_haptics"

    static func best() -> Int { UserDefaults.standard.integer(forKey: bestKey) }
    static func recordBest(_ score: Int) {
        if score > best() { UserDefaults.standard.set(score, forKey: bestKey) }
    }

    /// Defaults to ON when never set.
    static var hapticsEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: hapticsKey) == nil
                ? true : UserDefaults.standard.bool(forKey: hapticsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
    }
}
