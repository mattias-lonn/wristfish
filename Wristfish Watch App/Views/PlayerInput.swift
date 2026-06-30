//
//  PlayerInput.swift
//  Wristfish — the one platform-specific seam for controls. The game model only ever sees an abstract
//  `crown(delta:)` channel plus `tap()`, so each platform just feeds that: the watch uses the Digital
//  Crown, iOS uses a drag (to be tuned when the iPhone target lands). Everything else is shared.
//

import SwiftUI

struct PlayerInput: ViewModifier {
    @ObservedObject var model: GameModel

    #if os(watchOS)
    @State private var crown = 0.0
    @FocusState private var focused: Bool
    #elseif os(iOS)
    @State private var lastDragX = 0.0
    #endif

    func body(content: Content) -> some View {
        #if os(watchOS)
        content
            .focusable(true)
            .focused($focused)
            .digitalCrownRotation($crown, from: -1_000_000, through: 1_000_000, by: 0.5,
                                  sensitivity: .high, isContinuous: true, isHapticFeedbackEnabled: false)
            .onChange(of: crown) { old, new in model.crown(delta: new - old) }
            .onAppear { focused = true }
        #elseif os(iOS)
        // Touch control: a SIDEWAYS drag feeds the same abstract channel as the Digital Crown, so it
        // drives steering (boating) and the reeling marker identically — zero game-logic changes.
        // Casting stays on the shared tap (GameView's .onTapGesture); minimumDistance lets taps through.
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        let dx = v.translation.width - lastDragX
                        lastDragX = v.translation.width
                        model.crown(delta: Double(dx) * 0.16)   // drag right → boat right; ~60% screen ≈ full lane
                    }
                    .onEnded { _ in lastDragX = 0 }
            )
        #endif
    }
}

extension View {
    /// Routes platform input into the model's abstract control channel.
    func playerInput(_ model: GameModel) -> some View { modifier(PlayerInput(model: model)) }
}

/// Human-readable control wording, per platform — keeps hints and the tutorial honest (no "Crown" on iPhone).
enum Controls {
    #if os(iOS)
    static let steerHint = "Drag to steer"
    static let steerVerb = "Drag sideways"      // tutorial: "<verb> to steer your boat."
    static let reelVerb  = "drag"               // tutorial: "…<verb> to keep the marker…"
    static let steerIcon = "hand.draw.fill"
    #else
    static let steerHint = "Crown to steer"
    static let steerVerb = "Turn the Digital Crown"
    static let reelVerb  = "use the Crown"
    static let steerIcon = "dial.medium.fill"
    #endif
}
