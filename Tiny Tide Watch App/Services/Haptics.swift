//
//  Haptics.swift
//  Tiny Tide — one place for every haptic cue. Honors the Settings toggle. The cue taxonomy is shared;
//  only the per-platform playback differs (watchOS uses WatchKit, iOS uses UIKit feedback generators).
//

#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

enum Haptic { case cast, bite, tug, reel, catchSmall, catchBig, miss, crash }

extension Haptic {
    /// The matching sound cue (same taxonomy, so one feedback call drives both).
    var sound: GameSound {
        switch self {
        case .cast:       return .cast
        case .bite:       return .bite
        case .tug:        return .tug
        case .reel:       return .reel
        case .catchSmall: return .catchSmall
        case .catchBig:   return .catchBig
        case .miss:       return .miss
        case .crash:      return .crash
        }
    }
}

struct HapticsManager {
    static let shared = HapticsManager()

    /// Play a cue. `sound: false` fires only the haptic — used when a distinct sound is played
    /// separately (e.g. a perfect chime or the unlock fanfare) so the default cue doesn't double up.
    func play(_ h: Haptic, sound: Bool = true) {
        if sound { SoundManager.shared.play(h.sound) }   // sound + haptic gated independently in Settings
        guard LocalStore.hapticsEnabled else { return }

        #if os(watchOS)
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
        #elseif os(iOS)
        switch h {
        case .cast:       UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .bite:       UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .tug:        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .reel:       UISelectionFeedbackGenerator().selectionChanged()
        case .catchSmall: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .catchBig:   UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .miss:       UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .crash:      UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        #endif
    }
}
