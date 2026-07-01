//
//  GameCanvas.swift
//  Tiny Tide — turns the GameModel's state into a frame, using GameArt for every shape.
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

            var ctx = ctx
            if model.shakeAmp > 0.05 {        // impact shake — jolts the world (HUD stays put)
                let s = model.shakeAmp, t = model.elapsed
                ctx.translateBy(x: sin(t * 119) * s, y: cos(t * 97) * s)
            }

            GameArt.drawWater(ctx, size, scroll: model.scroll, timeOfDay: model.timeOfDay)

            // Soft cloud shadows drift across the surface, under everything else.
            GameArt.drawCloudShadows(ctx, size, scroll: model.scroll)

            // The kraken darkens the deep and looms behind the boat.
            if model.phase == .kraken {
                GameArt.drawKrakenMurk(ctx, size, t: model.elapsed, emerge: model.krakenEmerge)
            }

            // The Boot Beast looms behind the boat.
            if model.phase == .bootBeast {
                GameArt.drawBootBeast(ctx, size, t: model.elapsed, emerge: model.bootBeastEmerge)
            }

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

            // While aiming: the line going out + the aim marker — only after the rod has whipped
            // forward (during the wind-up castReach is still 0, so nothing shows yet).
            if model.phase == .casting && model.castReach > 0 {
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

            // The towing fish + taut line during a sleigh ride (drawn under the boat).
            if model.phase == .sleighRide {
                GameArt.drawSleigh(ctx, size, fishX: model.towFishX, fishY: model.towFishY,
                                   boatX: model.boatX, boatY: model.boatY,
                                   strain: model.sleighStrain, t: model.elapsed)
            }

            GameArt.drawBoat(ctx, size, x: model.boatX, boatY: model.boatY,
                             wake: model.wakeTrail, t: model.elapsed, speed: model.boatSpeed,
                             timeOfDay: model.timeOfDay, hull: model.boat.hull, accent: model.boat.accent,
                             style: model.boat.style, shiny: model.boat.shiny,
                             casting: model.phase == .casting, castT: model.castT)

            // A newly-unlocked boat doing its celebratory lap, flying its name.
            if let cameo = model.cameoBoat {
                GameArt.drawCameoBoat(ctx, size, boat: cameo, x: model.cameoX, y: model.cameoY,
                                      t: model.elapsed, name: model.cameoName)
            }

            // The gull itself flies over the top of everything — straight across, or diving for a fish.
            if model.birdActive {
                GameArt.drawBird(ctx, size, progress: model.birdProgress, dir: model.birdDir,
                                 t: model.elapsed, dive: model.birdDive,
                                 diveX: model.birdDiveTargetX, diveY: model.birdDiveTargetY,
                                 xOffset: model.birdXOffset, shadows: false)
            }

            // Feathers knocked loose by a clipped gull, fluttering down over the water.
            for f in model.feathers { GameArt.drawFeather(ctx, size, f, dur: model.featherDuration) }

            // Kraken tentacles slam over the top of the boat; your harpoons fly up at it.
            if model.phase == .kraken {
                GameArt.drawKrakenStrikes(ctx, size, tentacles: model.tentacles)
                GameArt.drawHarpoons(ctx, size, harpoons: model.harpoons)
                if model.harpoonHitActive {
                    GameArt.drawHarpoonImpact(ctx, size, x: model.harpoonHitX, y: model.harpoonHitY,
                                              progress: model.harpoonHitT / 0.35)
                }
            }

            // Boots the beast lobs at you, over the top of the boat.
            if model.phase == .bootBeast {
                GameArt.drawBootThrows(ctx, size, throws: model.bootThrows)
            }

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
