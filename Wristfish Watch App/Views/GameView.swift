//
//  GameView.swift
//  Wristfish — the gameplay screen. Hosts the Canvas, routes Crown + taps to the model,
//  and lays the HUD / result cards on top.
//

import SwiftUI

struct GameView: View {
    @StateObject private var model = GameModel()
    let onExit: () -> Void

    @State private var config: LevelConfig
    @Environment(\.scenePhase) private var scenePhase

    // Staged entrance for the end-of-level card: frosted glass fades in, stars pop one-by-one, then the rest.
    @State private var cardIn = false
    @State private var starsShown = 0
    @State private var winDetailsIn = false
    @State private var comboScale = 1.0   // one-shot punch when the combo multiplier steps up

    init(config: LevelConfig = .freeplay, onExit: @escaping () -> Void) {
        self.onExit = onExit
        _config = State(initialValue: config)
    }

    /// The next campaign level after this one, if any.
    private var nextLevel: LevelConfig? {
        guard model.isCampaign else { return nil }
        return LevelConfig.campaign.first { $0.id == config.id + 1 }
    }

    private func startLevel(_ c: LevelConfig) { config = c; model.start(c) }

    /// Reveal the end card in stages: glass fades in → (on a win) stars pop one-by-one with a haptic → rest.
    private func revealEndCard() {
        cardIn = false; starsShown = 0; winDetailsIn = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { cardIn = true }
        guard model.isCampaign && model.levelWon else {              // fail / freeplay: just fade the card in
            withAnimation(.easeOut(duration: 0.3).delay(0.12)) { winDetailsIn = true }
            return
        }
        let stars = max(1, model.levelStars)
        for i in 0..<stars {                                        // each earned star springs in with a tick
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.34) {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.5)) { starsShown = i + 1 }
                HapticsManager.shared.play(.reel)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(stars) * 0.34 + 0.05) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { winDetailsIn = true }
        }
    }

    /// Whether the level-goal banner should show (during active play, not on the end card).
    private var showObjective: Bool {
        switch model.phase {
        case .boating, .casting, .reeling, .hooking, .surfacing, .landed, .sleighRide: return true
        default: return false
        }
    }

    var body: some View {
        ZStack {
            // World — also the tap surface (cast on tap / double-tap).
            GameCanvas(model: model)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.tap() }

            if model.phase == .crashing {
                (model.crashIsMine ? Color(red: 1, green: 0.72, blue: 0.36) : .white)
                    .opacity((1 - model.crashProgress) * (model.crashIsMine ? 0.7 : 0.45))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            if model.phase == .hooking {
                Color.white.opacity(max(0, 1 - model.hookProgress * 1.5))
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                Text("ON THE LINE!")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(Sea.gold)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                    .scaleEffect(0.7 + model.hookProgress * 0.5)
                    .opacity(1 - model.hookProgress)
                    .allowsHitTesting(false)
            }
            if model.phase == .surfacing {
                Color.white.opacity((1 - model.surfaceProgress) * 0.5)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                if model.surfaceCaught {
                    Text(surfaceTitle)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(Sea.gold)
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                        .scaleEffect(0.7 + model.surfaceProgress * 0.5)
                        .opacity(1 - model.surfaceProgress)
                        .allowsHitTesting(false)
                }
            }
            hud
            if model.scorePopActive && model.phase != .landed && model.phase != .gameOver { scorePopView }
            if model.phase == .landed   { landedCard }
            if model.phase == .gameOver {
                // A full-bleed frosted overlay — the glass runs edge to edge (no card border).
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .opacity(cardIn ? 1 : 0)
                    .allowsHitTesting(false)
                Rectangle()
                    .fill(Sea.deep.opacity(0.22))           // gentle darken for text contrast
                    .ignoresSafeArea()
                    .opacity(cardIn ? 1 : 0)
                    .allowsHitTesting(false)
                gameOverCard
                    .padding(.horizontal, 22)
                    .scaleEffect(cardIn ? 1 : 0.92)
                    .opacity(cardIn ? 1 : 0)
            }
        }
        .playerInput(model)                       // platform input → model.crown(delta:)/tap() (watch: Crown, iOS: drag)
        .onChange(of: model.phase) { _, new in
            if new == .gameOver { revealEndCard() }
            else { cardIn = false; starsShown = 0; winDetailsIn = false }
            switch new {                                     // monster fights get the tense "boss" bed
            case .kraken, .bootBeast, .sleighRide: MusicManager.shared.play(.boss)
            case .boating, .casting:               MusicManager.shared.play(.gameplay)
            default: break                                   // .landed/.gameOver keep whatever's playing
            }
        }
        .onChange(of: model.comboMult) { old, new in
            if new > old && new >= 2 {                       // streak stepped up → punch the chip
                comboScale = 1.35
                withAnimation(.spring(response: 0.32, dampingFraction: 0.45)) { comboScale = 1.0 }
            }
        }
        .onChange(of: scenePhase) { _, phase in              // never run the loop (or music) in the background
            if phase == .active { model.resume(); MusicManager.shared.resume() }
            else { model.pause(); MusicManager.shared.pause() }
        }
        .onAppear { model.start(config) }
        .onDisappear { model.stop() }
    }

    // MARK: HUD -------------------------------------------------------------

    private var hud: some View {
        VStack {
            HStack {
                Text("\(model.hudScore)")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Sea.gold)
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                    .scaleEffect(model.scoreBumpScale, anchor: .leading)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)                      // sits level with the watch time

            if model.isCampaign && showObjective {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(model.objectiveText)
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                        Spacer()
                    }
                    meter(model.objectiveProgress, Sea.teal, eased: true)
                }
                .padding(.horizontal, 14).padding(.top, 1)
            }

            if model.doublePoints || model.rockBreak || model.comboActive {
                HStack(spacing: 6) {
                    if model.comboActive {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill").font(.system(size: 10, weight: .bold))
                            Text("\(model.comboMult)×").font(.system(size: 12, weight: .black, design: .rounded))
                        }
                        .foregroundStyle(Sea.coral)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.black.opacity(0.5), in: Capsule())
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                        .scaleEffect(comboScale)
                    }
                    if model.doublePoints {
                        powerChip(systemName: nil, text: "2×", time: model.doublePointsLeft, color: Sea.gold)
                    }
                    if model.rockBreak {
                        powerChip(systemName: "hammer.fill", text: nil, time: model.rockBreakLeft, color: Sea.teal)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
            }

            if !model.flash.isEmpty && model.phase != .kraken && model.phase != .bootBeast {   // don't cover the monster
                Text(model.flash)
                    .font(.caption.bold())
                    .foregroundStyle(model.flashGold ? Sea.gold : Sea.coral)   // reward = gold, else coral
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 2)
            }

            Spacer()
            bottomBar
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    @ViewBuilder private var bottomBar: some View {
        switch model.phase {
        case .reeling:
            VStack(spacing: 5) {
                if model.hookedSpecial == .mine {
                    pill("Danger!", .red)             // a mine — don't reel this one in
                    meter(model.reelProgress, .red)
                } else {
                    pill(model.markerInZone ? "Reeling in!" : "Keep it in!",
                         model.markerInZone ? Sea.teal : Sea.coral)
                    meter(model.reelProgress, Sea.gold)   // catch progress
                }
            }
            .padding(.horizontal, 14).padding(.bottom, 6)

        case .casting:
            VStack(spacing: 5) {
                pill(model.castLocked ? "Tap!" : "Tap to drop",
                     model.castLocked ? Sea.gold : Sea.teal)
                meter(model.castReachFraction, model.castLocked ? Sea.gold : Sea.blue)
            }
            .padding(.horizontal, 14).padding(.bottom, 6)

        case .sleighRide:
            VStack(spacing: 4) {
                pill(model.sleighStrain > 0.6 ? "Ease off!" : "Stay on its tail!",
                     model.sleighStrain > 0.6 ? .red : Sea.teal)
                meter(model.sleighCatchProgress, Sea.gold, eased: true)                      // fish tiring
                meter(model.sleighStrain, model.sleighStrain > 0.6 ? .red : Sea.coral)       // line strain
            }
            .padding(.horizontal, 14).padding(.bottom, 6)

        case .kraken:
            VStack(spacing: 4) {
                if model.krakenProgress <= 0 {
                    pill("Brace yourself…", Sea.coral)               // a hint while it rises
                } else {
                    if model.krakenJustStarted { pill("Tap to harpoon!", Sea.teal) }
                    meter(model.krakenDamage, Sea.gold, eased: true) // drive-it-off progress
                }
            }
            .padding(.horizontal, 28).padding(.bottom, 5)

        case .bootBeast:
            if model.bootBeastRising {
                pill("The Boot Beast!", Sea.coral).padding(.bottom, 6)   // names the beast while it rises
            } else {
                meter(model.bootBeastProgress, Sea.gold, eased: true)    // slim bar — clear of the dodge zone
                    .padding(.horizontal, 30).padding(.bottom, 5)
            }

        case .boating:
            if model.targetAhead {
                pill("Tap to cast", Sea.gold).padding(.bottom, 6)
            } else if model.showSteerHint {
                pill("Crown to steer", .white).padding(.bottom, 6)
            }

        default:
            EmptyView()
        }
    }

    /// The "+points" that pops up and floats away after a catch.
    private var scorePopView: some View {
        let prog = model.scorePopProgress
        let fadeIn = min(1, prog / 0.15)
        let fadeOut = prog < 0.15 ? 1 : 1 - (prog - 0.15) / 0.85
        return VStack(spacing: 1) {
            if model.scorePopPerfect {
                Text("PERFECT")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(Sea.teal)
            }
            Text("+\(model.scorePop)")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Sea.gold)
            if model.scorePopMult >= 2 {
                Text("\(model.scorePopMult)× COMBO")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Sea.coral)
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        .scaleEffect(0.7 + min(1, prog * 3) * 0.4)
        .offset(y: -36 - prog * 52)
        .opacity(fadeIn * fadeOut)
        .allowsHitTesting(false)
    }

    /// Title over the splash as something surfaces (fish vs special).
    private var surfaceTitle: String {
        switch model.lastSpecial {
        case .chest:   return "TREASURE!"
        case .pickaxe: return "PICKAXE!"
        default:       return "CATCH!"
        }
    }

    /// A small active-power-up chip (icon/text + seconds left).
    private func powerChip(systemName: String?, text: String?, time: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            if let systemName { Image(systemName: systemName).font(.system(size: 10, weight: .bold)) }
            if let text { Text(text).font(.system(size: 12, weight: .black, design: .rounded)) }
            Text("\(time)s").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(.black.opacity(0.5), in: Capsule())
        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
    }

    /// Bold uppercase prompt in a dark rounded pill (matches the design reference).
    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 13).padding(.vertical, 5)
            .background(.black.opacity(0.5), in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    }

    /// `eased` smooths chunky, step-changing bars (objective, kraken damage, boot bonus). Leave it off
    /// for the per-frame, timing-critical bars (reel gauge, cast reach, line strain) so they stay snappy.
    private func meter(_ value: Double, _ color: Color, eased: Bool = false) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule().fill(color)
                    .frame(width: max(2, geo.size.width * min(1, max(0, value))))
                    .animation(eased ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: value)
            }
        }
        .frame(height: 5)
    }

    // MARK: Result cards ----------------------------------------------------

    private var landedCard: some View {
        VStack(spacing: 3) {
            if let sp = model.lastSpecial {
                Image(systemName: sp == .chest ? "shippingbox.fill" : "hammer.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(sp == .chest ? Sea.gold : Sea.teal)
                Text(sp.title)
                    .font(.headline)
                    .foregroundStyle(sp == .chest ? Sea.gold : Sea.teal)
                Text(sp.blurb)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            } else if let c = model.lastCatch {
                Text(c.kind.name)
                    .font(.headline)
                    .foregroundStyle(GameArt.fishColor(c.kind))
                Text(c.points > 0 ? "+\(c.points)" : "No points")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))
                    .foregroundStyle(c.points > 0 ? Sea.gold : .secondary)
                if c.points > 0 && (model.lastPerfect || model.lastComboMult >= 2) {
                    HStack(spacing: 6) {
                        if model.lastPerfect {
                            Text("PERFECT").font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(Sea.teal)
                        }
                        if model.lastComboMult >= 2 {
                            Text("\(model.lastComboMult)× COMBO").font(.system(size: 11, weight: .black, design: .rounded))
                                .foregroundStyle(Sea.coral)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .allowsHitTesting(false)        // purely informational; it auto-continues — no tap target here
    }

    @ViewBuilder private var gameOverCard: some View {
        if model.isCampaign {
            if model.levelWon { campaignWinCard } else { campaignFailCard }
        } else {
            freeplayOverCard
        }
    }

    private var freeplayOverCard: some View {
        VStack(spacing: 5) {
            Text(model.crashIsMine ? "BLOWN UP" : "TRIP OVER")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .tracking(2)
                .foregroundStyle(model.crashIsMine ? Color.red.opacity(0.9) : .secondary)
            Text("\(model.score)")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Sea.gradient)
                .shadow(color: Sea.blue.opacity(0.35), radius: 7)
            if model.isBest {
                Label("New best!", systemImage: "trophy.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Sea.gold)
            } else {
                Text("Best \(LocalStore.best())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 5) {
                Button("Play again") { model.restart() }
                    .buttonStyle(.seaPrimary)
                Button("Menu", action: onExit)
                    .buttonStyle(.seaSecondary())
            }
            .padding(.top, 4)
        }
    }

    private var campaignWinCard: some View {
        VStack(spacing: 6) {
            Text("LEVEL \(config.id)")
                .font(.system(.caption2, design: .rounded).weight(.bold)).tracking(3)
                .foregroundStyle(.secondary)
            Text("COMPLETE")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(Sea.gradient)
                .shadow(color: Sea.blue.opacity(0.4), radius: 6)
            starsRow(model.levelStars, shown: starsShown)
                .padding(.vertical, 2)
            VStack(spacing: 6) {
                Text("\(model.score) pts")
                    .font(.system(size: 16, weight: .heavy, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Sea.gold)
                VStack(spacing: 5) {
                    if let next = nextLevel {
                        Button("Next level") { startLevel(next) }
                            .buttonStyle(.seaPrimary)
                        Button("Menu", action: onExit).buttonStyle(.seaSecondary())
                    } else {
                        Text("Campaign cleared! 🎣")
                            .font(.caption2.weight(.semibold)).foregroundStyle(Sea.teal)
                        Button("Menu", action: onExit).buttonStyle(.seaPrimary)
                    }
                }
                .padding(.top, 4)
            }
            .opacity(winDetailsIn ? 1 : 0)
            .offset(y: winDetailsIn ? 0 : 10)
        }
    }

    private var campaignFailCard: some View {
        VStack(spacing: 5) {
            Text(model.crashIsMine ? "BLOWN UP" : "TRIP OVER")
                .font(.system(.caption2, design: .rounded).weight(.bold)).tracking(2)
                .foregroundStyle(model.crashIsMine ? Color.red.opacity(0.9) : .secondary)
            Image(systemName: "target")
                .font(.system(size: 22))
                .foregroundStyle(Sea.coral.opacity(0.85))
            Text(config.subtitle)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(model.objectiveText)
                .font(.caption2).foregroundStyle(.secondary)
            VStack(spacing: 5) {
                Button("Retry") { model.restart() }
                    .buttonStyle(.seaPrimary)
                Button("Menu", action: onExit).buttonStyle(.seaSecondary())
            }
            .padding(.top, 4)
        }
    }

    /// Three star slots; the `shown` earned stars pop in on top of dim placeholders.
    private func starsRow(_ total: Int, shown: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                ZStack {
                    Image(systemName: "star")                    // always-present dim slot
                        .foregroundStyle(.white.opacity(0.22))
                    if i < total && i < shown {                  // earned star pops in
                        Image(systemName: "star.fill")
                            .foregroundStyle(Sea.gold)
                            .shadow(color: Sea.gold.opacity(0.6), radius: 5)
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    }
                }
                .font(.system(size: 22))
            }
        }
    }

}
