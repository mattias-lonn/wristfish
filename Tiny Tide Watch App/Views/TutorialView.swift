//
//  TutorialView.swift
//  Tiny Tide — "How to play", reachable from the start menu.
//

import SwiftUI

struct TutorialView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                step(Controls.steerIcon, "Steer", "\(Controls.steerVerb) to steer your boat. Dodge the rocks — hitting one ends the trip.", Sea.teal)
                step("dot.radiowaves.left.and.right", "Find fish", "Ripples mean fish below. Small teal ripples are shallow; big blue ones with a shadow are deep.", Sea.blue)
                step("hand.tap.fill", "Cast", "Line up with a ripple, tap to send the line out, then tap again to drop it. You control how far it reaches.", Sea.teal)
                step("arrow.up.and.down.circle.fill", "Reel", "When a fish bites, \(Controls.reelVerb) to keep the marker inside the slowly-moving zone. Hold it there and the fish comes in.", Sea.coral)
                step("trophy.fill", "Score", "Bigger fish are worth more points. The deep water hides the real trophies.", Sea.gold)
            }
            .padding(.horizontal, 14)
            .padding(.top, 4).padding(.bottom, 10)
        }
    }

    private func step(_ icon: String, _ title: String, _ text: String, _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(text).font(.caption).foregroundStyle(.white.opacity(0.78))
            }
        }
    }
}
