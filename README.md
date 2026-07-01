# Tiny Tide

> **Shipping target:** the **Tiny Tide iOS** target is the single iOS app (`com.dropdev.tinytide`)
> and it now embeds the watch app (`com.dropdev.tinytide.watchkitapp`, companion = the iOS app) — so
> iPhone + Watch ship together from one app record. Archive the **Tiny Tide iOS** scheme.
> The watch app is **independent** (`WKRunsIndependentlyOfCompanionApp = YES`), so Apple Watch users
> can find and install it straight from the **Watch App Store** without first installing the iPhone app.
> The legacy watch-container target (named **Tiny Tide**, `com.dropdev.tinytidecontainer`) is vestigial —
> delete it in Xcode (Targets → Tiny Tide → Delete) when convenient; don't build/archive it.

A cozy cross-platform (Apple Watch + iPhone) fishing game built in SwiftUI — steer a boat, dodge rocks and lighthouses,
cast at ripples, and work a balance gauge to land your catch. Hook the occasional
treasure chest (double points), pickaxe (cleave through rocks), or sea mine (let it go!).

## Build & run

Open `Tiny Tide.xcodeproj` in Xcode and run the **Tiny Tide Watch App** scheme on a
watchOS simulator, or from the command line:

```sh
xcodebuild -project Tiny Tide.xcodeproj -scheme "Tiny Tide Watch App" \
  -configuration Debug \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build
```

## Layout

- `Tiny Tide Watch App/Render/GameArt.swift` — all the drawing (water, boats, fish, effects)
- `Tiny Tide Watch App/Render/GameCanvas.swift` — turns game state into each frame
- `Tiny Tide Watch App/Game/GameModel.swift` — game logic and the 30 fps loop
- `Tiny Tide Watch App/Game/GameTypes.swift` — value types
- `Tiny Tide Watch App/Views/` — SwiftUI screens (menu, game, HUD)
