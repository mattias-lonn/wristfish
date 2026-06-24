//
//  TutorialView.swift
//  Wristfish — "How to play", reachable from the start menu.
//

import SwiftUI

struct TutorialView: View {
    var onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("How to play")
                    .font(.headline)
                    .frame(maxWidth: .infinity)

                step("dial.medium.fill", "Steer", "Turn the Digital Crown to steer your boat. Dodge the rocks — hitting one ends the trip.", Sea.teal)
                step("dot.radiowaves.left.and.right", "Find fish", "Ripples mean fish below. Small teal ripples are shallow; big blue ones with a shadow are deep.", Sea.blue)
                step("hand.tap.fill", "Cast", "Line up with a ripple, tap to send the line out, then tap again to drop it. You control how far it reaches.", Sea.teal)
                step("arrow.up.and.down.circle.fill", "Reel", "When a fish bites, use the Crown to keep the marker inside the slowly-moving zone. Hold it there and the fish comes in.", Sea.coral)
                step("trophy.fill", "Score", "Bigger fish are worth more points. The deep water hides the real trophies.", Sea.gold)

                Button("Back", action: onBack)
                    .buttonStyle(.seaSecondary())
                    .padding(.top, 4)
            }
            .padding()
        }
    }

    private func step(_ icon: String, _ title: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.bold())
                Text(text).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
