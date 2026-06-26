//
//  GameCanvas.swift
//  Wristfish — turns the GameModel's state into a frame, using GameArt for every shape.
//

import SwiftUI

struct GameCanvas: View {
    @ObservedObject var model: GameModel

    var body: some View {
        Canvas { ctx, size in
            // The reel, plus its "Fish on!" and catch/loss transitions, use the first-person view.
            if model.phase == .reeling || model.phase == .hooking || model.phase == .surfacing {
                GameArt.drawReelingFP(ctx, size, model: model)
                return
            }

            GameArt.drawWater(ctx, size, scroll: model.scroll, timeOfDay: model.timeOfDay)

            // Soft cloud shadows drift across the surface, under everything else.
            GameArt.drawCloudShadows(ctx, size, scroll: model.scroll)

            if model.phase == .launching {
                GameArt.drawHarbor(ctx, size, offset: model.harborOffset)
            }

            // The gull's shadow glides across the water, beneath the obstacles.
            if model.birdActive {
                GameArt.drawBird(ctx, size, progress: model.birdProgress, dir: model.birdDir,
                                 t: model.elapsed, dive: model.birdDive,
                                 diveX: model.birdDiveTargetX, diveY: model.birdDiveTargetY,
                                 xOffset: model.birdXOffset, shadows: true)
            }

            for hint in model.hints { GameArt.drawRipple(ctx, size, hint) }
            for o in model.rocks {
                switch o.kind {
                case .rock:       GameArt.drawRock(ctx, size, o, t: model.elapsed)
                case .lighthouse: GameArt.drawLighthouse(ctx, size, o, t: model.elapsed)
                case .boat:       GameArt.drawDriftBoat(ctx, size, o, t: model.elapsed)
                }
            }
            // Rocks bursting apart where the pickaxe cleaved them.
            for sh in model.shatters { GameArt.drawShatter(ctx, size, sh, dur: model.shatterDuration) }
            // Fish leaping out of the water (above the surface).
            for leap in model.leaps { GameArt.drawLeap(ctx, size, leap, dur: model.leapDuration) }

            // The finish line — a fixed spot that scrolls in; drawn under the boat so you cross it.
            if let fy = model.finishLineY {
                GameArt.drawFinishLine(ctx, size, y: fy, t: model.elapsed,
                                       near: min(1, max(0, fy / model.boatY)))
            }

            // While aiming: the line going out + the aim marker (gold when locked on a fish).
            if model.phase == .casting {
                GameArt.drawLine(ctx, size, from: model.boatX, boatY: model.boatY,
                                 to: model.hookPoint, tension: 0)
                GameArt.drawAim(ctx, size, at: model.hookPoint, locked: model.castLocked, t: model.elapsed)
            }

            // The diving gull's splash erupts right where it hits the fish.
            if model.birdActive && model.birdDive {
                let sp = (model.birdProgress - 0.62) / 0.20
                if sp > 0 && sp < 1 {
                    GameArt.drawSplash(ctx, size, x: model.birdDiveTargetX, y: model.birdDiveTargetY, progress: sp)
                }
            }

            GameArt.drawBoat(ctx, size, x: model.boatX, boatY: model.boatY,
                             wake: model.wakeTrail, t: model.elapsed, speed: model.boatSpeed,
                             timeOfDay: model.timeOfDay)

            // The gull itself flies over the top of everything — straight across, or diving for a fish.
            if model.birdActive {
                GameArt.drawBird(ctx, size, progress: model.birdProgress, dir: model.birdDir,
                                 t: model.elapsed, dive: model.birdDive,
                                 diveX: model.birdDiveTargetX, diveY: model.birdDiveTargetY,
                                 xOffset: model.birdXOffset, shadows: false)
            }

            // Feathers knocked loose by a clipped gull, fluttering down over the water.
            for f in model.feathers { GameArt.drawFeather(ctx, size, f, dur: model.featherDuration) }

            if model.phase == .crashing {
                if model.crashIsMine {
                    GameArt.drawExplosion(ctx, size, x: model.crashX, y: model.crashY,
                                          progress: model.crashProgress)
                } else {
                    GameArt.drawSplash(ctx, size, x: model.crashX, y: model.crashY,
                                       progress: model.crashProgress)
                }
            }
        }
    }
}
