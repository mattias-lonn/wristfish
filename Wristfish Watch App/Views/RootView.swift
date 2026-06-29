//
//  RootView.swift
//  Wristfish — the start menu. Full-screen state switch (no nav chrome over the game).
//

import SwiftUI

struct RootView: View {
    private enum Route: Hashable { case campaign, boats, tutorial, settings }
    @State private var path: [Route] = []
    @State private var playing = false
    @State private var playConfig: LevelConfig = .freeplay
    @State private var chosenBoat = LocalStore.selectedBoat()
    private let haptics = HapticsManager.shared

    // One-time intro: boat sails up (full-screen) → settles into the scroll header → title in → buttons stagger.
    @State private var introPlayed = false
    @State private var boatRaised = false      // false → boat held below the screen; animate true to race it up
    @State private var settled = false        // boat reached the top; fish ripples start dancing
    @State private var settleT: Double = 0     // reference time the boat docked, for a smooth race→idle blend
    @State private var titleIn = false
    @State private var shownButtons = 0
    @State private var scrollY: CGFloat = 0    // live menu scroll offset; the boat tracks it
    private let introDelay = 0.30              // a water-only beat before the boat appears
    private let riseDuration = 1.40            // the boat racing up from the bottom of the screen
    private let boatStartY = 1.10              // just below the screen — fully hidden until it sets off
    private let boatRestY = 0.22               // resting centre; the small boat parks high, near the top
    private let boatScale = 1.0                // same size as in gameplay

