//
//  GameView.swift
//  Wristfish — the gameplay screen. Hosts the Canvas, routes Crown + taps to the model,
//  and lays the HUD / result cards on top.
//

import SwiftUI

struct GameView: View {
    @StateObject private var model = GameModel()
    var onExit: () -> Void

    @State private var crown = 0.0
    @FocusState private var focused: Bool

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
            if model.scorePopActive && model.phase != .landed { scorePopView }
            if model.phase == .landed   { landedCard }
            if model.phase == .gameOver { gameOverCard }
        }
        .focusable(true)
        .focused($focused)
        .digitalCrownRotation($crown, from: -1_000_000, through: 1_000_000, by: 0.5,
                              sensitivity: .high, isContinuous: true, isHapticFeedbackEnabled: false)
        .onChange(of: crown) { old, new in model.crown(delta: new - old) }
        .onAppear { focused = true; model.start() }
        .onDisappear { model.stop() }
    }

    // MARK: HUD -------------------------------------------------------------

    private var hud: some View {
        VStack {
            HStack {
                Text("\(model.score)")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(Sea.gold)
                    .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)                      // sits level with the watch time

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

            if !model.flash.isEmpty {
                Text(model.flash)
                    .font(.caption.bold())
                    .foregroundStyle(Sea.coral)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.5), in: Capsule())
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

        case .boating:
            if model.targetAhead {
                pill("Tap to cast", Sea.gold).padding(.bottom, 6)
            } else if model.elapsed < 4 && model.score == 0 {
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

    private func meter(_ value: Double, _ color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule().fill(color)
                    .frame(width: max(2, geo.size.width * min(1, max(0, value))))
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
            Text("Tap to keep fishing")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
        .onTapGesture { model.tap() }
    }

    private var gameOverCard: some View {
        VStack(spacing: 4) {
            Text(model.crashIsMine ? "BLOWN UP" : "TRIP OVER")
                .font(.system(.caption2, design: .rounded).weight(.bold))
                .tracking(2)
                .foregroundStyle(model.crashIsMine ? Color.red.opacity(0.9) : .secondary)
            Text("\(model.score)")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
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
            .padding(.top, 6)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}
