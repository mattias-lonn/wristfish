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
    @State private var lastDragY = 0.0
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
        // Placeholder touch control — a vertical drag drives the same delta channel as the Crown.
        // The real iPhone scheme (drag axis / tilt / on-screen control + feel tuning) is designed
        // when the iOS target is added; the model side needs no changes.
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let dy = v.translation.height - lastDragY
                        lastDragY = v.translation.height
                        model.crown(delta: -dy * 0.06)   // drag up ≈ Crown up; scale is provisional
                    }
                    .onEnded { _ in lastDragY = 0 }
            )
        #endif
    }
}

extension View {
    /// Routes platform input into the model's abstract control channel.
    func playerInput(_ model: GameModel) -> some View { modifier(PlayerInput(model: model)) }
}
