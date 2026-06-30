//
//  SoundManager.swift
//  Wristfish — tiny SFX layer. One short synthesized cue per game event, mirroring the haptic
//  taxonomy so feedback stays in sync. Plays through an .ambient session (respects the silent switch)
//  and is gated by the Settings sound toggle. Cross-platform (watchOS + a future iOS target).
//

import AVFoundation

/// Game-event sound cues. The first eight are 1:1 with `Haptic` (so one feedback call drives both);
/// the rest are distinct cues for special moments, played directly via `SoundManager`.
enum GameSound: String, CaseIterable {
    case cast, bite, tug, reel, catchSmall, catchBig, miss, crash
    case perfect, combo, unlock, kraken, bootBeast, plop, gull, leapSplash

    /// A calm, balanced mix. Every .wav is normalized to the same peak, so this map alone sets the
    /// relative loudness: frequent/ambient cues (cast, reel) sit far under the one-shot reward cues.
    var volume: Float {
        switch self {
        case .cast:        return 0.14   // fires on every aim — kept very subtle
        case .reel:        return 0.16   // rapid ticks while reeling
        case .tug:         return 0.26
        case .miss:        return 0.28
        case .combo:       return 0.32
        case .bite:        return 0.34
        case .plop:        return 0.37
        case .gull:        return 0.05   // ambient flyby cry (kept very quiet)
        case .leapSplash:  return 0.014  // a leaping fish dropping back in — barely-there, a whisper of water
        case .bootBeast:   return 0.40
        case .catchSmall:  return 0.43
        case .perfect:     return 0.48
        case .catchBig:    return 0.57
        case .unlock:      return 0.60
        case .crash:       return 0.66
        case .kraken:      return 0.71
        }
    }
}

final class SoundManager {
    static let shared = SoundManager()
    private var players: [GameSound: AVAudioPlayer] = [:]
    private var prepared = false
    private init() {}

    /// Preload every cue once (cheap, ~80 KB total) and set a polite audio session.
    private func prepare() {
        guard !prepared else { return }
        prepared = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        for s in GameSound.allCases {
            guard let url = Bundle.main.url(forResource: s.rawValue, withExtension: "wav"),
                  let p = try? AVAudioPlayer(contentsOf: url) else { continue }
            p.volume = s.volume
            p.prepareToPlay()
            players[s] = p
        }
    }

    func play(_ s: GameSound) {
        guard LocalStore.soundEnabled else { return }
        prepare()
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let p = players[s] else { return }
        p.currentTime = 0
        p.play()
    }
}
