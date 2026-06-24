//
//  RootView.swift
//  Wristfish — the start menu. Full-screen state switch (no nav chrome over the game).
//

import SwiftUI

struct RootView: View {
    private enum Screen { case menu, playing, tutorial, settings }
    @State private var screen: Screen = .menu

    var body: some View {
        ZStack {
            Sea.deep.ignoresSafeArea()
            switch screen {
            case .menu:     menu
            case .playing:  GameView(onExit: { screen = .menu })
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

                Button("Play") { screen = .playing }
                    .buttonStyle(.seaPrimary)
                Button("How to play") { screen = .tutorial }
                    .buttonStyle(.seaSecondary())
                Button("Settings") { screen = .settings }
                    .buttonStyle(.seaSecondary(Sea.blue))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

#Preview {
    RootView()
}
