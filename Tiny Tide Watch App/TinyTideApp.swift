//
//  TinyTideApp.swift
//  Tiny Tide Watch App
//
//  Created by Mattias Lönn on 2026-06-22.
//

import SwiftUI

@main
struct TinyTideApp: App {
    init() { LocalStore.startCloudSync() }   // begin mirroring progress to iCloud + merging changes back

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)   // the art is dark-themed — match the watch (no light-mode washout on iPhone)
        }
    }
}
