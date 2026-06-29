//
//  MusicManager.swift
//  Wristfish — looping background music. Three short, seamless beds (menu, gameplay, and a darker
//  "boss" bed for monster fights) that crossfade on transitions and sit well under the SFX mix. Plays
//  through the same .ambient session as SoundManager (so it mixes politely and is silenced by the
//  Ring/Silent switch), is gated by the Settings music toggle, and — being a polite background bed —
//  steps aside for the user's own audio (Apple Music / Spotify / a podcast) while the SFX keep playing.
//  Cross-platform (watchOS + future iOS).
//
//  Transitions use an equal-power crossfade (sin/cos curves on a timer) rather than AVAudioPlayer's
//  built-in linear fade, so there is no volume dip in the middle and the swell feels smooth — the boss
//  transition uses a longer fade so the tension eases in/out rather than snapping.
//
//  Design notes (grounded in Apple's game-audio guidance):
//   • .ambient, never .playback — respects the silent switch and mixes with other apps.
//   • Music pauses when the game backgrounds / the wrist drops (driven by GameView's scenePhase).
//   • When the user is already playing their own audio we suppress the music (not duck it), keep SFX.
//

import AVFoundation

final class MusicManager {
    static let shared = MusicManager()

    enum Track: String { case menu, gameplay, boss }   // boss = the darker, tense bed for monster fights

    /// Base level — kept well under the SFX mix so music never competes with gameplay cues.
    /// Per-track level — kept well under the SFX mix. The in-game beds sit a touch lower than the menu
    /// so gameplay cues read clearly over them; boss stays a hair above gameplay (the fight is present).
    private func baseVolume(_ t: Track) -> Float {
        switch t {
        case .menu:     return 0.40
        case .gameplay: return 0.30
        case .boss:     return 0.34
        }
    }
    private let normalFade: TimeInterval = 0.9         // menu ↔ gameplay
    private let bossFade: TimeInterval = 1.6           // into/out of a monster fight — a slower swell

    private var players: [Track: AVAudioPlayer] = [:]
    private var current: Track?              // the track we *want* playing (survives pause/suppress)
    private var prepared = false
    private var suppressed = false           // the user's own audio is playing → stay silent
    private init() {}

    // MARK: Equal-power crossfade engine -----------------------------------
    private struct Ramp {
        let player: AVAudioPlayer
        let from: Float, to: Float
        var elapsed: TimeInterval
        let duration: TimeInterval
        let rising: Bool
        let pauseAtEnd: Bool
    }
    private var ramps: [Ramp] = []
    private var fadeTimer: Timer?
    private let tick: TimeInterval = 1.0 / 30.0

    /// Ramp one player to a target volume along an equal-power curve; optionally pause it when silent.
    private func ramp(_ player: AVAudioPlayer, to target: Float, duration: TimeInterval, pauseAtEnd: Bool) {
        ramps.removeAll { $0.player === player }       // replace any in-flight ramp for this player
        let from = player.volume
        ramps.append(Ramp(player: player, from: from, to: target, elapsed: 0,
                          duration: max(0.05, duration), rising: target >= from, pauseAtEnd: pauseAtEnd))
        guard fadeTimer == nil else { return }
        let t = Timer(timeInterval: tick, repeats: true) { [weak self] _ in self?.stepRamps() }
        RunLoop.main.add(t, forMode: .common)          // keeps fading even during UI interaction
        fadeTimer = t
    }

    private func stepRamps() {
        guard !ramps.isEmpty else { fadeTimer?.invalidate(); fadeTimer = nil; return }
        for i in ramps.indices { ramps[i].elapsed += tick }
        for r in ramps {
            let p = min(1, r.elapsed / r.duration)
            // equal-power: fade-in follows sin, fade-out follows cos — constant combined power, no dip.
            let v: Float = r.rising
                ? r.from + (r.to - r.from) * Float(sin(p * .pi / 2))
                : r.to + (r.from - r.to) * Float(cos(p * .pi / 2))
            r.player.volume = v
            if p >= 1 {
                r.player.volume = r.to
                if r.pauseAtEnd { r.player.pause() }
            }
        }
        ramps.removeAll { $0.elapsed >= $0.duration }
    }

    /// Stop all fading immediately (used when backgrounding — no audible transition needed).
    private func cancelRamps() { ramps.removeAll(); fadeTimer?.invalidate(); fadeTimer = nil }

    // MARK: Setup ----------------------------------------------------------
    /// Preload all beds once and start listening for the user's audio starting/stopping.
    private func prepare() {
        guard !prepared else { return }
        prepared = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        for t in [Track.menu, .gameplay, .boss] {
            guard let url = Bundle.main.url(forResource: t.rawValue, withExtension: "wav"),
                  let p = try? AVAudioPlayer(contentsOf: url) else { continue }
            p.numberOfLoops = -1            // loop forever
            p.volume = 0                    // we always fade in from silence
            p.prepareToPlay()
            players[t] = p
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(secondaryAudioChanged(_:)),
            name: AVAudioSession.silenceSecondaryAudioHintNotification, object: nil)
    }

    /// A boss transition (into or out of a fight) gets the longer, more dramatic swell.
    private func fadeFor(_ track: Track) -> TimeInterval {
        (track == .boss || current == .boss) ? bossFade : normalFade
    }

    // MARK: Public API -----------------------------------------------------
    /// Start, or crossfade to, a track. A no-op if it's already the active track.
    func play(_ track: Track) {
        guard LocalStore.musicEnabled else { return }
        prepare()
        guard current != track else { return }
        let dur = fadeFor(track)
        if let cur = current, let p = players[cur] { ramp(p, to: 0, duration: dur, pauseAtEnd: true) }
        current = track
        suppressed = AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint
        guard !suppressed, let p = players[track] else { return }    // their audio wins — stay silent
        try? AVAudioSession.sharedInstance().setActive(true)
        if !p.isPlaying { p.currentTime = 0; p.volume = 0; p.play() }
        ramp(p, to: baseVolume(track), duration: dur, pauseAtEnd: false)
    }

    /// Fade out and forget the current track (used when leaving all music behind).
    func stop() {
        for p in players.values where p.isPlaying { ramp(p, to: 0, duration: normalFade, pauseAtEnd: true) }
        current = nil
    }

    /// scenePhase background — silence music at once but remember the track for resume().
    func pause() {
        cancelRamps()
        for p in players.values where p.isPlaying { p.pause() }
    }

    /// scenePhase foreground — bring the remembered track back if music is on and not suppressed.
    func resume() {
        guard LocalStore.musicEnabled, !suppressed, let t = current, let p = players[t], !p.isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        p.volume = 0
        p.play()
        ramp(p, to: baseVolume(t), duration: normalFade, pauseAtEnd: false)
    }

    /// The Settings toggle. On → resume the current/menu bed; off → stop everything.
    func setEnabled(_ on: Bool) {
        if on { play(current ?? .menu) } else { stop() }
    }

    /// The user started or stopped their own audio: step aside / come back politely.
    @objc private func secondaryAudioChanged(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: raw) else { return }
        switch type {
        case .begin:                 // their audio started → our music gets out of the way (SFX stay)
            suppressed = true
            pause()
        case .end:                   // their audio stopped → bring our bed back
            suppressed = false
            resume()
        @unknown default: break
        }
    }
}