    var body: some View {
        ZStack {
            Sea.deep.ignoresSafeArea()
            if playing {
                // Gameplay runs full-screen, outside the navigation chrome.
                GameView(config: playConfig,
                         onExit: { withAnimation(.easeInOut(duration: 0.2)) { playing = false } })
                    .transition(.opacity)
            } else {
                NavigationStack(path: $path) {
                    menu
                        .containerBackground(Sea.deep, for: .navigation)
                        .navigationDestination(for: Route.self) { route in
                            destination(route).containerBackground(Sea.deep, for: .navigation)
                        }
                }
                .tint(Sea.teal)                  // the native back chevron uses our accent
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .campaign: campaign.navigationTitle("Campaign")
        case .boats:    boats.navigationTitle("Boats")
        case .tutorial: TutorialView().navigationTitle("How to Play")
        case .settings: SettingsView().navigationTitle("Settings")
        }
    }

    private func open(_ route: Route) { haptics.play(.reel); path.append(route) }

    private func startGame(_ c: LevelConfig) {
        playConfig = c
        haptics.play(.reel)
        withAnimation(.easeInOut(duration: 0.2)) { playing = true }
    }

    private var menu: some View {
        GeometryReader { geo in
            let H = geo.size.height
            ZStack(alignment: .top) {
                waterScene                                   // full-screen living water (behind everything)
                boatLayer(H: H)                              // one full-screen boat: sails up, then rides the scroll

                // Legibility scrim: clear at the top (water + boat shine), darker over the buttons.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: 0.34),
                    .init(color: Sea.deep.opacity(0.86), location: 0.62),
                    .init(color: Sea.deep.opacity(0.94), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

                // Title + buttons scroll; the boat behind tracks the same offset, so all move together.
                ScrollView {
                    VStack(spacing: 12) {
                        Color.clear.frame(height: H * 0.27)      // title tucks in right at the boat's stern
                        Text("WRISTFISH")
                            .font(.system(size: 26, weight: .black, design: .rounded)).tracking(1)
                            .foregroundStyle(Sea.titleGradient)
                            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
                            .opacity(titleIn ? 1 : 0)
                            .offset(y: titleIn ? 0 : 30)

                        Button { open(.campaign) } label: { Label("Campaign", systemImage: "map.fill") }
                            .buttonStyle(.seaPrimary).modifier(Stagger(shownButtons, 0))
                        Button { startGame(.freeplay) } label: { Label("Open Water", systemImage: "play.fill") }
                            .buttonStyle(.seaSecondary()).modifier(Stagger(shownButtons, 1))
                        Button { open(.boats) } label: { Label("Boats", systemImage: "sailboat.fill") }
                            .buttonStyle(.seaSecondary()).modifier(Stagger(shownButtons, 2))
                        Button { open(.tutorial) } label: { Label("How to play", systemImage: "questionmark.circle.fill") }
                            .buttonStyle(.seaSecondary()).modifier(Stagger(shownButtons, 3))
                        Button { open(.settings) } label: { Label("Settings", systemImage: "gearshape.fill") }
                            .buttonStyle(.seaSecondary(Sea.blue)).modifier(Stagger(shownButtons, 4))
                    }
                    .padding(.horizontal, 16).padding(.bottom, 10)
                }
                .scrollIndicators(.hidden)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in scrollY = y }
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: runIntro)
    }

    private func runIntro() {
        guard !introPlayed else { return }                // once per launch; later visits keep everything in place
        introPlayed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + introDelay) {      // after the water-only beat…
            withAnimation(.easeOut(duration: riseDuration)) { boatRaised = true }   // …the boat races up and docks
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + introDelay + riseDuration) {   // the boat has docked
            settleT = Date().timeIntervalSinceReferenceDate
            settled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.45)) { titleIn = true }  // then the title rises into its stern
                for i in 0..<5 {                                            // then the buttons, one by one
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.30 + Double(i) * 0.10) {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.72)) { shownButtons = i + 1 }
                    }
                }
            }
        }
    }

    /// Full-screen living water: flowing surface, ambient wake, and fish ripples — no boat, no obstacles.
    /// Rides the menu scroll (`-scrollY`) so the whole seascape moves together with the boat and buttons.
    private var waterScene: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let c = settled ? min(1, max(0, (t - settleT) / 0.7)) : 0
            let fade = c * c * (3 - 2 * c)                                // same race→idle blend as the boat
            Canvas { ctx, size in
                GameArt.drawWater(ctx, size, scroll: t * 0.5)
                GameArt.drawAmbientWake(ctx, size, t: t)
                if fade > 0 { GameArt.drawMenuRipples(ctx, size, t: t, fade: fade) }   // fish ripples ease in once docked
            }
        }
        .offset(y: -scrollY)
    }

    /// The boat lives in ONE full-screen canvas (so it never distorts): it sails up from the bottom
    /// during the intro, settles near the top, then rides the menu scroll (offset by `scrollY`) so it
    /// moves together with the title and buttons.
    private func boatLayer(H: CGFloat) -> some View {
        let boat = BoatModel.all.first { $0.id == chosenBoat } ?? BoatModel.all[0]
        // The canvas always draws the boat at its resting spot; the rise is a plain SwiftUI
        // `.offset` animation (frame-perfect, unlike deriving position from the TimelineView clock).
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            // Blend race → idle over ~0.7s after docking so nothing snaps: the bob/sway ease in from
            // zero and the wake settles down gradually, instead of flipping on the instant it arrives.
            let c = settled ? min(1, max(0, (t - settleT) / 0.7)) : 0
            let calm = c * c * (3 - 2 * c)
            let sway = sin(t * 0.6) * 0.015 * calm
            let bob = sin(t * 1.5) * 0.010 * calm
            Canvas { ctx, size in
                let strength = 1.0 - 0.7 * calm                            // long wake while racing → gentle at rest
                let trail = (0..<14).map { i in 0.5 + sin((t - Double(i) * 0.05) * 0.6) * 0.03 }
                GameArt.drawBoat(ctx, size, x: 0.5 + sway, boatY: boatRestY + bob,
                                 wake: trail, t: t, speed: strength, hull: boat.hull, accent: boat.accent,
                                 scale: boatScale, style: boat.style, shiny: boat.shiny)
            }
        }
        // Held (boatStartY − boatRestY)·H below the screen until raised, then animated up to 0.
        // Combined with the scroll offset so the boat keeps riding the menu after it's docked.
        .offset(y: (boatRaised ? 0 : (boatStartY - boatRestY) * H) - scrollY)
        .allowsHitTesting(false)
    }

    // MARK: Campaign level select ------------------------------------------

    private var campaign: some View {
        ScrollView {
            VStack(spacing: 10) {
                HStack(spacing: 4) {                     // total-stars summary
                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(Sea.gold)
                    Text("\(LocalStore.totalStars())")
                        .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Sea.gold)
                    Text("/ \(LevelConfig.campaign.count * 3)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                }
                .padding(.bottom, 2)

                ForEach(LevelConfig.campaign, id: \.id) { lvl in
                    levelRow(lvl)
                }
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
        }
    }

    private func levelRow(_ lvl: LevelConfig) -> some View {
        let unlocked = LocalStore.isUnlocked(level: lvl.id)
        let stars = LocalStore.stars(level: lvl.id)
        return Button {
            guard unlocked else { haptics.play(.miss); return }
            startGame(lvl)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("\(lvl.id)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(lvl.title)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)   // wrap, never truncate
                    }
                    Text(unlocked ? lvl.subtitle : "Clear level \(lvl.id - 1) to unlock")
                        .font(.system(size: 11))
                        .foregroundStyle(unlocked ? .white.opacity(0.6) : Sea.coral.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if unlocked {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            Image(systemName: i < stars ? "star.fill" : "star")
                                .font(.system(size: 11))
                                .foregroundStyle(i < stars ? Sea.gold : .white.opacity(0.42))
                        }
                    }
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(.white.opacity(unlocked ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 13))
        .opacity(unlocked ? 1 : 0.6)
        .disabled(!unlocked)
    }

    // MARK: Boat picker ----------------------------------------------------

    private let boatGrid = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    private var boats: some View {
        ScrollView {
            LazyVGrid(columns: boatGrid, spacing: 8) {
                ForEach(BoatModel.all) { b in boatCard(b) }
            }
            .padding(.horizontal, 9).padding(.bottom, 8)
        }
    }

    /// A compact tile: the boat shown clean (no wake/foam) on still water, with name + status.
    private func boatCard(_ b: BoatModel) -> some View {
        let unlocked = b.isUnlocked
        let selected = chosenBoat == b.id
        return Button {
            guard unlocked else { haptics.play(.miss); return }
            LocalStore.setSelectedBoat(b.id)
            withAnimation(.snappy(duration: 0.2)) { chosenBoat = b.id }
            haptics.play(.catchSmall)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Sea.waterGradient)
                    Canvas { ctx, size in            // no wake/foam/angler: a clean portrait of the hull
                        GameArt.drawBoat(ctx, size, x: 0.5, boatY: 0.53, wake: [], t: 0.6,
                                         speed: 0, hull: b.hull, accent: b.accent, scale: 2.45,
                                         style: b.style, angler: false, shiny: b.shiny)
                    }
                    if !unlocked {
                        RoundedRectangle(cornerRadius: 13, style: .continuous).fill(.black.opacity(0.5))
                        Image(systemName: "lock.fill").font(.system(size: 20)).foregroundStyle(.white.opacity(0.85))
                    }
                    if selected {
                        VStack { HStack { Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16)).foregroundStyle(Sea.teal)
                                .shadow(color: .black.opacity(0.4), radius: 2)
                        }; Spacer() }.padding(5)
                    }
                }
                .frame(height: 118)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(selected ? Sea.teal : .white.opacity(0.22), lineWidth: selected ? 2.5 : 1))

                Text(b.name)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)   // wrap, never truncate
                Text(statusLine(b, unlocked: unlocked, selected: selected))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Sea.teal : (unlocked ? .white.opacity(0.6) : Sea.coral.opacity(0.95)))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
        .opacity(unlocked ? 1 : 0.62)
        .disabled(!unlocked)
    }

    private func statusLine(_ b: BoatModel, unlocked: Bool, selected: Bool) -> String {
        if selected { return "Selected ✓" }
        if unlocked { return "Tap to use" }
        let cur = compact(min(b.unlock.current, b.unlock.target)), tgt = compact(b.unlock.target)
        return "\(b.unlock.metric) \(cur)/\(tgt)"
    }

    /// 25000 → "25k" for tight tiles.
    private func compact(_ n: Int) -> String { n >= 1000 ? "\(n / 1000)k" : "\(n)" }
}

/// Fades & slides a menu item in once its turn arrives (`shown` > `index`).
private struct Stagger: ViewModifier {
    let shown: Int, index: Int
    init(_ shown: Int, _ index: Int) { self.shown = shown; self.index = index }
    func body(content: Content) -> some View {
        content
            .opacity(shown > index ? 1 : 0)
            .offset(y: shown > index ? 0 : 14)
    }
}

#Preview {
    RootView()
}
