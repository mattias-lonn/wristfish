//
//  WristfishApp.swift
//  Wristfish Watch App
//
//  Created by Mattias Lönn on 2026-06-22.
//

import SwiftUI

@main
struct Wristfish_Watch_AppApp: App {
    init() { LocalStore.startCloudSync() }   // begin mirroring progress to iCloud + merging changes back

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
