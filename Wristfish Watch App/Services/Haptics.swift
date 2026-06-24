//
//  Haptics.swift
//  Wristfish — one place for every haptic cue. Honors the Settings toggle.
//

import WatchKit

enum Haptic { case cast, bite, tug, reel, catchSmall, catchBig, miss, crash }

struct HapticsManager {
    static let shared = HapticsManager()

    func play(_ h: Haptic) {
        guard LocalStore.hapticsEnabled else { return }
        let device = WKInterfaceDevice.current()
        switch h {
        case .cast:       device.play(.start)
        case .bite:       device.play(.notification)
        case .tug:        device.play(.directionUp)
        case .reel:       device.play(.click)
        case .catchSmall: device.play(.success)
        case .catchBig:   device.play(.success)
        case .miss:       device.play(.retry)
        case .crash:      device.play(.failure)
        }
    }
}
