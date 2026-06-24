//
//  SettingsView.swift
//  Wristfish — minimal settings (more can be added as the game grows).
//

import SwiftUI

struct SettingsView: View {
    var onBack: () -> Void
    @State private var haptics = LocalStore.hapticsEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Settings")
                    .font(.headline)

                Toggle("Haptics", isOn: $haptics)
                    .tint(Sea.teal)
                    .onChange(of: haptics) { _, value in LocalStore.hapticsEnabled = value }

                HStack {
                    Text("Best catch")
                    Spacer()
                    Text("\(LocalStore.best())")
                        .foregroundStyle(Sea.gold)
                        .monospacedDigit()
                }
                .font(.caption)
                .padding(.vertical, 2)

                Button("Back", action: onBack)
                    .buttonStyle(.seaSecondary())
                    .padding(.top, 6)
            }
            .padding()
        }
    }
}
