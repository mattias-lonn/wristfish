//
//  RootView.swift
//  Wristfish — the start menu. Full-screen state switch (no nav chrome over the game).
//

import SwiftUI

struct RootView: View {
    private enum Screen { case menu, campaign, boats, playing, tutorial, settings }
    @State private var screen: Screen = .menu
    @State private var playConfig: LevelConfig = .freeplay
    @State private var chosenBoat = LocalStore.selectedBoat()

    var body: some View {
        ZStack {
            Sea.deep.ignoresSafeArea()
            switch screen {
            case .menu:     menu
            case .campaign: screenWithBack { campaign }
            case .boats:    screenWithBack { boats }
            case .playing:
                GameView(config: playConfig,
                         onExit: { screen = playConfig.objective == nil ? .menu : .campaign })
            case .tutorial: TutorialView(onBack: { screen = .menu })
            case .settings: SettingsView(onBack: { screen = .menu })
            }
        }
    }

    private var menu: some View {
        ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 1) {
                    Image(systemName: "fish.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Sea.teal)
                    Text("WRISTFISH")
                        .font(.system(.title3, design: .rounded).weight(.black))
                        .tracking(1)
                        .foregroundStyle(Sea.gradient)
                }
                .padding(.bottom, 2)

                Button("Campaign") { screen = .campaign }
                    .buttonStyle(.seaPrimary)
                Button("Open Water") { playConfig = .freeplay; screen = .playing }
                    .buttonStyle(.seaSecondary())
                Button("Boats") { screen = .boats }
                    .buttonStyle(.seaSecondary())
                Button("How to play") { screen = .tutorial }
                    .buttonStyle(.seaSecondary())
                Button("Settings") { screen = .settings }
                    .buttonStyle(.seaSecondary(Sea.blue))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: A consistent top-left back arrow ------------------------------

    private func screenWithBack<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            content()
            Button { screen = .menu } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Sea.teal)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(Sea.teal.opacity(0.4), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4).padding(.top, -10)     // hug the top-left corner
        }
    }

    // MARK: Campaign level select ------------------------------------------

    private var campaign: some View {
        ScrollView {
            VStack(spacing: 7) {
                VStack(spacing: 1) {
                    Text("CAMPAIGN")
                        .font(.system(.headline, design: .rounded).weight(.black)).tracking(1)
                        .foregroundStyle(Sea.gradient)
                    Label("\(LocalStore.totalStars())", systemImage: "star.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Sea.gold)
                }
                .padding(.top, 2).padding(.bottom, 2)

                ForEach(LevelConfig.campaign, id: \.id) { lvl in
                    levelRow(lvl)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 26).padding(.bottom, 8)      // clear the floating back arrow
        }
    }

    private func levelRow(_ lvl: LevelConfig) -> some View {
        let unlocked = LocalStore.isUnlocked(level: lvl.id)
        let stars = LocalStore.stars(level: lvl.id)
        return Button {
            guard unlocked else { return }
            playConfig = lvl
            screen = .playing
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(lvl.id). \(lvl.title)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(lvl.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if unlocked {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < stars ? "star.fill" : "star")
                                .font(.system(size: 8))
                                .foregroundStyle(i < stars ? Sea.gold : .white.opacity(0.25))
                        }
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.white.opacity(unlocked ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 12))
        .opacity(unlocked ? 1 : 0.6)
        .disabled(!unlocked)
    }

    // MARK: Boat picker ----------------------------------------------------

    private let boatGrid = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    private var boats: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("BOATS")
                    .font(.system(.headline, design: .rounded).weight(.black)).tracking(1)
                    .foregroundStyle(Sea.gradient)
                    .padding(.bottom, 2)

                LazyVGrid(columns: boatGrid, spacing: 6) {
                    ForEach(BoatModel.all) { b in boatCard(b) }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 26).padding(.bottom, 8)      // clear the floating back arrow
        }
    }

    /// A compact tile: the boat shown clean (no wake/foam) on still water, with name + status.
    private func boatCard(_ b: BoatModel) -> some View {
        let unlocked = b.isUnlocked
        let selected = chosenBoat == b.id
        return Button {
            guard unlocked else { return }
            LocalStore.setSelectedBoat(b.id)
            chosenBoat = b.id
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Sea.waterGradient)
                    Canvas { ctx, size in            // no wake/foam/angler: a clean portrait of the hull
                        GameArt.drawBoat(ctx, size, x: 0.5, boatY: 0.53, wake: [], t: 0,
                                         speed: 0, hull: b.hull, accent: b.accent, scale: 2.45,
                                         style: b.style, angler: false)
                    }
                    if !unlocked {
                        RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black.opacity(0.5))
                        Image(systemName: "lock.fill").font(.system(size: 20)).foregroundStyle(.white.opacity(0.85))
                    }
                    if selected {
                        VStack { HStack { Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16)).foregroundStyle(Sea.teal)
                                .shadow(color: .black.opacity(0.4), radius: 2)
                        }; Spacer() }.padding(5)
                    }
                }
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(selected ? Sea.teal : .white.opacity(0.10), lineWidth: selected ? 2 : 1))

                Text(b.name)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(statusLine(b, unlocked: unlocked, selected: selected))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(selected ? Sea.teal : (unlocked ? .secondary : Sea.coral.opacity(0.9)))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .opacity(unlocked ? 1 : 0.9)
        .disabled(!unlocked)
    }

    private func statusLine(_ b: BoatModel, unlocked: Bool, selected: Bool) -> String {
        if selected { return "Selected ✓" }
        if unlocked { return "Tap to use" }
        let cur = compact(min(b.unlock.current, b.unlock.target)), tgt = compact(b.unlock.target)
        return "\(b.unlock.metric) \(cur)/\(tgt)"
    }

    /// 25000 → "25k" for tight tiles.
    private func compact(_ n: Int) -> String { n >= 1000 ? "\(n / 1000)k" : "\(n)" }
}

#Preview {
    RootView()
}
