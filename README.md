# Tiny Tide

> Player-facing name is **Tiny Tide**. The Xcode project, schemes and folders keep the original
> **Wristfish** codename, so build commands still say "Wristfish".
>
> **Shipping target:** the **Wristfish iOS** target is the single iOS app (`com.dropdev.tinytide`)
> and it now embeds the watch app (`com.dropdev.tinytide.watchkitapp`, companion = the iOS app) — so
> iPhone + Watch ship together from one app record. Archive the **Wristfish iOS** scheme.
> The watch app is **independent** (`WKRunsIndependentlyOfCompanionApp = YES`), so Apple Watch users
> can find and install it straight from the **Watch App Store** without first installing the iPhone app.
> The old **Wristfish** watch-container target (`com.dropdev.Wristfish`) is now vestigial — delete it
> in Xcode (Targets → Wristfish → Delete) when convenient; don't build/archive it.

A cozy cross-platform (Apple Watch + iPhone) fishing game built in SwiftUI — steer a boat, dodge rocks and lighthouses,
cast at ripples, and work a balance gauge to land your catch. Hook the occasional
treasure chest (double points), pickaxe (cleave through rocks), or sea mine (let it go!).

## Build & run

Open `Wristfish.xcodeproj` in Xcode and run the **Wristfish Watch App** scheme on a
watchOS simulator, or from the command line:

```sh
xcodebuild -project Wristfish.xcodeproj -scheme "Wristfish Watch App" \
  -configuration Debug \
  -destination "platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)" build
```

## Layout

- `Wristfish Watch App/Render/GameArt.swift` — all the drawing (water, boats, fish, effects)
- `Wristfish Watch App/Render/GameCanvas.swift` — turns game state into each frame
- `Wristfish Watch App/Game/GameModel.swift` — game logic and the 30 fps loop
- `Wristfish Watch App/Game/GameTypes.swift` — value types
- `Wristfish Watch App/Views/` — SwiftUI screens (menu, game, HUD)
