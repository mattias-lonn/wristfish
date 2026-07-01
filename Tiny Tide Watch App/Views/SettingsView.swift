//
//  SettingsView.swift
//  Tiny Tide — minimal settings (more can be added as the game grows).
//

import SwiftUI

struct SettingsView: View {
    @State private var haptics = LocalStore.hapticsEnabled
    @State private var sound = LocalStore.soundEnabled
    @State private var music = LocalStore.musicEnabled

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Toggle("Sound", isOn: $sound)
                    .font(.callout)
                    .tint(Sea.teal)
                    .onChange(of: sound) { _, value in
                        LocalStore.soundEnabled = value
                        if value { SoundManager.shared.play(.catchSmall) }   // hear the setting you just enabled
                    }

                Toggle("Music", isOn: $music)
                    .font(.callout)
                    .tint(Sea.teal)
                    .onChange(of: music) { _, value in
                        LocalStore.musicEnabled = value
                        MusicManager.shared.setEnabled(value)                // start/stop the menu bed right away
                    }

                Toggle("Haptics", isOn: $haptics)
                    .font(.callout)
                    .tint(Sea.teal)
                    .onChange(of: haptics) { _, value in
                        LocalStore.hapticsEnabled = value
                        if value { HapticsManager.shared.play(.reel) }   // feel the setting you just enabled
                    }

                // A small stats card — read-only progress at a glance.
                VStack(spacing: 9) {
                    statRow("trophy.fill", "Best catch", "\(LocalStore.best())", Sea.gold)
                    statRow("star.fill", "Stars", "\(LocalStore.totalStars()) / \(LevelConfig.campaign.count * 3)", Sea.gold)
                    statRow("fish.fill", "Fish caught", "\(LocalStore.totalFish())", Sea.teal)
                }
                .padding(12)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 14)
            .padding(.top, 4).padding(.bottom, 10)
        }
    }

    private func statRow(_ icon: String, _ label: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint).frame(width: 18)
            Text(label).font(.system(size: 13))
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded)).monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}
