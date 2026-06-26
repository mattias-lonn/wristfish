//
//  RootView.swift
//  Wristfish — the start menu. Full-screen state switch (no nav chrome over the game).
//

import SwiftUI

struct RootView: View {
    private enum Screen { case menu, campaign, playing, tutorial, settings }
    @State private var screen: Screen = .menu
    @State private var playConfig: LevelConfig = .freeplay

    var body: some View {
        ZStack {
            Sea.deep.ignoresSafeArea()
            switch screen {
            case .menu:     menu
            case .campaign: campaign
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
                Button("How to play") { screen = .tutorial }
                    .buttonStyle(.seaSecondary())
                Button("Settings") { screen = .settings }
                    .buttonStyle(.seaSecondary(Sea.blue))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: Campaign level select ------------------------------------------

    private var campaign: some View {
        ScrollView {
            VStack(spacing: 7) {
                HStack {
                    Text("CAMPAIGN")
                        .font(.system(.headline, design: .rounded).weight(.black)).tracking(1)
                        .foregroundStyle(Sea.gradient)
                    Spacer()
                    Label("\(LocalStore.totalStars())", systemImage: "star.fill")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(Sea.gold)
                }
                .padding(.bottom, 2)

                ForEach(LevelConfig.campaign, id: \.id) { lvl in
                    levelRow(lvl)
                }

                Button("Back") { screen = .menu }
                    .buttonStyle(.seaSecondary(Sea.blue))
                    .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
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
}

#Preview {
    RootView()
}
