//
//  GameArt.swift
//  Wristfish — ALL the drawing lives here.
//
//  🎨 This is the file to repaint. Every shape is a small, self-contained function drawn with
//  simple paths + colours from `Sea` (Theme.swift). Tweak a shape, a colour, a size — nothing
//  else in the game needs to change. Coordinates are normalized 0…1; `p(x,y,size)` maps them
//  to pixels so art stays resolution-independent across watch sizes.
//

import SwiftUI

enum GameArt {

    /// Normalized (0…1) → pixel point.
    private static func p(_ x: Double, _ y: Double, _ s: CGSize) -> CGPoint {
        CGPoint(x: x * s.width, y: y * s.height)
    }

    // MARK: Time of day ------------------------------------------------------

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// The (shallow, water, deep) water colours for a time of day (0 = bright day → 1 = deep night),
    /// blended through four key frames: day → golden hour → dusk → night.
    static func seaColors(_ tod: Double) -> (shallow: Color, water: Color, deep: Color) {
        typealias Key = (pos: Double, sh: (Double, Double, Double),
                         wa: (Double, Double, Double), de: (Double, Double, Double))
        let keys: [Key] = [
            (0.00, (0.10, 0.40, 0.55), (0.06, 0.22, 0.40), (0.03, 0.09, 0.18)),  // day
            (0.45, (0.60, 0.46, 0.34), (0.30, 0.25, 0.33), (0.09, 0.08, 0.17)),  // golden hour
            (0.72, (0.42, 0.28, 0.44), (0.18, 0.15, 0.32), (0.05, 0.05, 0.14)),  // dusk
            (1.00, (0.09, 0.16, 0.30), (0.03, 0.07, 0.17), (0.01, 0.02, 0.07)),  // night
        ]
        let c = min(1, max(0, tod))
        var lo = keys[0], hi = keys[keys.count - 1]
        for i in 0..<(keys.count - 1) where c >= keys[i].pos && c <= keys[i + 1].pos {
            lo = keys[i]; hi = keys[i + 1]; break
        }
        let span = hi.pos - lo.pos
        let f = span > 0 ? (c - lo.pos) / span : 0
        func blend(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Color {
            Color(red: mix(a.0, b.0, f), green: mix(a.1, b.1, f), blue: mix(a.2, b.2, f))
        }
        return (blend(lo.sh, hi.sh), blend(lo.wa, hi.wa), blend(lo.de, hi.de))
    }

    /// How deep into night it is (0 until dusk, ramping to 1) — drives dimming, moonlight & wake glow.
    static func nightAmount(_ tod: Double) -> Double { max(0, min(1, (tod - 0.6) / 0.4)) }
    /// A bump that peaks around sunset — drives the warm horizon glow.
    private static func sunsetAmount(_ tod: Double) -> Double { max(0, 1 - abs(tod - 0.56) / 0.34) }

    /// A few faint little V-wakes drifting down the water — ambient life for the menu header (no obstacles).
    static func drawAmbientWake(_ ctx: GraphicsContext, _ s: CGSize, t: Double) {
        let w = s.width, h = s.height
        for i in 0..<5 {
            let hx = Double((i * 61 + 13) % 100) / 100
            let speed = 0.30 + Double(i % 3) * 0.12
            let prog = (t * speed + Double(i) * 0.23).truncatingRemainder(dividingBy: 1)
            let cy = prog * h
            let cx = (hx + 0.02 * sin(t * 0.5 + Double(i))) * w
            let fade = sin(prog * .pi)                      // fade in at the top, out at the bottom
            guard fade > 0 else { continue }
            let sz = (0.05 + 0.02 * Double(i % 2)) * h
            for side in [-1.0, 1.0] {                       // a little diverging V wake
                var p = Path()
                p.move(to: CGPoint(x: cx, y: cy))
                p.addLine(to: CGPoint(x: cx + side * sz * 0.5, y: cy + sz))
                ctx.stroke(p, with: .color(Sea.foam.opacity(0.16 * fade)), lineWidth: 1.5)
            }
        }
    }

    // MARK: Water background -------------------------------------------------

    /// An irregular soft "blob" outline (a wobbled circle) — clips caustic light into organic shapes.
    private static func causticBlob(r: Double, seed: Int) -> Path {
        var path = Path()
        let pts = 14
        let ph = Double(seed) * 0.7
        for k in 0...pts {
            let a = Double(k) / Double(pts) * 2 * .pi
            let rr = r * (1 + 0.24 * sin(a * 2 + ph) + 0.15 * sin(a * 3 + ph * 1.6))
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if k == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    static func drawWater(_ ctx: GraphicsContext, _ s: CGSize, scroll: Double, timeOfDay tod: Double = 0) {
        let w = s.width, h = s.height
        let pal = seaColors(tod)
        let night = nightAmount(tod)
        let sunset = sunsetAmount(tod)
        let dim = 1 - 0.55 * night                                  // caustics & glints fade after dark

        // 1) Depth gradient.
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(
            Gradient(colors: [pal.shallow, pal.water, pal.deep]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))

        // 1a) A warm sky glow spilling across the far water around sunset.
        if sunset > 0.01 {
            let warm = Color(red: 1.0, green: 0.58, blue: 0.34)
            ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h * 0.55)), with: .linearGradient(
                Gradient(colors: [warm.opacity(0.32 * sunset), .clear]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.45)))
        }

        // 1b) Depth — darker organic patches drifting slowly underneath, suggesting deeper water.
        let depths = 14
        for i in 0..<depths {
            let hx = Double((i * 61 + 29) % 100) / 100.0
            let hsz = Double((i * 41 + 13) % 100) / 100.0
            let speed = 0.16 + Double(i % 4) * 0.04                 // slower than caustics (parallax)
            let cy = (Double(i) / Double(depths) + scroll * speed).truncatingRemainder(dividingBy: 1)
            let cyP = cy * 1.2 - 0.1
            let edgeFade = min(cyP * 4, (1 - cyP) * 4)
            guard edgeFade > 0 else { continue }
            let cx = (hx + 0.02 * sin(scroll * 0.4 + Double(i) * 1.7)) * w
            let rad = (0.10 + 0.10 * hsz) * w                       // larger, softer patches
            let op = 0.10 * min(1, edgeFade)                        // subtle
            let angle = (Double((i * 37 + 7) % 100) / 100.0 - 0.5) * 1.4
            let elongX = 0.9 + 0.6 * Double((i * 59 + 19) % 100) / 100.0
            let squashY = 0.40 + 0.40 * Double((i * 23 + 5) % 100) / 100.0
            var c = ctx
            c.translateBy(x: cx, y: cyP * h)
            c.rotate(by: .radians(angle))
            c.scaleBy(x: elongX, y: squashY)
            c.clip(to: causticBlob(r: rad, seed: i + 50))          // different irregular shapes
            c.fill(Path(CGRect(x: -rad * 1.6, y: -rad * 1.6, width: rad * 3.2, height: rad * 3.2)),
                   with: .radialGradient(Gradient(colors: [pal.deep.opacity(op), .clear]),
                                         center: .zero, startRadius: 0, endRadius: rad * 1.05))
        }

        // 2) Caustics — soft horizontal light streaks drifting down, gently pulsing.
        let caustic = Color(red: 0.52, green: 0.92, blue: 1.0)
        let pools = 22
        for i in 0..<pools {
            let hx = Double((i * 73 + 17) % 100) / 100.0          // stable scattered x
            let hsz = Double((i * 31 + 7) % 100) / 100.0          // size variation
            let speed = 0.26 + Double(i % 5) * 0.06
            let cy = (Double(i) / Double(pools) + scroll * speed).truncatingRemainder(dividingBy: 1)
            let cyP = cy * 1.18 - 0.09                            // extend a touch past the edges
            let edgeFade = min(cyP * 4, (1 - cyP) * 4)           // fade near top/bottom (no wrap pop)
            guard edgeFade > 0 else { continue }
            let pulse = 0.5 + 0.5 * sin(scroll * 1.6 + Double(i) * 1.3)
            let cx = (hx + 0.02 * sin(scroll * 0.6 + Double(i))) * w
            let rad = (0.07 + 0.08 * hsz) * w
            let op = 0.11 * (0.4 + 0.6 * pulse) * min(1, edgeFade) * dim     // subtler than before, fades after dark
            // Each caustic gets its own tilt, length and flatness → varied shapes.
            let angle = (Double((i * 47 + 11) % 100) / 100.0 - 0.5) * 1.4    // ±0.7 rad
            let elongX = 0.85 + 0.7 * Double((i * 53 + 9) % 100) / 100.0
            let squashY = 0.30 + 0.45 * Double((i * 29 + 3) % 100) / 100.0
            var c = ctx
            c.translateBy(x: cx, y: cyP * h)
            c.rotate(by: .radians(angle))
            c.scaleBy(x: elongX, y: squashY)
            c.clip(to: causticBlob(r: rad, seed: i))                        // irregular, non-round outline
            c.fill(Path(CGRect(x: -rad * 1.6, y: -rad * 1.6, width: rad * 3.2, height: rad * 3.2)),
                   with: .radialGradient(Gradient(colors: [caustic.opacity(op), .clear]),
                                         center: .zero, startRadius: 0, endRadius: rad * 1.05))
        }

        // 4) Sparkles — tiny bright glints drifting down.
        let glints = 16
        for i in 0..<glints {
            let gx = Double((i * 53) % 97) / 97.0 * w
            let speed = 0.18 + Double(i % 4) * 0.06
            let gy = (Double(i) * 0.131 + scroll * speed).truncatingRemainder(dividingBy: 1) * h
            let r = 0.9 + Double(i % 3) * 0.7
            ctx.fill(Path(ellipseIn: CGRect(x: gx - r, y: gy - r, width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(0.18 * dim)))
        }

        // 4b) After dark: a shimmering moon-reflection column + brighter star-glints on the water.
        if night > 0.05 {
            let moonX = w * 0.62
            for k in 0..<11 {
                let yy = ((Double(k) * 0.1 + scroll * 0.3).truncatingRemainder(dividingBy: 1)) * h
                let ww = (0.05 + 0.03 * sin(scroll * 2 + Double(k))) * w
                let op = 0.12 * night * (0.5 + 0.5 * sin(scroll * 3 + Double(k) * 1.7))
                ctx.fill(Path(ellipseIn: CGRect(x: moonX - ww / 2, y: yy - 2, width: ww, height: 3)),
                         with: .color(Color(red: 0.85, green: 0.90, blue: 1.0).opacity(op)))
            }
            for i in 0..<14 {
                let gx = Double((i * 61) % 97) / 97.0 * w
                let speed = 0.10 + Double(i % 4) * 0.04
                let gy = (Double(i) * 0.137 + scroll * speed).truncatingRemainder(dividingBy: 1) * h
                let tw = 0.5 + 0.5 * sin(scroll * 4 + Double(i))
                let r = 0.8 + 0.8 * tw
                ctx.fill(Path(ellipseIn: CGRect(x: gx - r, y: gy - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity((0.10 + 0.22 * tw) * night)))
            }
        }

        // 5) Soft vignette for depth.
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
            Gradient(colors: [.clear, pal.deep.opacity(0.35 + 0.25 * night)]),
            center: CGPoint(x: w * 0.5, y: h * 0.5), startRadius: w * 0.32, endRadius: w * 0.85))
    }

    /// Big, soft cloud shadows drifting slowly across the water (high parallax) — atmosphere.
    static func drawCloudShadows(_ ctx: GraphicsContext, _ s: CGSize, scroll: Double) {
        let w = s.width, h = s.height
        let n = 3
        for i in 0..<n {
            let speed = 0.07 + Double(i) * 0.02                         // slow — they sit "up high"
            let cy = (Double(i) / Double(n) + scroll * speed).truncatingRemainder(dividingBy: 1)
            let cyP = cy * 1.3 - 0.15
            let edge = min(cyP * 3, (1 - cyP) * 3)                      // fade in/out top & bottom
            guard edge > 0 else { continue }
            let cx = (Double((i * 47 + 15) % 100) / 100.0 + 0.04 * sin(scroll * 0.3 + Double(i))) * w
            let rad = (0.34 + 0.12 * Double((i * 31) % 100) / 100.0) * w
            var g = ctx
            g.translateBy(x: cx, y: cyP * h)
            g.scaleBy(x: 1.5, y: 0.8)
            g.rotate(by: .radians(Double((i * 29) % 100) / 100.0 - 0.5))
            g.clip(to: causticBlob(r: rad, seed: i + 200))             // organic cloud outline
            g.fill(Path(CGRect(x: -rad * 1.7, y: -rad * 1.7, width: rad * 3.4, height: rad * 3.4)),
                   with: .radialGradient(Gradient(colors: [Sea.deep.opacity(0.12 * min(1, edge)), .clear]),
                                         center: .zero, startRadius: 0, endRadius: rad * 1.05))
        }
    }

    // MARK: Fish-here ripples -----------------------------------------------

    static func drawRipple(_ ctx: GraphicsContext, _ s: CGSize, _ h: Hint, alpha: Double = 1) {
        let center = p(h.x, h.y, s)
        let tint = h.deep ? Sea.blue : Sea.teal
        let baseR = (h.deep ? 0.085 : 0.055) * s.width

        // Two pulsing rings.
        for k in 0..<2 {
            let t = (h.phase * 0.9 + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
            let r = baseR * (0.5 + t)
            let ring = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r * 0.6,
                                              width: r * 2, height: r * 1.2))
            ctx.stroke(ring, with: .color(tint.opacity(0.5 * (1 - t) * alpha)), lineWidth: h.deep ? 2 : 1.5)
        }
        // Deep spots show a dark fish shadow drifting under the surface.
        if h.deep {
            let shadow = Path(ellipseIn: CGRect(x: center.x - baseR * 0.5, y: center.y - baseR * 0.2,
                                                width: baseR, height: baseR * 0.45))
            ctx.fill(shadow, with: .color(Sea.deep.opacity(0.55 * alpha)))
        }
        // Centre glint.
        let dot = Path(ellipseIn: CGRect(x: center.x - 2, y: center.y - 2, width: 4, height: 4))
        ctx.fill(dot, with: .color(tint.opacity(0.8 * alpha)))
    }

    /// Fish ripples drifting down in front of the menu boat — occasional, fading in & out.
    static func drawMenuRipples(_ ctx: GraphicsContext, _ s: CGSize, t: Double, fade: Double = 1) {
        for i in 0..<3 {
            let speed = 0.16 + Double(i) * 0.05
            let prog = (t * speed + Double(i) * 0.41).truncatingRemainder(dividingBy: 1)
            let y = -0.05 + prog * 0.62                 // from above the boat, drifting down past it
            let x = 0.5 + (Double(i) - 1) * 0.18        // near the boat's lane
            drawRipple(ctx, s, Hint(x: x, y: y, deep: i % 2 == 0, phase: t), alpha: 0.9 * sin(prog * .pi) * fade)
        }
    }

    // MARK: Leaping fish (ambient) ------------------------------------------

    /// A small foam burst — used where a leaping fish leaves and re-enters the water.
    private static func miniSplash(_ ctx: GraphicsContext, _ s: CGSize, at c: CGPoint, prog: Double) {
        let r = (0.01 + prog * 0.03) * s.width
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.5, width: r * 2, height: r)),
                   with: .color(Sea.foam.opacity(0.55 * (1 - prog))), lineWidth: 1.4)
        for i in 0..<5 {
            let a = -Double.pi * 0.9 + Double(i) / 4 * Double.pi * 0.8
            let d = r * 1.2
            let dx = c.x + cos(a) * d, dy = c.y + sin(a) * d - prog * 0.012 * s.height
            let sz = max(1, 3 * (1 - prog))
            ctx.fill(Path(ellipseIn: CGRect(x: dx - sz / 2, y: dy - sz / 2, width: sz, height: sz)),
                     with: .color(Sea.foam.opacity(1 - prog)))
        }
    }

    /// A fish arcing out of the water and splashing back — a brief flourish. `dur` = leap length.
    static func drawLeap(_ ctx: GraphicsContext, _ s: CGSize, _ l: Leap, dur: Double) {
        let p = min(1, l.age / dur)
        let base = CGPoint(x: l.x * s.width, y: l.y * s.height)
        let arcW = 0.055 * s.width, arcH = 0.065 * s.height
        let pos = CGPoint(x: base.x + l.dir * arcW * p, y: base.y - arcH * sin(p * .pi))
        let entry = CGPoint(x: base.x + l.dir * arcW, y: base.y)
        let heading = atan2(-arcH * .pi * cos(p * .pi), l.dir * arcW)
        let sz = 0.052 * s.width
        let silver = Color(red: 0.80, green: 0.86, blue: 0.92)

        // Shadow gliding on the water beneath the fish.
        let shx = base.x + l.dir * arcW * p
        ctx.fill(Path(ellipseIn: CGRect(x: shx - sz * 0.4, y: base.y - sz * 0.1,
                                        width: sz * 0.8, height: sz * 0.22)),
                 with: .color(Sea.deep.opacity(0.18 * max(0, 1 - abs(0.5 - p) * 1.6))))

        // The fish (banked along its arc).
        var g = ctx
        g.translateBy(x: pos.x, y: pos.y)
        g.rotate(by: .radians(heading))
        g.fill(Path(ellipseIn: CGRect(x: -sz * 0.5, y: -sz * 0.17, width: sz, height: sz * 0.34)),
               with: .color(silver))
        g.fill(Path(ellipseIn: CGRect(x: -sz * 0.42, y: -sz * 0.02, width: sz * 0.7, height: sz * 0.13)),
               with: .color(.white.opacity(0.55)))                       // belly sheen
        var tail = Path()
        tail.move(to: CGPoint(x: -sz * 0.46, y: 0))
        tail.addLine(to: CGPoint(x: -sz * 0.64, y: -sz * 0.15))
        tail.addLine(to: CGPoint(x: -sz * 0.64, y: sz * 0.15))
        tail.closeSubpath()
        g.fill(tail, with: .color(silver.opacity(0.85)))
        g.fill(Path(ellipseIn: CGRect(x: sz * 0.3, y: -sz * 0.05, width: sz * 0.08, height: sz * 0.08)),
               with: .color(.black.opacity(0.7)))                        // eye

        // Splash leaving the water, then splashing back in.
        if p < 0.22 { miniSplash(ctx, s, at: base, prog: p / 0.22) }
        if p > 0.78 { miniSplash(ctx, s, at: entry, prog: (p - 0.78) / 0.22) }
    }

    // MARK: Rocks ------------------------------------------------------------

    private static func hash01(_ n: Int) -> Double {
        let x = sin(Double(n) * 12.9898) * 43_758.5453
        return x - floor(x)
    }

    private static let foamLight = Color(red: 0.80, green: 0.93, blue: 0.99)
    private static let rockLight = Color(red: 0.55, green: 0.58, blue: 0.63)
    private static let rockDark  = Color(red: 0.30, green: 0.32, blue: 0.37)

    /// A soft, rounded rock silhouette — a jittered blob with rounded corners, fixed by the seed.
    private static func rockShape(_ c: CGPoint, _ r: Double, seed: Int) -> Path {
        let n = 6 + seed % 3                                  // 6…8 lobes
        let rot = hash01(seed) * 2 * .pi
        var pts: [CGPoint] = []
        for k in 0..<n {
            let a = rot + Double(k) / Double(n) * 2 * .pi
            let jit = 0.82 + 0.30 * hash01(seed * 31 + k * 17)
            pts.append(CGPoint(x: c.x + cos(a) * r * jit, y: c.y + sin(a) * r * jit * 0.9))
        }
        func mid(_ i: Int, _ j: Int) -> CGPoint {
            CGPoint(x: (pts[i].x + pts[j].x) / 2, y: (pts[i].y + pts[j].y) / 2)
        }
        // Curve through the midpoints, using each vertex as a control point → rounded corners.
        var path = Path()
        path.move(to: mid(n - 1, 0))
        for k in 0..<n { path.addQuadCurve(to: mid(k, (k + 1) % n), control: pts[k]) }
        path.closeSubpath()
        return path
    }

    static func drawRock(_ ctx: GraphicsContext, _ s: CGSize, _ o: Obstacle, t: Double) {
        let c = p(o.x, o.y, s)
        let r = o.r * s.width

        // Water breaking around the rock — a foam edge in the rock's exact shape, pulsing weakly.
        let pn = 0.5 + 0.5 * sin(t * 1.8 + hash01(o.seed) * 6.28)     // 0…1 gentle pulse
        let foam = rockShape(c, r * (1.05 + 0.05 * pn), seed: o.seed)
        ctx.stroke(foam, with: .color(foamLight.opacity(0.05 + 0.05 * pn)), lineWidth: 4)   // soft glow
        ctx.stroke(foam, with: .color(foamLight.opacity(0.14 + 0.12 * pn)), lineWidth: 1.5) // crest

        // Rock body with a soft top→bottom shade for a rounded stone.
        let body = rockShape(c, r, seed: o.seed)
        ctx.fill(body, with: .linearGradient(Gradient(colors: [rockLight, rockDark]),
                                             startPoint: CGPoint(x: c.x, y: c.y - r),
                                             endPoint: CGPoint(x: c.x, y: c.y + r)))
        // Lit top + a soft outline (no harsh black).
        let hi = rockShape(CGPoint(x: c.x - r * 0.15, y: c.y - r * 0.22), r * 0.6, seed: o.seed)
        ctx.fill(hi, with: .color(.white.opacity(0.12)))
        ctx.stroke(body, with: .color(rockDark.opacity(0.5)), lineWidth: 1)
    }

    // MARK: Lighthouse (rarer obstacle — a skerry with a sweeping beacon) -----

    static func drawLighthouse(_ ctx: GraphicsContext, _ s: CGSize, _ o: Obstacle, t: Double) {
        let c = p(o.x, o.y, s)
        let r = o.r * s.width
        let glassY = Color(red: 1.0, green: 0.92, blue: 0.58)   // warm beacon light
        let pulse  = 0.5 + 0.5 * sin(t * 3.0)                   // the lamp throbs

        // Water breaking around the skerry — a foam edge in the rock's shape, gently pulsing.
        let pn = 0.5 + 0.5 * sin(t * 1.8 + hash01(o.seed) * 6.28)
        let foam = rockShape(c, r * (1.05 + 0.05 * pn), seed: o.seed)
        ctx.stroke(foam, with: .color(foamLight.opacity(0.06 + 0.05 * pn)), lineWidth: 4)
        ctx.stroke(foam, with: .color(foamLight.opacity(0.14 + 0.10 * pn)), lineWidth: 1.5)

        // Skerry rock it stands on, with a darker wet rim at the waterline.
        let base = rockShape(c, r, seed: o.seed)
        ctx.fill(base, with: .linearGradient(Gradient(colors: [rockLight, rockDark]),
                                             startPoint: CGPoint(x: c.x, y: c.y - r),
                                             endPoint: CGPoint(x: c.x, y: c.y + r)))
        ctx.stroke(base, with: .color(rockDark.opacity(0.55)), lineWidth: 2)

        // Two opposite light beams sweeping around the lamp (soft, brightening with the pulse).
        let len = r * 3.2, halfW = 0.17, ang = t * 1.1
        var bc = ctx
        bc.addFilter(.blur(radius: r * 0.2))
        for k in 0..<2 {
            let a = ang + Double(k) * .pi
            var beam = Path()
            beam.move(to: c)
            beam.addLine(to: CGPoint(x: c.x + cos(a - halfW) * len, y: c.y + sin(a - halfW) * len))
            beam.addLine(to: CGPoint(x: c.x + cos(a) * len * 1.1, y: c.y + sin(a) * len * 1.1))
            beam.addLine(to: CGPoint(x: c.x + cos(a + halfW) * len, y: c.y + sin(a + halfW) * len))
            beam.closeSubpath()
            bc.fill(beam, with: .radialGradient(
                Gradient(colors: [glassY.opacity(0.42 * (0.7 + 0.3 * pulse)), .clear]),
                center: c, startRadius: r * 0.3, endRadius: len))
        }
        // Soft halo around the lamp.
        let gr = r * (1.5 + 0.25 * pulse)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)),
                 with: .radialGradient(Gradient(colors: [glassY.opacity(0.16 + 0.12 * pulse), .clear]),
                                       center: c, startRadius: r * 0.5, endRadius: gr))

        // --- The tower, seen from above ---------------------------------------
        let tr = r * 0.62
        func ring(_ rad: Double) -> Path { Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)) }
        let lit = CGPoint(x: c.x - tr * 0.4, y: c.y - tr * 0.4)   // light comes from the upper-left

        // Drop shadow of the tower onto the rock.
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - tr + r * 0.05, y: c.y - tr + r * 0.08,
                                        width: tr * 2, height: tr * 2)),
                 with: .color(.black.opacity(0.22)))
        // White tower wall, shaded round for a 3-D feel.
        ctx.fill(ring(tr), with: .radialGradient(Gradient(colors: [.white, Color(white: 0.66)]),
                                                 center: lit, startRadius: 0, endRadius: tr * 1.9))
        ctx.stroke(ring(tr), with: .color(.black.opacity(0.22)), lineWidth: 1)

        // Red gallery ring (the painted walkway), with a soft sheen.
        let rr = tr * 0.72
        ctx.fill(ring(rr), with: .color(Sea.coral))
        ctx.fill(ring(rr), with: .radialGradient(Gradient(colors: [.white.opacity(0.22), .clear]),
                                                 center: lit, startRadius: 0, endRadius: rr * 1.7))

        // Railing posts around the gallery deck.
        let railR = tr * 0.88, posts = 10
        for i in 0..<posts {
            let a = Double(i) / Double(posts) * 2 * .pi
            let pp = CGPoint(x: c.x + cos(a) * railR, y: c.y + sin(a) * railR)
            ctx.fill(Path(ellipseIn: CGRect(x: pp.x - 1.3, y: pp.y - 1.3, width: 2.6, height: 2.6)),
                     with: .color(.black.opacity(0.35)))
        }

        // Lantern room (glass), with radial glazing bars.
        let lr = tr * 0.48
        ctx.fill(ring(lr), with: .color(Color(red: 0.84, green: 0.91, blue: 0.96)))
        for i in 0..<6 {
            let a = Double(i) / 6 * 2 * .pi
            var bar = Path()
            bar.move(to: CGPoint(x: c.x + cos(a) * lr * 0.25, y: c.y + sin(a) * lr * 0.25))
            bar.addLine(to: CGPoint(x: c.x + cos(a) * lr, y: c.y + sin(a) * lr))
            ctx.stroke(bar, with: .color(.black.opacity(0.18)), lineWidth: 0.8)
        }

        // The glowing lamp at the centre.
        let cr = lr * 0.62
        ctx.fill(ring(cr * (1.0 + 0.12 * pulse)),
                 with: .radialGradient(Gradient(colors: [.white, glassY, glassY.opacity(0)]),
                                       center: c, startRadius: 0, endRadius: cr * 1.6))
        // A little lens sparkle on the bright half of the pulse.
        let spark = max(0, (pulse - 0.45) / 0.55)
        if spark > 0 {
            let sl = cr * (1.5 + 1.3 * spark)
            for a in stride(from: 0.0, to: .pi, by: .pi / 2) {
                var ray = Path()
                ray.move(to: CGPoint(x: c.x - cos(a) * sl, y: c.y - sin(a) * sl))
                ray.addLine(to: CGPoint(x: c.x + cos(a) * sl, y: c.y + sin(a) * sl))
                ctx.stroke(ray, with: .color(.white.opacity(0.55 * spark)), lineWidth: 1)
            }
        }
    }

    // MARK: Shared boat look (used by every boat — player, harbour, drifting) -

    /// A proper boat hull seen from above: a sharp bow at −y, a flat wide transom (stern) at +y.
    /// `hw`/`hh` are the half-width / half-length.
    private static func hullShape(_ hw: Double, _ hh: Double) -> Path { hullShape(.skiff, hw, hh) }

    /// Per-style hull proportions: width, length, bow sharpness (0 round → 1 pointed), stern width.
    private static func hullParams(_ style: BoatStyle) -> (w: Double, l: Double, bow: Double, stern: Double) {
        switch style {
        case .skiff:     return (1.00, 1.00, 0.00, 0.66)
        case .motorboat: return (0.94, 1.02, 0.35, 0.58)
        case .trawler:   return (1.16, 0.96, 0.12, 0.84)
        case .voyager:   return (0.84, 1.10, 0.70, 0.50)
        case .speedboat: return (0.78, 1.12, 0.95, 0.50)
        case .sailboat:  return (0.66, 1.12, 0.85, 0.34)
        case .yacht:     return (0.82, 1.14, 0.80, 0.46)
        case .boot:      return (1.06, 1.00, 0.15, 0.80)
        case .barge:     return (1.05, 1.00, 0.00, 1.00)
        }
    }

    /// A hull silhouette for a given style — a sharper bow & narrower stern read very differently.
    private static func hullShape(_ style: BoatStyle, _ hw: Double, _ hh: Double) -> Path {
        if style == .barge {        // a boxy, flat-fronted barge
            return Path(roundedRect: CGRect(x: -hw * 1.05, y: -hh * 0.92, width: hw * 2.10, height: hh * 1.84),
                        cornerSize: CGSize(width: hw * 0.30, height: hw * 0.30))
        }
        let pm = hullParams(style)
        let HW = hw * pm.w, HH = hh * pm.l
        let cBowX = HW * (0.92 - 0.55 * pm.bow)
        let cBowY = -HH * (0.66 + 0.22 * pm.bow)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -HH))                                          // bow tip
        p.addQuadCurve(to: CGPoint(x: HW, y: HH * 0.10), control: CGPoint(x: cBowX, y: cBowY))
        p.addQuadCurve(to: CGPoint(x: HW * pm.stern, y: HH), control: CGPoint(x: HW, y: HH * 0.66))
        p.addLine(to: CGPoint(x: -HW * pm.stern, y: HH))                           // flat transom
        p.addQuadCurve(to: CGPoint(x: -HW, y: HH * 0.10), control: CGPoint(x: -HW, y: HH * 0.66))
        p.addQuadCurve(to: CGPoint(x: 0, y: -HH), control: CGPoint(x: -cBowX, y: cBowY))
        p.closeSubpath()
        return p
    }

    /// The one boat style for the whole game (player, harbour, drifting): a painted hull with a
    /// flat stern, a wooden gunwale/deck, a covered foredeck, an open cockpit with thwart seats,
    /// and a little outboard at the transom. Drawn centred at `c`, bow up, banked by `bank`.
    private static func boatBody(_ ctx: GraphicsContext, at c: CGPoint, hw: Double, hh: Double,
                                 bank: Double, hull: Color, accent: Color = Sea.coral,
                                 style: BoatStyle = .skiff, motor: Bool = true) {
        let deck = Color(red: 0.82, green: 0.70, blue: 0.50)   // sun-bleached wooden gunwale/deck
        let well = Color(red: 0.55, green: 0.43, blue: 0.30)   // shaded open interior
        let seat = Color(red: 0.71, green: 0.57, blue: 0.39)   // thwart seats
        let wf = (style == .barge) ? 1.05 : hullParams(style).w   // effective half-width for this style
        let ew = hw * wf
        let sl = hh * hullParams(style).l                         // effective half-length for superstructure
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(bank))

        // Soft drop shadow under the hull.
        var sc = g
        sc.translateBy(x: 0, y: hh * 0.10)
        sc.addFilter(.blur(radius: hw * 0.5))
        sc.fill(hullShape(style, hw * 1.04, hh * 1.03), with: .color(.black.opacity(0.40)))

        // A sailboat's sail sits behind the hull — drawn first, so the boat is on top of it.
        if style == .sailboat { drawSail(g, hw: ew, hh: sl) }

        // Outboard motor sticking off the transom.
        if motor {
            let mw = hw * 0.24
            g.fill(Path(roundedRect: CGRect(x: -mw, y: hh * 0.9, width: mw * 2, height: hh * 0.34),
                        cornerRadius: mw * 0.6), with: .color(Color(red: 0.23, green: 0.25, blue: 0.28)))
            g.fill(Path(roundedRect: CGRect(x: -mw * 0.45, y: hh * 1.06, width: mw * 0.9, height: hh * 0.26),
                        cornerRadius: 2), with: .color(Color(red: 0.14, green: 0.15, blue: 0.17)))
        }

        // Painted outer hull + a crisp outline.
        let shell = hullShape(style, hw, hh)
        g.fill(shell, with: .color(hull))
        g.stroke(shell, with: .color(.black.opacity(0.22)), lineWidth: max(0.8, hw * 0.05))

        // Wooden deck / gunwale surface (inset hull) — leaves a painted hull band around the rim.
        var dg = g
        dg.translateBy(x: 0, y: hh * 0.015)
        dg.fill(hullShape(style, hw * 0.76, hh * 0.84), with: .color(deck))

        // Open cockpit well (forward, where the angler sits) + a couple of thwart seats.
        let well0 = CGRect(x: -ew * 0.42, y: -hh * 0.36, width: ew * 0.84, height: hh * 0.54)
        g.fill(Path(roundedRect: well0, cornerRadius: ew * 0.28), with: .color(well))
        for fy in [0.18, 0.62] {
            let yy = well0.minY + well0.height * fy
            g.fill(Path(roundedRect: CGRect(x: well0.minX, y: yy, width: well0.width, height: hh * 0.09),
                        cornerRadius: 2), with: .color(seat))
        }

        // Per-boat superstructure (cabins, mast, treasure, …) gives each its identity.
        drawSuperstructure(g, style, hw: ew, hh: sl, hull: hull, accent: accent)

        // A light rim catching the sun along the hull edge.
        g.stroke(shell, with: .color(.white.opacity(0.28)), lineWidth: max(0.7, hw * 0.05))
    }

    /// A sailboat's billowing mainsail — set aft (behind the angler) and drawn behind the hull.
    private static func drawSail(_ g: GraphicsContext, hw: Double, hh: Double) {
        var sail = Path()
        sail.move(to: CGPoint(x: 0, y: hh * 0.14))
        sail.addQuadCurve(to: CGPoint(x: 0, y: hh * 1.5), control: CGPoint(x: hw * 0.28, y: hh * 0.9))
        sail.addQuadCurve(to: CGPoint(x: hw * 0.92, y: hh * 0.5), control: CGPoint(x: hw * 0.85, y: hh * 1.0))
        sail.closeSubpath()
        g.fill(sail, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.80)]),
                                           startPoint: CGPoint(x: 0, y: hh * 1.5), endPoint: CGPoint(x: hw, y: hh * 0.5)))
        g.stroke(sail, with: .color(.black.opacity(0.18)), lineWidth: 0.8)
    }

    /// The bits that make each boat distinct: cabins, windshields, masts/sails, treasure, boot trim.
    private static func drawSuperstructure(_ g: GraphicsContext, _ style: BoatStyle,
                                           hw: Double, hh: Double, hull: Color, accent: Color) {
        let dark = Color.black.opacity(0.32)
        let glass = Color(red: 0.55, green: 0.74, blue: 0.90)
        switch style {
        case .skiff:
            break                                       // an open rowing skiff — nothing on deck

        case .motorboat:
            var ws = Path()                             // console windscreen aft, behind the angler
            ws.move(to: CGPoint(x: -hw * 0.30, y: hh * 0.34))
            ws.addLine(to: CGPoint(x: hw * 0.30, y: hh * 0.34))
            ws.addLine(to: CGPoint(x: hw * 0.20, y: hh * 0.58))
            ws.addLine(to: CGPoint(x: -hw * 0.20, y: hh * 0.58))
            ws.closeSubpath()
            g.fill(ws, with: .color(glass.opacity(0.8)))
            g.stroke(ws, with: .color(dark), lineWidth: max(0.6, hw * 0.05))

        case .trawler:
            let wh = CGRect(x: -hw * 0.34, y: hh * 0.30, width: hw * 0.68, height: hh * 0.46)   // wheelhouse aft
            g.fill(Path(roundedRect: wh, cornerRadius: hw * 0.12), with: .color(accent))
            g.fill(Path(CGRect(x: wh.minX + hw * 0.07, y: wh.minY + hh * 0.07, width: wh.width - hw * 0.14, height: hh * 0.12)),
                   with: .color(glass.opacity(0.85)))
            var mast = Path(); mast.move(to: CGPoint(x: 0, y: hh * 0.30)); mast.addLine(to: CGPoint(x: 0, y: hh * 0.04))
            g.stroke(mast, with: .color(dark), lineWidth: max(0.8, hw * 0.06))
            var boom = Path(); boom.move(to: CGPoint(x: -hw * 0.5, y: hh * 0.13)); boom.addLine(to: CGPoint(x: hw * 0.5, y: hh * 0.13))
            g.stroke(boom, with: .color(dark.opacity(0.7)), lineWidth: max(0.6, hw * 0.04))

        case .voyager:
            let cab = CGRect(x: -hw * 0.36, y: hh * 0.22, width: hw * 0.72, height: hh * 0.58)   // cabin aft
            g.fill(Path(roundedRect: cab, cornerRadius: hw * 0.22), with: .color(accent.opacity(0.92)))
            g.fill(Path(roundedRect: CGRect(x: cab.minX + hw * 0.07, y: cab.minY + hh * 0.09, width: cab.width - hw * 0.14, height: hh * 0.18), cornerRadius: hw * 0.06),
                   with: .color(glass.opacity(0.9)))                                   // wraparound window
            g.stroke(Path(roundedRect: cab, cornerRadius: hw * 0.22), with: .color(dark.opacity(0.5)), lineWidth: 0.7)

        case .speedboat:
            for sx in [-0.13, 0.13] {                   // racing stripes the length of the hull
                g.fill(Path(CGRect(x: hw * sx - hw * 0.045, y: -hh * 0.9, width: hw * 0.09, height: hh * 1.75)),
                       with: .color(accent.opacity(0.9)))
            }
            var ws = Path()                             // sport cowl aft
            ws.move(to: CGPoint(x: -hw * 0.24, y: hh * 0.52))
            ws.addLine(to: CGPoint(x: hw * 0.24, y: hh * 0.52))
            ws.addLine(to: CGPoint(x: hw * 0.15, y: hh * 0.28))
            ws.addLine(to: CGPoint(x: -hw * 0.15, y: hh * 0.28))
            ws.closeSubpath()
            g.fill(ws, with: .color(Color(red: 0.13, green: 0.17, blue: 0.24).opacity(0.9)))

        case .sailboat:
            // the sail is drawn behind the hull (drawSail); mast + pennant sit aft, behind the angler
            var mast = Path(); mast.move(to: CGPoint(x: 0, y: hh * 0.16)); mast.addLine(to: CGPoint(x: 0, y: hh * 1.05))
            g.stroke(mast, with: .color(Color(red: 0.5, green: 0.36, blue: 0.22)), lineWidth: max(0.9, hw * 0.07))
            g.fill(Path(CGRect(x: 0, y: hh * 1.0, width: hw * 0.4, height: hh * 0.12)), with: .color(accent))  // pennant

        case .yacht:
            let lower = CGRect(x: -hw * 0.38, y: hh * 0.12, width: hw * 0.76, height: hh * 0.78)   // superstructure aft
            g.fill(Path(roundedRect: lower, cornerRadius: hw * 0.16), with: .color(Color(white: 0.95)))
            g.fill(Path(CGRect(x: lower.minX + hw * 0.06, y: hh * 0.42, width: lower.width - hw * 0.12, height: hh * 0.12)),
                   with: .color(accent))                                              // gold window band
            let bridge = CGRect(x: -hw * 0.24, y: hh * 0.20, width: hw * 0.48, height: hh * 0.32)
            g.fill(Path(roundedRect: bridge, cornerRadius: hw * 0.1), with: .color(Color(white: 0.84)))
            g.stroke(hullShape(.yacht, hw / hullParams(.yacht).w, hh / hullParams(.yacht).l),
                     with: .color(accent.opacity(0.8)), lineWidth: max(0.6, hw * 0.05))  // gold sheer line

        case .boot:
            g.fill(Path(roundedRect: CGRect(x: -hw * 0.7, y: hh * 0.4, width: hw * 1.4, height: hh * 0.42), cornerRadius: hw * 0.2),
                   with: .color(Color(red: 0.30, green: 0.19, blue: 0.11)))           // folded cuff at the stern
            for i in 0..<4 {                                                          // lace eyelets toward the stern
                let ly = hh * 0.06 + Double(i) * hh * 0.22
                for sx in [-1.0, 1.0] {
                    g.fill(Path(ellipseIn: CGRect(x: sx * hw * 0.12 - hw * 0.05, y: ly, width: hw * 0.10, height: hh * 0.06)),
                           with: .color(Color(white: 0.85).opacity(0.85)))
                }
            }
            g.stroke(hullShape(.boot, hw / hullParams(.boot).w, hh / hullParams(.boot).l),
                     with: .color(Color(red: 0.20, green: 0.12, blue: 0.07)), lineWidth: max(1, hw * 0.09))  // thick sole

        case .barge:
            for i in 0..<3 {                                                          // deck planks
                let ly = -hh * 0.5 + Double(i) * hh * 0.5
                var ln = Path(); ln.move(to: CGPoint(x: -hw * 0.9, y: ly)); ln.addLine(to: CGPoint(x: hw * 0.9, y: ly))
                g.stroke(ln, with: .color(.black.opacity(0.18)), lineWidth: 1)
            }
            let ch = CGRect(x: -hw * 0.34, y: hh * 0.24, width: hw * 0.68, height: hh * 0.5)   // chest aft
            g.fill(Path(roundedRect: ch, cornerRadius: hw * 0.08), with: .color(Color(red: 0.42, green: 0.27, blue: 0.14)))
            g.fill(Path(CGRect(x: ch.minX, y: ch.midY - hh * 0.04, width: ch.width, height: hh * 0.08)), with: .color(accent))
            g.fill(Path(ellipseIn: CGRect(x: -hw * 0.06, y: ch.midY - hh * 0.04, width: hw * 0.12, height: hh * 0.08)),
                   with: .color(Color(white: 0.9)))                                   // lock
            for d in [-0.5, 0.5] {                                                    // gold spilling on deck
                g.fill(Path(ellipseIn: CGRect(x: hw * d - hw * 0.07, y: hh * 0.14, width: hw * 0.14, height: hh * 0.09)),
                       with: .color(accent.opacity(0.95)))
            }
        }
    }

    // MARK: Drifting boat (very rare obstacle — another boat crossing slowly) -

    static func drawDriftBoat(_ ctx: GraphicsContext, _ s: CGSize, _ o: Obstacle, t: Double) {
        let c = p(o.x, o.y, s)
        let hw = o.r * s.width * 0.72
        let hh = o.r * s.width * 1.02
        // Same colours as the boats moored in the harbour.
        let palette = [Sea.coral, Sea.gold, Sea.teal, Color(red: 0.80, green: 0.52, blue: 0.42)]
        let col = palette[o.seed % palette.count]
        let bank = max(-0.3, min(0.3, o.vx * 4))

        // The water breaks faintly off the bow on the side it's steering toward.
        let side: Double = o.vx >= 0 ? 1 : -1
        let mag = min(1, abs(o.vx) / 0.10)
        let flick = 0.82 + 0.18 * sin(t * 4 + Double(o.seed))
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(bank))
        var wave = Path()
        wave.move(to: CGPoint(x: side * hw * 0.30, y: -hh * 0.92))
        wave.addQuadCurve(to: CGPoint(x: side * hw * 1.15, y: hh * 0.40),
                          control: CGPoint(x: side * hw * 1.45, y: -hh * 0.40))
        g.stroke(wave, with: .color(foamLight.opacity(0.26 * mag * flick)), lineWidth: 5)   // soft glow
        g.stroke(wave, with: .color(foamLight.opacity(0.70 * mag * flick)), lineWidth: 2)   // crest
        // A little foam curl breaking off the bow.
        g.fill(Path(ellipseIn: CGRect(x: side * hw * 0.55, y: -hh * 0.78, width: hw * 0.5, height: hw * 0.5)),
               with: .color(foamLight.opacity(0.30 * mag * flick)))

        boatBody(ctx, at: c, hw: hw, hh: hh, bank: bank, hull: col)
    }

    // MARK: Boat (top-down, pointing "up" the screen) -----------------------

    /// The rod tip — where the fishing line starts. Other code reads this via `rodTip`.
    static func rodTip(boatX: Double, boatY: Double) -> CGPoint {
        CGPoint(x: boatX, y: boatY - 0.05)   // normalized
    }

    static func drawBoat(_ ctx: GraphicsContext, _ s: CGSize, x: Double, boatY: Double,
                         wake: [Double], t: Double, speed: Double = 1, timeOfDay tod: Double = 0,
                         hull: Color = Sea.gold, accent: Color = Sea.coral, scale: Double = 1,
                         style: BoatStyle = .skiff, angler: Bool = true,
                         casting: Bool = false, castT: Double = 0) {
        let cx = x * s.width
        let cy = boatY * s.height
        let hw = 0.066 * s.width * scale
        let hh = 0.085 * s.height * scale

        // Bank gently into the turn (from how the boat's been moving lately — a smooth debounce).
        let recent = wake.first ?? x
        let older = wake.count > 5 ? wake[5] : (wake.last ?? x)
        let bank = max(-0.3, min(0.3, (recent - older) * 9))

        // A living, curving wake behind (below) the boat — fades in as the boat gets up to speed.
        drawWake(ctx, s, stern: CGPoint(x: cx, y: cy + hh * 0.9), wake: wake, t: t, strength: speed,
                 night: nightAmount(tod))

        var c = ctx
        c.translateBy(x: cx, y: cy)
        c.rotate(by: .radians(bank))

        // Turning into the water: a bow wave breaks at the bow (the front — up the screen) on the
        // side you're steering toward and peels back along the hull. Drawn in the boat's frame, so
        // it banks and hangs with the boat.
        let turn = min(1, abs(bank) / 0.3)
        if turn > 0.05 {
            let side: Double = bank >= 0 ? 1 : -1
            let pulse = 0.7 + 0.3 * sin(t * 5)
            var bw = Path()
            bw.move(to: CGPoint(x: side * hw * 0.10, y: -hh * 1.02))            // breaks at the bow tip
            bw.addQuadCurve(to: CGPoint(x: side * hw * 1.0, y: -hh * 0.20),     // peels out & back, front half only
                            control: CGPoint(x: side * hw * 1.02, y: -hh * 0.82))
            c.stroke(bw, with: .color(foamLight.opacity(0.22 * turn * pulse)), lineWidth: 5)   // soft glow
            c.stroke(bw, with: .color(foamLight.opacity(0.62 * turn * pulse)), lineWidth: 2)   // crest
            let cr = hw * 0.24                                                   // foam curl at the bow
            c.fill(Path(ellipseIn: CGRect(x: side * hw * 0.30 - cr, y: -hh * 1.02 - cr * 0.3,
                                          width: cr * 2, height: cr * 2)),
                   with: .color(foamLight.opacity(0.34 * turn * pulse)))
        }
        // A little foam at the bow tip as it cuts forward (only once it's moving).
        c.fill(Path(ellipseIn: CGRect(x: -hw * 0.2, y: -hh * 1.02, width: hw * 0.4, height: hh * 0.16)),
               with: .color(Sea.foam.opacity(0.5 * speed)))

        // Shared hull / deck / cockpit look (no motor — this one's worked by rod).
        boatBody(ctx, at: CGPoint(x: cx, y: cy), hw: hw, hh: hh, bank: bank,
                 hull: hull, accent: accent, style: style, motor: false)

        // White foam churning right behind the stern — only once under way.
        c.fill(Path(ellipseIn: CGRect(x: -hw * 0.5, y: hh * 0.86, width: hw, height: hh * 0.26)),
               with: .color(Sea.foam.opacity(0.5 * speed)))

        // The angler sitting in the cockpit well + the rod. While casting he winds the rod back,
        // then whips it forward and the line flies out over the bow.
        if angler {
            // Rod poses (boat-local): rest forward · wound back · whipped forward.
            let restTip = CGPoint(x: 0, y: -0.055 * s.height), restCtrl = CGPoint(x: hw * 0.16, y: -hh * 0.45)
            let backTip = CGPoint(x: hw * 0.72, y: hh * 0.66), backCtrl = CGPoint(x: hw * 0.55, y: hh * 0.22)
            let castTip = CGPoint(x: -hw * 0.10, y: -0.062 * s.height), castCtrl = CGPoint(x: -hw * 0.10, y: -hh * 0.5)
            var tip = restTip, ctrl = restCtrl, lean = 0.0
            if casting {
                let wind = 0.22, whip = 0.40, settle = 0.58       // mirrors GameModel.castWindup
                if castT < wind {
                    let u = smooth(castT / wind); tip = lerpP(restTip, backTip, u); ctrl = lerpP(restCtrl, backCtrl, u)
                } else if castT < whip {
                    let u = smooth((castT - wind) / (whip - wind))
                    tip = lerpP(backTip, castTip, u); ctrl = lerpP(backCtrl, castCtrl, u)
                    lean = -hh * 0.05 * sin(u * .pi)              // a little forward bob on the whip
                } else if castT < settle {
                    let u = smooth((castT - whip) / (settle - whip)); tip = lerpP(castTip, restTip, u); ctrl = lerpP(castCtrl, restCtrl, u)
                }
            }
            // Body + head (lean forward slightly during the whip).
            c.fill(Path(ellipseIn: CGRect(x: -hw * 0.26, y: -hh * 0.06 + lean, width: hw * 0.52, height: hw * 0.52)),
                   with: .color(accent))
            c.fill(Path(ellipseIn: CGRect(x: -hw * 0.13, y: -hh * 0.14 + lean, width: hw * 0.26, height: hw * 0.26)),
                   with: .color(Color(red: 0.93, green: 0.80, blue: 0.66)))           // head
            var rod = Path()
            rod.move(to: CGPoint(x: hw * 0.12, y: -hh * 0.02))
            rod.addQuadCurve(to: tip, control: ctrl)
            c.stroke(rod, with: .color(Color(red: 0.30, green: 0.22, blue: 0.15)), lineWidth: 1.8)
        }
    }

    private static func smooth(_ u: Double) -> Double { let x = min(1, max(0, u)); return x * x * (3 - 2 * x) }
    private static func lerpP(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    /// A soft, animated foam trail that follows the boat's recent path (curves as you steer).
    /// `strength` (0…1) fades the whole wake in as the boat gets up to speed.
    private static func drawWake(_ ctx: GraphicsContext, _ s: CGSize, stern: CGPoint, wake: [Double],
                                 t: Double, strength: Double, night: Double = 0) {
        guard wake.count > 3, strength > 0.02 else { return }
        let w = s.width
        let dy = 0.024 * s.height
        let n = wake.count
        let wakeBlue = Color(red: 0.62, green: 0.84, blue: 0.97)
        let glow = Sea.teal                                        // bioluminescent trail after dark

        // Two tapering streams that diverge from the stern and curve along the boat's path.
        for side in [-1.0, 1.0] {
            var topEdge: [CGPoint] = [], botEdge: [CGPoint] = [], core: [CGPoint] = []
            for i in 0..<n {
                let f = Double(i) / Double(n - 1)
                let cx = wake[i] * w + side * (0.012 + Double(i) * 0.006) * w
                          + sin(Double(i) * 0.5 + t * 3) * 0.003 * w
                let cy = stern.y + Double(i) * dy
                let hw = (0.045 * pow(1 - f, 0.75) + 0.004) * w        // wide near the boat, tapering away
                core.append(CGPoint(x: cx, y: cy))
                topEdge.append(CGPoint(x: cx - hw, y: cy))
                botEdge.append(CGPoint(x: cx + hw, y: cy))
            }
            var ribbon = Path()
            ribbon.move(to: topEdge[0])
            for p in topEdge.dropFirst() { ribbon.addLine(to: p) }
            for p in botEdge.reversed() { ribbon.addLine(to: p) }
            ribbon.closeSubpath()
            ctx.fill(ribbon, with: .color(wakeBlue.opacity(0.14 * strength)))   // soft translucent body
            for i in 1..<n {                                               // bright fading core line
                let fade = 1 - Double(i) / Double(n)
                var seg = Path(); seg.move(to: core[i - 1]); seg.addLine(to: core[i])
                if night > 0.05 {                                          // soft glowing halo at night
                    ctx.stroke(seg, with: .color(glow.opacity(0.45 * fade * strength * night)),
                               lineWidth: 4.6 * fade + 1.6)
                }
                ctx.stroke(seg, with: .color(wakeBlue.opacity(0.55 * fade * strength)), lineWidth: 2.4 * fade + 0.8)
            }
        }
    }

    // MARK: A flock of birds passing over, with soft shadows on the water -----

    /// A herring gull seen from above, centred at `c`, body pointing along `angle`. `L` is the
    /// body length; `flap` (0…1) sweeps the wings — wide & flat on the downstroke, shorter & more
    /// swept when raised. `shadow` draws it as one soft dark shape; otherwise it's fully coloured.
    private static func drawGull(_ ctx: GraphicsContext, at c: CGPoint, angle: Double, L: Double,
                                 flap: Double, alpha: Double, shadow: Bool) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(angle))          // +x is the direction of flight
        if shadow { g.addFilter(.blur(radius: L * 0.16)) }

        let wingCol = Color(red: 0.70, green: 0.74, blue: 0.79).opacity(alpha)   // pale grey
        let tipCol  = Color(red: 0.16, green: 0.18, blue: 0.22).opacity(alpha)   // black wingtips
        let bodyCol = Color(red: 0.95, green: 0.96, blue: 0.98).opacity(alpha)   // white
        let billCol = Color(red: 0.95, green: 0.74, blue: 0.20).opacity(alpha)   // yellow bill
        let shCol   = Sea.deep.opacity(0.22 * alpha)

        let span  = L * (0.74 + 0.26 * flap)      // lateral reach — widest on the downstroke
        let sweep = L * (0.34 - 0.16 * flap)      // wings swept further back when raised

        // Two long, pointed wings swept back from the shoulders.
        for side in [-1.0, 1.0] {
            let rootF = CGPoint(x: L * 0.22, y: side * L * 0.05)
            let tip   = CGPoint(x: L * 0.06 - sweep, y: side * span)
            let rootB = CGPoint(x: -L * 0.14, y: side * L * 0.05)
            var wing = Path()
            wing.move(to: rootF)
            wing.addQuadCurve(to: tip,   control: CGPoint(x: L * 0.30, y: side * span * 0.62))  // bowed leading edge
            wing.addQuadCurve(to: rootB, control: CGPoint(x: -L * 0.18, y: side * span * 0.5))  // swept trailing edge
            wing.closeSubpath()
            g.fill(wing, with: .color(shadow ? shCol : wingCol))
            if !shadow {
                var blackTip = Path()                     // dark wingtip
                blackTip.move(to: tip)
                blackTip.addQuadCurve(to: CGPoint(x: L * 0.06 - sweep * 0.45, y: side * span * 0.7),
                                      control: CGPoint(x: L * 0.16 - sweep * 0.4, y: side * span * 0.92))
                blackTip.addLine(to: CGPoint(x: -sweep * 0.55, y: side * span * 0.72))
                blackTip.closeSubpath()
                g.fill(blackTip, with: .color(tipCol))
            }
        }

        // Body, then the head, bill and tail on top.
        g.fill(Path(ellipseIn: CGRect(x: -L * 0.5, y: -L * 0.11, width: L, height: L * 0.22)),
               with: .color(shadow ? shCol : bodyCol))
        if !shadow {
            var tail = Path()
            tail.move(to: CGPoint(x: -L * 0.42, y: -L * 0.10))
            tail.addLine(to: CGPoint(x: -L * 0.64, y: 0))
            tail.addLine(to: CGPoint(x: -L * 0.42, y: L * 0.10))
            tail.closeSubpath()
            g.fill(tail, with: .color(wingCol))
            g.fill(Path(ellipseIn: CGRect(x: L * 0.40, y: -L * 0.08, width: L * 0.20, height: L * 0.16)),
                   with: .color(bodyCol))                                          // head
            var bill = Path()
            bill.move(to: CGPoint(x: L * 0.58, y: -L * 0.025))
            bill.addLine(to: CGPoint(x: L * 0.70, y: 0))
            bill.addLine(to: CGPoint(x: L * 0.58, y: L * 0.025))
            bill.closeSubpath()
            g.fill(bill, with: .color(billCol))
        } else {
            g.fill(Path(ellipseIn: CGRect(x: L * 0.40, y: -L * 0.08, width: L * 0.20, height: L * 0.16)),
                   with: .color(shCol))
        }
    }

    /// A single gull crossing the screen diagonally, bottom-to-top. On a `dive` pass it leaves that
    /// path midway to swoop down at a fish far ahead of the boat — at (`diveX`,`diveY`) — then climbs
    /// back and continues off the top. Called twice per frame: `shadows: true` lays its soft shadow
    /// on the water (under the obstacles), `shadows: false` draws the gull on top.
    static func drawBird(_ ctx: GraphicsContext, _ s: CGSize, progress p: Double, dir: Double,
                         t: Double, dive: Bool, diveX: Double, diveY: Double, xOffset: Double = 0,
                         shadows: Bool) {
        let w = s.width, h = s.height
        let alpha = min(1, min(p, 1 - p) / 0.12)                          // fade in/out at the ends
        guard alpha > 0 else { return }

        // The base diagonal flyover (bottom → top). `xOffset` shifts it after a knock off course.
        let x0 = dir > 0 ? -0.15 : 1.15
        let x1 = dir > 0 ?  1.05 : -0.05
        let y0 = 0.70, y1 = 0.04
        func base(_ q: Double) -> CGPoint {
            CGPoint(x: (x0 + (x1 - x0) * q + xOffset) * w, y: (y0 + (y1 - y0) * q) * h + 0.012 * sin(t * 1.4) * h)
        }
        // The dive: a snappy swoop that homes onto the fish, peaking late (high up the screen).
        let pd = 0.62, halfWin = 0.07
        func dipAmount(_ q: Double) -> Double {
            let d = abs(q - pd); guard d < halfWin else { return 0 }
            let u = 1 - d / halfWin; return u * u * (3 - 2 * u)
        }
        func pos(_ q: Double) -> CGPoint {
            let b = base(q)
            guard dive else { return b }
            let k = dipAmount(q)
            return CGPoint(x: b.x + (diveX * w - b.x) * k, y: b.y + (diveY * h - b.y) * k)
        }
        let cur = pos(p), nxt = pos(min(1, p + 0.012))
        let heading = atan2(nxt.y - cur.y, nxt.x - cur.x)
        let dip = dive ? dipAmount(p) : 0
        let L = 0.060 * w * (1 - 0.30 * p) * (1 + 0.30 * dip)             // grows toward the water at the dip
        let flap = 0.5 + 0.5 * sin(t * 7)

        if shadows {
            let sc = 1 - 0.85 * dip                                       // shadow slides under it at the dip
            drawGull(ctx, at: CGPoint(x: cur.x + 0.018 * w * sc, y: cur.y + 0.05 * h * sc),
                     angle: heading, L: L, flap: flap, alpha: alpha * 0.9, shadow: true)
        } else {
            drawGull(ctx, at: cur, angle: heading, L: L, flap: flap, alpha: alpha, shadow: false)
        }
    }

    /// A single feather knocked loose from a clipped gull — a small curved vane that sways as it falls.
    static func drawFeather(_ ctx: GraphicsContext, _ s: CGSize, _ f: Feather, dur: Double) {
        let w = s.width, h = s.height
        let life = min(1, max(0, f.age / dur))
        let alpha = (1 - life) * (1 - life)                    // ease-out fade
        guard alpha > 0 else { return }
        let sway = sin(f.age * 7 + Double(f.seed % 100) * 0.1) * 0.18   // lazy side-to-side flutter
        let c = CGPoint(x: (f.x) * w, y: f.y * h)
        let L = 0.034 * w
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(f.rot + sway))

        let vane = Color(red: 0.96, green: 0.97, blue: 0.99).opacity(0.92 * alpha)
        let quill = Color(red: 0.62, green: 0.66, blue: 0.72).opacity(0.9 * alpha)
        // The vane: a pointed leaf shape around the central shaft.
        var blade = Path()
        blade.move(to: CGPoint(x: 0, y: -L * 0.5))
        blade.addQuadCurve(to: CGPoint(x: 0, y: L * 0.5), control: CGPoint(x: L * 0.26, y: 0))
        blade.addQuadCurve(to: CGPoint(x: 0, y: -L * 0.5), control: CGPoint(x: -L * 0.26, y: 0))
        blade.closeSubpath()
        g.fill(blade, with: .color(vane))
        // The shaft down the middle.
        var shaft = Path()
        shaft.move(to: CGPoint(x: 0, y: -L * 0.5))
        shaft.addLine(to: CGPoint(x: 0, y: L * 0.5))
        g.stroke(shaft, with: .color(quill), lineWidth: max(0.6, L * 0.05))
    }

    // MARK: The Kraken -------------------------------------------------------

    // Tentacle strike lifecycle (mirrors GameModel's krakenTeleT / krakenStrikeT / krakenRecedeT).
    private static let tentTele = 1.1, tentStrike = 0.35, tentRecede = 0.5

    /// The dark deep + the looming body, drawn UNDER the boat. `emerge` (0→1) drives the rise:
    /// the sea darkens, bubbles boil up, then the body lifts and the eyes open.
    static func drawKrakenMurk(_ ctx: GraphicsContext, _ s: CGSize, t: Double, emerge: Double) {
        let w = s.width, h = s.height
        let e = min(1, max(0, emerge))
        let es = e * e * (3 - 2 * e)                 // smoothstep for the rise

        // The deep darkens as it approaches — a little even before you can see it.
        ctx.fill(Path(CGRect(origin: .zero, size: s)),
                 with: .color(Color(red: 0.04, green: 0.02, blue: 0.10).opacity(0.12 + 0.36 * e)))
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
            Gradient(colors: [.clear, Color(red: 0.02, green: 0.0, blue: 0.08).opacity(0.18 + 0.55 * e)]),
            center: CGPoint(x: w * 0.5, y: h * 0.45), startRadius: w * 0.22, endRadius: w * 0.92))

        // Bubbles boiling up from the deep — the first hint, strongest during the build-up.
        let bubA = 0.25 + 0.75 * (1 - e)
        for k in 0..<16 {
            let bx = (Double((k * 37) % 100) / 100 + 0.05 * sin(t + Double(k))) * w
            let speed = 0.28 + Double(k % 4) * 0.09
            let prog = (t * speed + Double(k) * 0.17).truncatingRemainder(dividingBy: 1)
            let by = (1 - prog) * h
            let r = 1.2 + Double(k % 3) * 1.1
            let fade = sin(prog * .pi)               // fade in at the bottom & out near the top
            ctx.stroke(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                       with: .color(Sea.foam.opacity(0.22 * bubA * fade)), lineWidth: 1)
        }

        guard es > 0.02 else { return }

        // The body rises from beyond the top edge as it surfaces.
        let sway = sin(t * 0.8) * 0.02 * w
        let cx = w * 0.5 + sway
        let cy = (-0.10 + 0.23 * es) * h             // climbs into view
        let scale = 0.6 + 0.4 * es
        let bw = 0.52 * w * scale, bh = 0.34 * h * scale
        let a = es
        let bodyTop = Color(red: 0.34, green: 0.15, blue: 0.44)   // lit upper mantle
        let bodyDark = Color(red: 0.11, green: 0.04, blue: 0.20)  // shadowed underside
        let biolum = Sea.teal

        // Five waving arms (behind the mantle) — tapering chains of suckered segments.
        for k in 0..<5 {
            let dir = (Double(k) - 2) / 2
            let bxh = cx + dir * bw * 0.30, byh = cy + bh * 0.16
            let segs = 9
            for i in 0...segs {
                let f = Double(i) / Double(segs)
                let curl = sin(t * 1.6 + Double(k) * 1.3 + f * 3) * (0.04 + 0.06 * f) * w * scale
                let px = bxh + dir * bw * 0.52 * f + curl
                let py = byh + bh * 0.72 * f
                let r = (0.030 * (1 - f) + 0.006) * w * scale
                ctx.fill(Path(ellipseIn: CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)),
                         with: .color(bodyDark.opacity(0.92 * a)))
                if i % 2 == 1 {
                    ctx.fill(Path(ellipseIn: CGRect(x: px - r * 0.35, y: py - r * 0.35, width: r * 0.7, height: r * 0.7)),
                             with: .color(biolum.opacity(0.35 * a)))
                }
            }
        }

        // The mantle — a pointed squid head, top-lit gradient.
        var mantle = Path()
        mantle.move(to: CGPoint(x: cx, y: cy - bh * 0.80))
        mantle.addQuadCurve(to: CGPoint(x: cx + bw * 0.5, y: cy - bh * 0.06), control: CGPoint(x: cx + bw * 0.5, y: cy - bh * 0.66))
        mantle.addQuadCurve(to: CGPoint(x: cx + bw * 0.30, y: cy + bh * 0.34), control: CGPoint(x: cx + bw * 0.52, y: cy + bh * 0.18))
        mantle.addQuadCurve(to: CGPoint(x: cx - bw * 0.30, y: cy + bh * 0.34), control: CGPoint(x: cx, y: cy + bh * 0.52))
        mantle.addQuadCurve(to: CGPoint(x: cx - bw * 0.5, y: cy - bh * 0.06), control: CGPoint(x: cx - bw * 0.52, y: cy + bh * 0.18))
        mantle.addQuadCurve(to: CGPoint(x: cx, y: cy - bh * 0.80), control: CGPoint(x: cx - bw * 0.5, y: cy - bh * 0.66))
        mantle.closeSubpath()
        ctx.fill(mantle, with: .linearGradient(Gradient(colors: [bodyTop.opacity(a), bodyDark.opacity(a)]),
                                               startPoint: CGPoint(x: cx, y: cy - bh * 0.8), endPoint: CGPoint(x: cx, y: cy + bh * 0.4)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - bw * 0.26, y: cy - bh * 0.62, width: bw * 0.46, height: bh * 0.4)),
                 with: .color(.white.opacity(0.06 * a)))     // sheen

        // Mottled skin + bioluminescent freckles.
        for k in 0..<14 {
            let hx = Double((k * 53 + 11) % 100) / 100 - 0.5
            let hy = Double((k * 31 + 7) % 100) / 100 - 0.5
            let sx = cx + hx * bw * 0.7, sy = cy + hy * bh * 0.62 - bh * 0.08
            let rr = (1.0 + Double(k % 3)) * scale
            let twk = 0.5 + 0.5 * sin(t * 2 + Double(k))
            ctx.fill(Path(ellipseIn: CGRect(x: sx - rr, y: sy - rr, width: rr * 2, height: rr * 2)),
                     with: .color(k % 4 == 0 ? biolum.opacity(0.5 * twk * a) : bodyDark.opacity(0.45 * a)))
        }

        // The eyes open late in the rise — glowing, with a brow, slit pupil and glint.
        let open = max(0, min(1, (e - 0.55) / 0.4))
        if open > 0 {
            let pulse = 0.6 + 0.4 * sin(t * 3)
            let eh = 0.066 * w * scale * open, ew = 0.10 * w * scale
            for side in [-1.0, 1.0] {
                let ex = cx + side * bw * 0.17, ey = cy + bh * 0.05
                ctx.fill(Path(ellipseIn: CGRect(x: ex - ew * 0.95, y: ey - eh * 0.95, width: ew * 1.9, height: eh * 1.9)),
                         with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.8, blue: 0.3).opacity(0.4 * pulse * open), .clear]),
                                               center: CGPoint(x: ex, y: ey), startRadius: 0, endRadius: ew))     // halo
                ctx.fill(Path(ellipseIn: CGRect(x: ex - ew / 2, y: ey - eh / 2, width: ew, height: eh)),
                         with: .color(Color(red: 1, green: 0.84, blue: 0.32).opacity((0.5 + 0.4 * pulse) * open)))  // iris
                ctx.fill(Path(ellipseIn: CGRect(x: ex - 0.013 * w * scale, y: ey - eh / 2, width: 0.026 * w * scale, height: eh)),
                         with: .color(.black.opacity(0.88 * open)))                                                 // slit pupil
                ctx.fill(Path(ellipseIn: CGRect(x: ex - ew * 0.28, y: ey - eh * 0.3, width: ew * 0.2, height: ew * 0.2)),
                         with: .color(.white.opacity(0.85 * open)))                                                 // glint
                var brow = Path()
                brow.move(to: CGPoint(x: ex - ew * 0.75, y: ey - eh * 0.7))
                brow.addQuadCurve(to: CGPoint(x: ex + ew * 0.75, y: ey - eh * 0.7), control: CGPoint(x: ex, y: ey - eh * 1.35))
                ctx.stroke(brow, with: .color(bodyDark.opacity(0.9 * open)), lineWidth: 3 * scale)
            }
            // A hooked beak below the eyes.
            var beak = Path()
            beak.move(to: CGPoint(x: cx, y: cy + bh * 0.18))
            beak.addLine(to: CGPoint(x: cx - bw * 0.055, y: cy + bh * 0.04))
            beak.addLine(to: CGPoint(x: cx + bw * 0.055, y: cy + bh * 0.04))
            beak.closeSubpath()
            ctx.fill(beak, with: .color(Color(red: 0.06, green: 0.02, blue: 0.10).opacity(open)))
        }
    }

    /// The telegraphs + striking tentacles, drawn OVER the boat so they wrap around it.
    static func drawKrakenStrikes(_ ctx: GraphicsContext, _ s: CGSize, tentacles: [Tentacle]) {
        for tnt in tentacles { drawTentacle(ctx, s, x: tnt.x, age: tnt.age, seed: tnt.seed) }
    }

    /// Harpoons in flight, flying up toward the monster.
    static func drawHarpoons(_ ctx: GraphicsContext, _ s: CGSize, harpoons: [Harpoon]) {
        let w = s.width, h = s.height
        for hp in harpoons {
            let x = hp.x * w, y = hp.y * h
            let tail = y + 0.075 * h
            // shaft
            var shaft = Path(); shaft.move(to: CGPoint(x: x, y: tail)); shaft.addLine(to: CGPoint(x: x, y: y))
            ctx.stroke(shaft, with: .color(Color(red: 0.45, green: 0.32, blue: 0.20)), lineWidth: 2.4)
            ctx.stroke(shaft, with: .color(Sea.gold.opacity(0.6)), lineWidth: 0.8)
            // barbed steel head
            var head = Path()
            head.move(to: CGPoint(x: x, y: y - 0.022 * h))
            head.addLine(to: CGPoint(x: x - 4, y: y + 2))
            head.addLine(to: CGPoint(x: x + 4, y: y + 2))
            head.closeSubpath()
            ctx.fill(head, with: .color(Color(white: 0.85)))
            // little barbs
            ctx.stroke(Path { p in p.move(to: CGPoint(x: x - 3, y: y + 6)); p.addLine(to: CGPoint(x: x - 0.5, y: y + 1)) },
                       with: .color(Color(white: 0.8)), lineWidth: 1.2)
            ctx.stroke(Path { p in p.move(to: CGPoint(x: x + 3, y: y + 6)); p.addLine(to: CGPoint(x: x + 0.5, y: y + 1)) },
                       with: .color(Color(white: 0.8)), lineWidth: 1.2)
        }
    }

    /// A short burst where a harpoon bit into the kraken.
    static func drawHarpoonImpact(_ ctx: GraphicsContext, _ s: CGSize, x: Double, y: Double, progress: Double) {
        let w = s.width, h = s.height
        let p = min(1, max(0, progress))
        let cx = x * w, cy = y * h
        let rr = (0.02 + 0.06 * p) * w
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)),
                   with: .color(Sea.foam.opacity(0.8 * (1 - p))), lineWidth: 2)
        // a spurt of dark ink
        for k in 0..<5 {
            let a = Double(k) / 5 * 2 * .pi
            let d = rr * 0.9
            let r2 = 2.5 * (1 - p)
            ctx.fill(Path(ellipseIn: CGRect(x: cx + cos(a) * d - r2, y: cy + sin(a) * d - r2, width: r2 * 2, height: r2 * 2)),
                     with: .color(Color(red: 0.20, green: 0.06, blue: 0.26).opacity(0.7 * (1 - p))))
        }
    }

    private static func drawTentacle(_ ctx: GraphicsContext, _ s: CGSize, x: Double, age: Double, seed: Int) {
        let w = s.width, h = s.height
        let strikeY = 0.74
        let cx = x * w

        var ext = 0.0
        if age < tentTele {
            // Telegraph: a pulsing red warning ring where it'll slam.
            let tp = age / tentTele
            let rr = (0.035 + 0.05 * tp) * w
            let warn = 0.5 + 0.5 * sin(age * 22)
            let cy = strikeY * h
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: cy - rr * 0.55, width: rr * 2, height: rr * 1.1)),
                       with: .color(Color.red.opacity(0.45 + 0.45 * warn)), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: cx - rr * 0.45, y: cy - rr * 0.28, width: rr * 0.9, height: rr * 0.55)),
                     with: .color(.red.opacity(0.12 * warn)))
            ext = 0.06
        } else if age < tentTele + tentStrike {
            let u = (age - tentTele) / tentStrike
            ext = u * u * (3 - 2 * u)                 // smoothstep up — the slam
        } else {
            let u = (age - tentTele - tentStrike) / tentRecede
            ext = max(0, 1 - u)                       // sink back
        }
        guard ext > 0.05 else { return }

        let baseY = 1.14 * h
        let tipY = (1.14 + (strikeY - 1.14) * ext) * h
        let segs = 11
        let phase = Double(seed % 100) * 0.1
        let tcol = Color(red: 0.40, green: 0.18, blue: 0.48)
        for i in 0...segs {
            let f = Double(i) / Double(segs)
            let yy = baseY + (tipY - baseY) * f
            let wavx = sin(f * 3.2 + age * 7 + phase) * 0.028 * w * ext
            let curl = (f * f) * 0.05 * w * sin(age * 5 + phase) * ext
            let xx = cx + wavx + curl
            let r = (0.05 * (1 - f) + 0.012) * w
            ctx.fill(Path(ellipseIn: CGRect(x: xx - r, y: yy - r, width: r * 2, height: r * 2)),
                     with: .color(tcol.opacity(0.95)))
            if i % 2 == 0 {                            // suckers
                ctx.fill(Path(ellipseIn: CGRect(x: xx - r * 0.3, y: yy - r * 0.3, width: r * 0.6, height: r * 0.6)),
                         with: .color(Sea.coral.opacity(0.5)))
            }
        }
        // White impact ring at the tip during the slam.
        if age >= tentTele && age < tentTele + tentStrike {
            let sp = (age - tentTele) / tentStrike
            let rr = (0.04 + 0.06 * sp) * w
            ctx.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: tipY - rr * 0.5, width: rr * 2, height: rr)),
                       with: .color(Sea.foam.opacity(0.55 * (1 - sp))), lineWidth: 2)
        }
    }

    // MARK: The Boot Beast ---------------------------------------------------

    private static let bootTele = 0.6, bootDrop = 0.4   // mirrors GameModel.bootThrowTele / bootThrowDrop

    /// A simple cartoon boot centred at `c`, body `size`, rotated by `rot`.
    private static func drawBootShape(_ ctx: GraphicsContext, at c: CGPoint, size: Double, rot: Double) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(rot))
        let brown = Color(red: 0.45, green: 0.29, blue: 0.17)
        let dark = Color(red: 0.28, green: 0.17, blue: 0.10)
        let s = size
        g.fill(Path(roundedRect: CGRect(x: -s * 0.30, y: -s * 0.55, width: s * 0.60, height: s * 0.95),
                                        cornerSize: CGSize(width: s * 0.12, height: s * 0.12)), with: .color(brown))   // leg
        g.fill(Path(roundedRect: CGRect(x: -s * 0.30, y: s * 0.10, width: s * 0.95, height: s * 0.36),
                                        cornerSize: CGSize(width: s * 0.12, height: s * 0.12)), with: .color(brown))   // foot/toe
        g.fill(Path(CGRect(x: -s * 0.32, y: s * 0.40, width: s * 1.0, height: s * 0.12)), with: .color(dark))          // sole
        g.fill(Path(CGRect(x: -s * 0.34, y: -s * 0.55, width: s * 0.68, height: s * 0.14)), with: .color(dark))        // cuff
        g.fill(Path(roundedRect: CGRect(x: -s * 0.22, y: -s * 0.42, width: s * 0.16, height: s * 0.74),
                                        cornerSize: CGSize(width: s * 0.06, height: s * 0.06)),
               with: .color(.white.opacity(0.10)))                                                                     // leg sheen
        for i in 0..<3 {                                                                                               // laces
            let ly = -s * 0.34 + Double(i) * s * 0.17
            g.fill(Path(ellipseIn: CGRect(x: -s * 0.055, y: ly, width: s * 0.11, height: s * 0.07)),
                   with: .color(Color(white: 0.85).opacity(0.7)))
        }
    }

    /// The boot-monster looming at the top, drawn UNDER the boat. `emerge` (0→1) raises it.
    static func drawBootBeast(_ ctx: GraphicsContext, _ s: CGSize, t: Double, emerge: Double) {
        let w = s.width, h = s.height
        let e = min(1, max(0, emerge)); let es = e * e * (3 - 2 * e)

        // Same dramatic entrance as the kraken — the water darkens and bubbles boil up as it rises.
        ctx.fill(Path(CGRect(origin: .zero, size: s)),
                 with: .color(Color(red: 0.05, green: 0.09, blue: 0.05).opacity(0.10 + 0.30 * e)))
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
            Gradient(colors: [.clear, Color(red: 0.03, green: 0.06, blue: 0.03).opacity(0.15 + 0.45 * e)]),
            center: CGPoint(x: w * 0.5, y: h * 0.45), startRadius: w * 0.22, endRadius: w * 0.92))
        let bubA = 0.25 + 0.75 * (1 - e)
        for k in 0..<16 {
            let bx = (Double((k * 37) % 100) / 100 + 0.05 * sin(t + Double(k))) * w
            let speed = 0.28 + Double(k % 4) * 0.09
            let prog = (t * speed + Double(k) * 0.17).truncatingRemainder(dividingBy: 1)
            let by = (1 - prog) * h
            let r = 1.2 + Double(k % 3) * 1.1
            ctx.stroke(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                       with: .color(Sea.foam.opacity(0.22 * bubA * sin(prog * .pi))), lineWidth: 1)
        }

        guard es > 0.02 else { return }
        let cx = w * 0.5 + sin(t * 1.2) * 0.02 * w
        let cy = (-0.04 + 0.17 * es) * h
        let bw = 0.44 * w * (0.7 + 0.3 * es), bh = 0.27 * h * (0.7 + 0.3 * es)
        let bodyLit = Color(red: 0.37, green: 0.49, blue: 0.28)     // sunlit mossy green
        let bodyDark = Color(red: 0.19, green: 0.29, blue: 0.15)
        let weed = Color(red: 0.16, green: 0.40, blue: 0.22)

        // Boots jammed all over the beast (behind the body) — varied sizes & angles.
        for k in 0..<7 {
            let ang = .pi * (0.08 + 0.84 * Double(k) / 6)
            let rad = bw * (0.46 + 0.06 * Double(k % 2))
            let bx = cx + cos(ang) * rad
            let by = cy + bh * 0.28 - sin(ang) * bh * 0.55
            let sz = (0.042 + 0.018 * Double(k % 3)) * w * es
            drawBootShape(ctx, at: CGPoint(x: bx, y: by), size: sz, rot: cos(ang) * 0.9 + sin(t * 3 + Double(k)) * 0.12)
        }

        // Lumpy junk-pile silhouette — a few overlapping blobs.
        let lumps: [(Double, Double, Double, Double)] = [
            (-0.34, -0.16, 0.5, 0.5), (0.32, -0.10, 0.55, 0.55),
            (-0.24, 0.18, 0.45, 0.4), (0.26, 0.2, 0.42, 0.42)
        ]
        for (lx, ly, lwf, lhf) in lumps {
            ctx.fill(Path(ellipseIn: CGRect(x: cx + lx * bw - bw * lwf / 2, y: cy - bh * 0.7 + ly * bh,
                                            width: bw * lwf, height: bh * lhf)),
                     with: .color(bodyDark.opacity(0.9 * es)))
        }
        // Main mass with a top-lit gradient.
        ctx.fill(Path(ellipseIn: CGRect(x: cx - bw / 2, y: cy - bh * 0.7, width: bw, height: bh)),
                 with: .linearGradient(Gradient(colors: [bodyLit.opacity(es), bodyDark.opacity(es)]),
                                       startPoint: CGPoint(x: cx, y: cy - bh * 0.7), endPoint: CGPoint(x: cx, y: cy + bh * 0.3)))

        // Barnacles (light) & mottling (dark).
        for k in 0..<12 {
            let hx = Double((k * 47 + 9) % 100) / 100 - 0.5
            let hy = Double((k * 29 + 5) % 100) / 100 - 0.5
            let sx = cx + hx * bw * 0.66, sy = cy + hy * bh * 0.5 - bh * 0.05
            let rr = (1.0 + Double(k % 3) * 0.8) * (0.6 + 0.4 * es)
            ctx.fill(Path(ellipseIn: CGRect(x: sx - rr, y: sy - rr, width: rr * 2, height: rr * 2)),
                     with: .color(k % 3 == 0 ? Color(white: 0.78).opacity(0.7 * es) : bodyDark.opacity(0.5 * es)))
        }

        // Seaweed draped over its head.
        for k in 0..<4 {
            let sx = cx + (Double(k) - 1.5) * bw * 0.22
            var wd = Path()
            wd.move(to: CGPoint(x: sx, y: cy - bh * 0.5))
            for i in 1...5 {
                let f = Double(i) / 5
                wd.addLine(to: CGPoint(x: sx + sin(t * 2 + Double(k) + f * 4) * 0.02 * w, y: cy - bh * 0.5 + f * bh * 0.7))
            }
            ctx.stroke(wd, with: .color(weed.opacity(0.8 * es)), lineWidth: 3 * (0.6 + 0.4 * es))
        }

        // Big googly eyes — heavy lids, wobbling pupils, a shine, and seaweed brows.
        for side in [-1.0, 1.0] {
            let ex = cx + side * bw * 0.19, ey = cy + bh * 0.0
            let er = 0.052 * w * es
            ctx.fill(Path(ellipseIn: CGRect(x: ex - er, y: ey - er, width: er * 2, height: er * 2)),
                     with: .color(.white.opacity(0.96 * es)))
            let pr = er * 0.5
            let px = ex + sin(t * 4 + side) * er * 0.35, py = ey + cos(t * 3) * er * 0.3
            ctx.fill(Path(ellipseIn: CGRect(x: px - pr, y: py - pr, width: pr * 2, height: pr * 2)),
                     with: .color(.black.opacity(0.9 * es)))
            ctx.fill(Path(ellipseIn: CGRect(x: px - er * 0.34, y: py - er * 0.34, width: pr * 0.7, height: pr * 0.7)),
                     with: .color(.white.opacity(0.9 * es)))                                          // shine
            ctx.fill(Path(ellipseIn: CGRect(x: ex - er, y: ey - er * 1.55, width: er * 2, height: er)),
                     with: .color(bodyDark.opacity(0.9 * es)))                                        // heavy lid
            var brow = Path()
            brow.move(to: CGPoint(x: ex - er, y: ey - er * 1.0))
            brow.addQuadCurve(to: CGPoint(x: ex + er, y: ey - er * 1.0), control: CGPoint(x: ex, y: ey - er * 1.9))
            ctx.stroke(brow, with: .color(weed.opacity(0.85 * es)), lineWidth: 3 * (0.6 + 0.4 * es))  // seaweed brow
        }

        // A goofy gap-toothed grin with a tongue.
        let mw = bw * 0.20, my = cy + bh * 0.18
        var mouth = Path()
        mouth.move(to: CGPoint(x: cx - mw, y: my))
        mouth.addQuadCurve(to: CGPoint(x: cx + mw, y: my), control: CGPoint(x: cx, y: my + bh * 0.22))
        mouth.addQuadCurve(to: CGPoint(x: cx - mw, y: my), control: CGPoint(x: cx, y: my + bh * 0.10))
        mouth.closeSubpath()
        ctx.fill(mouth, with: .color(Color(red: 0.16, green: 0.07, blue: 0.09).opacity(0.85 * es)))
        ctx.fill(Path(ellipseIn: CGRect(x: cx - mw * 0.4, y: my + bh * 0.05, width: mw * 0.8, height: bh * 0.1)),
                 with: .color(Color(red: 0.85, green: 0.35, blue: 0.40).opacity(0.8 * es)))            // tongue
        for tx in [-0.55, 0.25] {
            ctx.fill(Path(CGRect(x: cx + tx * mw, y: my, width: mw * 0.3, height: bh * 0.055)),
                     with: .color(.white.opacity(0.85 * es)))                                          // teeth
        }
    }

    /// Boots being lobbed at you — a warning ring, then a tumbling boot that lands with a splash.
    static func drawBootThrows(_ ctx: GraphicsContext, _ s: CGSize, throws bts: [BootThrow]) {
        let w = s.width, h = s.height
        let landY = 0.78
        for b in bts {
            let cx = b.x * w
            if b.age < bootTele {
                let tp = b.age / bootTele
                let rr = (0.035 + 0.05 * tp) * w
                let warn = 0.5 + 0.5 * sin(b.age * 22)
                ctx.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: landY * h - rr * 0.55, width: rr * 2, height: rr * 1.1)),
                           with: .color(Color.red.opacity(0.4 + 0.4 * warn)), lineWidth: 2)
            } else {
                let f = min(1, (b.age - bootTele) / bootDrop)
                let by = (0.18 + (landY - 0.18) * f) * h
                drawBootShape(ctx, at: CGPoint(x: cx, y: by), size: 0.06 * w, rot: b.age * 7)
                if f >= 1 {
                    let rr = 0.05 * w
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx - rr, y: landY * h - rr * 0.4, width: rr * 2, height: rr * 0.8)),
                               with: .color(Sea.foam.opacity(0.5)), lineWidth: 2)
                }
            }
        }
    }

    // MARK: Sleigh ride ------------------------------------------------------

    /// The towing fish out ahead and the taut line back to the boat. The line whitens then reddens
    /// as `strain` (0…1) climbs toward a snap.
    static func drawSleigh(_ ctx: GraphicsContext, _ s: CGSize, fishX: Double, fishY: Double,
                           boatX: Double, boatY: Double, strain: Double, t: Double) {
        let w = s.width, h = s.height
        let fp = CGPoint(x: fishX * w, y: fishY * h)
        let len = 0.16 * w

        // Churned-up water around the powering fish.
        for k in 0..<3 {
            let rp = (t * 1.5 + Double(k) * 0.33).truncatingRemainder(dividingBy: 1)
            let rr = (0.04 + rp * 0.08) * w
            ctx.stroke(Path(ellipseIn: CGRect(x: fp.x - rr, y: fp.y - rr * 0.5, width: rr * 2, height: rr)),
                       with: .color(Sea.foam.opacity(0.30 * (1 - rp))), lineWidth: 1.5)
        }
        // A foam crest breaking at its head (it's surging up the screen).
        let crest = fp.y - len * 0.5
        ctx.fill(Path(ellipseIn: CGRect(x: fp.x - len * 0.28, y: crest - 4, width: len * 0.56, height: 9)),
                 with: .color(Sea.foam.opacity(0.55)))

        // The taut line from rod tip to fish — straight-ish, thicker & redder under strain.
        let tip = rodTip(boatX: boatX, boatY: boatY)
        let start = CGPoint(x: tip.x * w, y: tip.y * h)
        var line = Path()
        line.move(to: start)
        let sag = 8 * (1 - strain)                                    // a tight line barely bows
        line.addQuadCurve(to: fp, control: CGPoint(x: (start.x + fp.x) / 2 + sag, y: (start.y + fp.y) / 2))
        let strainCol = Color(red: 1, green: 1 - strain * 0.75, blue: 1 - strain * 0.9)
        ctx.stroke(line, with: .color(strainCol.opacity(0.95)), lineWidth: 1.8 + strain * 2.0)
        if strain > 0.6 {                                            // it shudders when near snapping
            ctx.stroke(line, with: .color(.white.opacity((strain - 0.6) * 1.5 * (0.5 + 0.5 * sin(t * 30)))),
                       lineWidth: 0.8)
        }

        // The big fish itself, leaning into its run.
        let lean = sin(t * 6) * 0.10 + (fishX - boatX) * 0.6
        drawTowFish(ctx, at: fp, len: len, lean: lean, t: t)
    }

    private static func drawTowFish(_ ctx: GraphicsContext, at c: CGPoint, len: Double, lean: Double, t: Double) {
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(lean))
        let bl = len, hw = len * 0.21          // body length & half-width
        let navy = Color(red: 0.10, green: 0.20, blue: 0.42)   // dark back
        let blue = fishColor(.tuna)                            // flank
        let finlet = Color(red: 1.0, green: 0.82, blue: 0.26)  // signature yellow finlets
        let sw = sin(t * 8) * hw * 0.5         // tail/body swish

        // --- Lunate (crescent) tail, behind the body ---
        var tail = Path()
        tail.move(to: CGPoint(x: 0, y: bl * 0.36))
        tail.addQuadCurve(to: CGPoint(x: hw * 1.25 + sw, y: bl * 0.64), control: CGPoint(x: hw * 0.45, y: bl * 0.42))
        tail.addQuadCurve(to: CGPoint(x: sw * 0.5, y: bl * 0.48), control: CGPoint(x: hw * 0.55 + sw, y: bl * 0.60))
        tail.addQuadCurve(to: CGPoint(x: -hw * 1.25 + sw, y: bl * 0.64), control: CGPoint(x: -hw * 0.55 + sw, y: bl * 0.60))
        tail.addQuadCurve(to: CGPoint(x: 0, y: bl * 0.36), control: CGPoint(x: -hw * 0.45, y: bl * 0.42))
        tail.closeSubpath()
        g.fill(tail, with: .color(navy))

        // --- Pectoral fins, swept back from the shoulders ---
        let pf = sin(t * 6) * hw * 0.12
        for side in [-1.0, 1.0] {
            var pec = Path()
            pec.move(to: CGPoint(x: side * hw * 0.55, y: -bl * 0.04))
            pec.addQuadCurve(to: CGPoint(x: side * hw * 1.5, y: bl * 0.16 + pf),
                             control: CGPoint(x: side * hw * 1.25, y: bl * 0.02))
            pec.addQuadCurve(to: CGPoint(x: side * hw * 0.5, y: bl * 0.08),
                             control: CGPoint(x: side * hw * 0.95, y: bl * 0.12))
            pec.closeSubpath()
            g.fill(pec, with: .color(blue.opacity(0.7)))
        }

        // --- Fusiform body (pointed snout up, narrow caudal peduncle) ---
        var body = Path()
        body.move(to: CGPoint(x: 0, y: -bl * 0.5))                                   // snout
        body.addQuadCurve(to: CGPoint(x: hw, y: -bl * 0.10), control: CGPoint(x: hw * 0.95, y: -bl * 0.40))
        body.addQuadCurve(to: CGPoint(x: hw * 0.30, y: bl * 0.30), control: CGPoint(x: hw, y: bl * 0.10))
        body.addLine(to: CGPoint(x: 0, y: bl * 0.36))
        body.addLine(to: CGPoint(x: -hw * 0.30, y: bl * 0.30))
        body.addQuadCurve(to: CGPoint(x: -hw, y: -bl * 0.10), control: CGPoint(x: -hw, y: bl * 0.10))
        body.addQuadCurve(to: CGPoint(x: 0, y: -bl * 0.5), control: CGPoint(x: -hw * 0.95, y: -bl * 0.40))
        body.closeSubpath()
        g.fill(body, with: .linearGradient(Gradient(colors: [navy, blue, navy]),
                                           startPoint: CGPoint(x: 0, y: -bl * 0.5),
                                           endPoint: CGPoint(x: 0, y: bl * 0.36)))

        // --- Yellow finlets running down toward the tail ---
        for k in 0..<4 {
            let f = Double(k) / 4
            let y = bl * (0.12 + f * 0.18)
            let x = hw * (0.78 - f * 0.5)
            for side in [-1.0, 1.0] {
                var fin = Path()
                fin.move(to: CGPoint(x: side * x, y: y))
                fin.addLine(to: CGPoint(x: side * (x + hw * 0.28), y: y + bl * 0.015))
                fin.addLine(to: CGPoint(x: side * x, y: y + bl * 0.05))
                fin.closeSubpath()
                g.fill(fin, with: .color(finlet.opacity(0.9)))
            }
        }

        // --- Metallic sheen along one flank + a spine line ---
        g.fill(Path(ellipseIn: CGRect(x: -hw * 0.55, y: -bl * 0.22, width: hw * 0.5, height: bl * 0.5)),
               with: .color(.white.opacity(0.16)))
        var spine = Path()
        spine.move(to: CGPoint(x: 0, y: -bl * 0.42)); spine.addLine(to: CGPoint(x: 0, y: bl * 0.30))
        g.stroke(spine, with: .color(navy.opacity(0.6)), lineWidth: max(1, hw * 0.12))

        // --- Eyes near the head (one each side) ---
        for side in [-1.0, 1.0] {
            g.fill(Path(ellipseIn: CGRect(x: side * hw * 0.5 - 2.2, y: -bl * 0.30, width: 4.4, height: 4.4)),
                   with: .color(.black.opacity(0.8)))
        }
    }

    // MARK: Finish line ------------------------------------------------------

    /// A checkered finish banner floating across the water at `y` (normalized). It drifts down toward
    /// the boat as the level goal nears; `near` (0…1) brightens its glow as it closes in.
    static func drawFinishLine(_ ctx: GraphicsContext, _ s: CGSize, y: Double, t: Double, near: Double) {
        let w = s.width, h = s.height
        guard y > -0.04, y < 1.06 else { return }
        let cy = y * h
        let band = max(10.0, 0.052 * h)
        let cols = 9
        let cellW = w / Double(cols)
        let rh = band / 2
        func wob(_ c: Int) -> Double { sin(Double(c) * 0.7 + t * 2.2) * (0.012 * h) }

        // Soft glow on the water, stronger as the line closes in on the boat.
        ctx.fill(Path(CGRect(x: 0, y: cy - band, width: w, height: band * 2)),
                 with: .linearGradient(
                    Gradient(colors: [.clear, Sea.foam.opacity(0.10 + 0.22 * near), .clear]),
                    startPoint: CGPoint(x: 0, y: cy - band), endPoint: CGPoint(x: 0, y: cy + band)))

        // Two rows of checkered cells with a gentle wave.
        let dark = Color(white: 0.08).opacity(0.88)
        let light = Color.white.opacity(0.95)
        for c in 0..<cols {
            let x = Double(c) * cellW
            let dy = wob(c)
            for r in 0..<2 {
                let on = (c + r) % 2 == 0
                let yy = cy - band / 2 + Double(r) * rh + dy
                ctx.fill(Path(CGRect(x: x, y: yy, width: cellW + 1, height: rh + 0.5)),
                         with: .color(on ? light : dark))
            }
        }
        // Crisp top & bottom edges following the same wave.
        for edge in [-band / 2, band / 2] {
            var line = Path()
            for c in 0...cols {
                let pt = CGPoint(x: Double(c) * cellW, y: cy + edge + wob(min(c, cols - 1)))
                if c == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            ctx.stroke(line, with: .color(.white.opacity(0.55)), lineWidth: 1)
        }

        // A little pennant buoy at each end so it reads as a gate.
        for side in [0.0, 1.0] {
            let px = side == 0 ? 0.06 * w : 0.94 * w
            let topY = cy - band * 0.5 - 0.05 * h + wob(side == 0 ? 0 : cols - 1)
            var post = Path()
            post.move(to: CGPoint(x: px, y: topY))
            post.addLine(to: CGPoint(x: px, y: cy + band * 0.5))
            ctx.stroke(post, with: .color(Color(white: 0.92)), lineWidth: 2.4)
            ctx.stroke(post, with: .color(Sea.deep.opacity(0.5)), lineWidth: 0.8)
            // fluttering triangular flag
            let fld = (side == 0 ? 1.0 : -1.0)
            let flutter = sin(t * 6 + side * 2) * 0.012 * w
            var flag = Path()
            flag.move(to: CGPoint(x: px, y: topY))
            flag.addLine(to: CGPoint(x: px + fld * 0.075 * w + flutter, y: topY + 0.012 * h))
            flag.addLine(to: CGPoint(x: px, y: topY + 0.028 * h))
            flag.closeSubpath()
            ctx.fill(flag, with: .color(Sea.coral.opacity(0.95)))
        }
    }

    // MARK: Line + hook ------------------------------------------------------

    /// The cast line going out (top-down) — a warm golden line from the rod tip to the hook point.
    static func drawLine(_ ctx: GraphicsContext, _ s: CGSize, from boatX: Double, boatY: Double,
                         to hook: CGPoint, tension: Double) {
        let tip = rodTip(boatX: boatX, boatY: boatY)
        let start = CGPoint(x: tip.x * s.width, y: tip.y * s.height)
        let end = CGPoint(x: hook.x * s.width, y: hook.y * s.height)
        var line = Path()
        line.move(to: start)
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + 4)
        line.addQuadCurve(to: end, control: mid)
        ctx.stroke(line, with: .color(Sea.gold.opacity(0.95)), lineWidth: 2)
        ctx.stroke(line, with: .color(.white.opacity(0.3)), lineWidth: 0.8)   // sheen
    }

    // MARK: Fish (drawn at the hook while reeling) --------------------------

    static func fishColor(_ kind: FishKind) -> Color {
        switch kind {
        case .herring:  return Color(red: 0.78, green: 0.85, blue: 0.92)
        case .mackerel: return Color(red: 0.35, green: 0.70, blue: 0.62)
        case .cod:      return Color(red: 0.62, green: 0.60, blue: 0.42)
        case .salmon:   return Color(red: 0.96, green: 0.55, blue: 0.45)
        case .tuna:     return Color(red: 0.30, green: 0.45, blue: 0.80)
        case .boot:     return Color(red: 0.40, green: 0.30, blue: 0.24)
        }
    }

    static func drawFish(_ ctx: GraphicsContext, _ s: CGSize, _ kind: FishKind, at hook: CGPoint, wiggle: Double) {
        let c = CGPoint(x: hook.x * s.width, y: hook.y * s.height)
        let scale = (0.6 + kind.fight * 0.18)
        let bw = 0.085 * s.width * scale
        let bh = bw * 0.5
        let w = sin(wiggle * 6) * bh * 0.25   // tail wiggle

        let color = fishColor(kind)
        // Body.
        let body = Path(ellipseIn: CGRect(x: c.x - bw / 2, y: c.y - bh / 2 + w, width: bw, height: bh))
        ctx.fill(body, with: .color(color))
        // Tail (points down, away from the boat).
        var tail = Path()
        tail.move(to: CGPoint(x: c.x, y: c.y + bh * 0.5 + w))
        tail.addLine(to: CGPoint(x: c.x - bw * 0.28, y: c.y + bh + w * 1.4))
        tail.addLine(to: CGPoint(x: c.x + bw * 0.28, y: c.y + bh + w * 1.4))
        tail.closeSubpath()
        ctx.fill(tail, with: .color(color.opacity(0.85)))
        // Eye.
        let eye = Path(ellipseIn: CGRect(x: c.x - bw * 0.28, y: c.y - bh * 0.18, width: 3, height: 3))
        ctx.fill(eye, with: .color(.black.opacity(0.8)))
    }

    // MARK: Harbour (the intro — a long pier, other boats, you head out to the right) ----

    static func drawHarbor(_ ctx: GraphicsContext, _ s: CGSize, offset: Double) {
        let w = s.width, h = s.height
        let scroll = offset                             // driven at ~sea speed by the model
        let wood = Color(red: 0.46, green: 0.31, blue: 0.18)
        let woodDark = Color(red: 0.32, green: 0.21, blue: 0.12)

        // --- The shore the pier is rooted to (a strip of land at the bottom, recedes as you head out).
        let sand = Color(red: 0.86, green: 0.78, blue: 0.56)
        let sandDark = Color(red: 0.74, green: 0.65, blue: 0.45)
        let grass = Color(red: 0.47, green: 0.59, blue: 0.37)
        let grassDark = Color(red: 0.35, green: 0.47, blue: 0.27)
        let baseY = (0.84 + scroll) * h                 // wavy waterline, slides down as you leave
        let amp = 0.013 * h, steps = 16
        if baseY < h + amp {                            // only while any shore is on-screen
            func shoreFill(_ topY: Double, _ ph: Double) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: h + 80))
                p.addLine(to: CGPoint(x: 0, y: topY + sin(ph) * amp))
                for i in 0...steps {
                    let fx = Double(i) / Double(steps)
                    p.addLine(to: CGPoint(x: fx * w, y: topY + sin(fx * 7 + ph) * amp))
                }
                p.addLine(to: CGPoint(x: w, y: h + 80))
                p.closeSubpath()
                return p
            }
            // Soft shallow band in the water just off the beach.
            ctx.fill(shoreFill(baseY - 0.05 * h, 0.6), with: .linearGradient(
                Gradient(colors: [Sea.shallow.opacity(0), Sea.shallow.opacity(0.5)]),
                startPoint: CGPoint(x: 0, y: baseY - 0.05 * h), endPoint: CGPoint(x: 0, y: baseY)))
            // Sand, then grass over the inland part.
            ctx.fill(shoreFill(baseY, 0.6), with: .linearGradient(
                Gradient(colors: [sand, sandDark]),
                startPoint: CGPoint(x: 0, y: baseY), endPoint: CGPoint(x: 0, y: baseY + 0.13 * h)))
            ctx.fill(shoreFill(baseY + 0.06 * h, 1.3), with: .linearGradient(
                Gradient(colors: [grass, grassDark]),
                startPoint: CGPoint(x: 0, y: baseY + 0.05 * h), endPoint: CGPoint(x: 0, y: h)))
            // Foam at the waterline (matches the sand's top wave).
            var foamLine = Path()
            for i in 0...steps {
                let fx = Double(i) / Double(steps)
                let yy = baseY + sin(fx * 7 + 0.6) * amp
                if i == 0 { foamLine.move(to: CGPoint(x: fx * w, y: yy)) }
                else { foamLine.addLine(to: CGPoint(x: fx * w, y: yy)) }
            }
            ctx.stroke(foamLine, with: .color(Sea.foam.opacity(0.45)), lineWidth: 6)
            ctx.stroke(foamLine, with: .color(.white.opacity(0.7)), lineWidth: 2)
            // A few rocks on the beach.
            for (rx, ry, rr, sd) in [(0.58, 0.035, 0.028, 11), (0.74, 0.075, 0.020, 23), (0.33, 0.02, 0.016, 7)] {
                let cc = CGPoint(x: rx * w, y: baseY + ry * h)
                let body = rockShape(cc, rr * w, seed: sd)
                ctx.fill(body, with: .linearGradient(Gradient(colors: [rockLight, rockDark]),
                         startPoint: CGPoint(x: cc.x, y: cc.y - rr * w), endPoint: CGPoint(x: cc.x, y: cc.y + rr * w)))
                ctx.stroke(body, with: .color(rockDark.opacity(0.5)), lineWidth: 1)
            }
            // Tufts of grass.
            for (gx, gy) in [(0.50, 0.09), (0.66, 0.105), (0.88, 0.08), (0.42, 0.12)] {
                let cx0 = gx * w, cy0 = baseY + gy * h
                for d in [-3.0, 0.0, 3.0] {
                    var bl = Path()
                    bl.move(to: CGPoint(x: cx0 + d, y: cy0))
                    bl.addQuadCurve(to: CGPoint(x: cx0 + d + 2, y: cy0 - 7), control: CGPoint(x: cx0 + d - 1, y: cy0 - 4))
                    ctx.stroke(bl, with: .color(grassDark.opacity(0.7)), lineWidth: 1.2)
                }
            }
        }

        // Long pier down the left — spans the screen (and a bit beyond) so it reads as long.
        let pierX = 0.15 * w, pierW = 0.13 * w
        let top = (-0.1 + scroll) * h, bot = (1.25 + scroll) * h
        ctx.fill(Path(roundedRect: CGRect(x: pierX, y: top, width: pierW, height: bot - top), cornerRadius: 4),
                 with: .color(wood))
        var py = top                                    // planks down the pier
        while py < bot {
            var ln = Path(); ln.move(to: CGPoint(x: pierX, y: py)); ln.addLine(to: CGPoint(x: pierX + pierW, y: py))
            ctx.stroke(ln, with: .color(woodDark.opacity(0.6)), lineWidth: 1)
            py += 0.07 * h
        }
        ctx.fill(Path(CGRect(x: pierX + pierW - 2, y: top, width: 2, height: bot - top)),
                 with: .color(.white.opacity(0.12)))    // edge highlight
        for k in 0..<6 {                                // mooring posts on the water side
            let postY = (-0.05 + Double(k) * 0.26 + scroll) * h
            ctx.fill(Path(CGRect(x: pierX + pierW + 0.015 * w, y: postY, width: 0.02 * w, height: 0.05 * h)),
                     with: .color(woodDark))
        }

        // Other boats moored in the harbour.
        let docked: [(Double, Double, Color)] = [
            (0.40, 0.18, Sea.coral),
            (0.40, 0.66, Sea.gold),
            (0.40, 1.06, Sea.teal),
            (0.80, 0.40, Color(red: 0.80, green: 0.52, blue: 0.42)),
        ]
        for (bx, by, col) in docked {
            miniBoat(ctx, s, x: bx * w, y: (by + scroll) * h, color: col)
        }
    }

    private static func miniBoat(_ ctx: GraphicsContext, _ s: CGSize, x: Double, y: Double, color: Color) {
        boatBody(ctx, at: CGPoint(x: x, y: y), hw: 0.032 * s.width, hh: 0.043 * s.height,
                 bank: 0, hull: color)
    }

    // MARK: Aim marker (where the line will drop while casting) --------------

    /// The target reticle where the line will land — a dashed, slowly-spinning ring + centre dot.
    static func drawAim(_ ctx: GraphicsContext, _ s: CGSize, at point: CGPoint, locked: Bool, t: Double) {
        let c = CGPoint(x: point.x * s.width, y: point.y * s.height)
        let r = (locked ? 0.062 : 0.05) * s.width
        let color = locked ? Sea.gold : Color.white.opacity(0.85)
        let ring = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.stroke(ring, with: .color(color),
                   style: StrokeStyle(lineWidth: locked ? 3 : 2, dash: [5, 4], dashPhase: t * 12))
        let dr = locked ? 4.0 : 3.0
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - dr, y: c.y - dr, width: dr * 2, height: dr * 2)),
                 with: .color(color))
    }

    // MARK: Crash splash -----------------------------------------------------

    static func drawSplash(_ ctx: GraphicsContext, _ s: CGSize, x: Double, y: Double, progress p: Double) {
        let c = CGPoint(x: x * s.width, y: y * s.height)
        let fade = max(0, 1 - p)

        for k in 0..<2 {                                       // expanding foam rings
            let pp = max(0, p - Double(k) * 0.18)
            let r = (0.03 + pp * 0.20) * s.width
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 0.7, width: r * 2, height: r * 1.4)),
                       with: .color(Sea.foam.opacity(0.9 * max(0, 1 - pp))),
                       lineWidth: max(1, 4 * (1 - pp)))
        }
        let n = 9                                              // droplets flying out
        let rr = (0.02 + p * 0.22) * s.width
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let d = rr * (0.7 + 0.3 * sin(a * 3))
            let px = c.x + cos(a) * d
            let py = c.y + sin(a) * d * 0.7 - p * 0.04 * s.height
            let sz = max(1.5, 5 * fade)
            ctx.fill(Path(ellipseIn: CGRect(x: px - sz / 2, y: py - sz / 2, width: sz, height: sz)),
                     with: .color(Sea.foam.opacity(fade)))
        }
        let fr = (0.05 + p * 0.05) * s.width                   // central flash
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - fr, y: c.y - fr, width: fr * 2, height: fr * 2)),
                 with: .color(.white.opacity(0.5 * fade)))
    }

    // MARK: First-person reeling (the rod bends, line in the water, fish below) ----

    static func drawReelingFP(_ ctx: GraphicsContext, _ s: CGSize, model: GameModel) {
        let w = s.width, h = s.height
        let p = model.reelProgress
        let inZone = model.markerInZone
        let t = model.elapsed
        let surfaceY = 0.30 * h

        // --- Underwater scene -------------------------------------------------
        let pal = seaColors(model.timeOfDay)
        let night = nightAmount(model.timeOfDay)
        ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .linearGradient(
            Gradient(colors: [pal.shallow, pal.water, pal.deep]),
            startPoint: CGPoint(x: 0, y: surfaceY), endPoint: CGPoint(x: 0, y: h)))
        // Hazy sky above the waterline — shifts from day blue toward a dark night sky.
        let skyTop = Color(red: mix(0.55, 0.05, night), green: mix(0.80, 0.08, night), blue: mix(0.92, 0.20, night))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: surfaceY)),
                 with: .linearGradient(Gradient(colors: [skyTop, pal.shallow]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: surfaceY)))
        // God rays slanting down from the surface.
        for k in 0..<3 {
            let rx = (0.22 + Double(k) * 0.30) * w + sin(t * 0.5 + Double(k)) * 6
            var ray = Path()
            ray.move(to: CGPoint(x: rx, y: surfaceY))
            ray.addLine(to: CGPoint(x: rx + 0.09 * w, y: surfaceY))
            ray.addLine(to: CGPoint(x: rx + 0.20 * w, y: h))
            ray.addLine(to: CGPoint(x: rx - 0.04 * w, y: h))
            ray.closeSubpath()
            ctx.fill(ray, with: .color(Sea.foam.opacity(0.05)))
        }
        // Rising bubbles.
        for k in 0..<7 {
            let bx = (0.30 + Double((k * 37) % 50) / 100.0) * w
            let speed = 0.05 + Double(k % 3) * 0.02
            let by = surfaceY + (1 - (t * speed + Double(k) * 0.13).truncatingRemainder(dividingBy: 1)) * (h - surfaceY)
            let r = 1.5 + Double(k % 3)
            ctx.stroke(Path(ellipseIn: CGRect(x: bx, y: by, width: r * 2, height: r * 2)),
                       with: .color(Sea.foam.opacity(0.18)), lineWidth: 1)
        }
        // Shimmering surface line.
        var surf = Path(); surf.move(to: CGPoint(x: 0, y: surfaceY))
        for i in 0...10 {
            let fx = Double(i) / 10
            surf.addLine(to: CGPoint(x: fx * w, y: surfaceY + 4 * sin((fx * 6 + t) * .pi)))
        }
        ctx.stroke(surf, with: .color(Sea.foam.opacity(0.55)), lineWidth: 2)

        // --- The hooked fish, pulled up & fighting ---------------------------
        let struggle = inZone ? 0.25 : 1.0                      // thrashes harder when it's winning
        let sway = sin(t * (4 + struggle * 5)) * (0.04 + struggle * 0.06)
        let mouth = CGPoint(x: (0.52 + sway) * w, y: (0.80 - 0.44 * p) * h)
        let landing = model.phase == .surfacing && model.surfaceCaught
        let chomped = model.predatorActive && model.predatorProgress > 0.55      // the predator's chomp moment
        let specialEaten = chomped || (landing && model.surfaceProgress > 0.2)   // specials just vanish on land
        if let sp = model.hookedSpecial, !specialEaten {
            drawSpecial(ctx, sp, at: mouth, size: 0.17 * w * (0.7 + 0.5 * p), t: t)
        } else if let kind = model.hooked, !chomped, !landing {
            // Underwater, fighting on the line. (On a successful land it instead bursts from the splash, below.)
            let size = (0.13 + kind.fight * 0.05) * w * (0.7 + 0.5 * p)   // grows as it nears
            drawFightingFish(ctx, kind: kind, mouth: mouth, size: size, struggle: struggle, t: t)
        }
        if model.predatorActive {
            drawPredator(ctx, s, target: mouth, progress: model.predatorProgress, t: t)
        }
        // Danger glow when a mine is on the line — telegraphs it so you can let it go.
        if model.hookedSpecial == .mine {
            let warn = 0.5 + 0.5 * sin(t * 6)
            ctx.fill(Path(CGRect(origin: .zero, size: s)), with: .radialGradient(
                Gradient(colors: [.clear, Color.red.opacity(0.05 + 0.16 * warn)]),
                center: CGPoint(x: w * 0.5, y: h * 0.5), startRadius: w * 0.35, endRadius: w * 0.9))
        }

        // --- Rod, reel & line ------------------------------------------------
        let bend = min(1, (1 - p) * 0.35 + (inZone ? 0.10 : 0.45))
        let base = CGPoint(x: 0.90 * w, y: 1.05 * h)
        let tip  = CGPoint(x: (0.66 - 0.18 * bend) * w, y: (0.20 + 0.10 * bend) * h)
        let ctrl = CGPoint(x: (0.92 - 0.22 * bend) * w, y: 0.55 * h)
        var rod = Path(); rod.move(to: base); rod.addQuadCurve(to: tip, control: ctrl)
        ctx.stroke(rod, with: .color(.black.opacity(0.30)), lineWidth: 7)
        ctx.stroke(rod, with: .color(Color(red: 0.20, green: 0.16, blue: 0.12)), lineWidth: 5)
        ctx.stroke(rod, with: .color(Color(red: 0.45, green: 0.34, blue: 0.23)), lineWidth: 2.5)
        for f in [0.4, 0.7] {                                   // line guides
            let gp = CGPoint(x: base.x + (tip.x - base.x) * f, y: base.y + (tip.y - base.y) * f)
            ctx.stroke(Path(ellipseIn: CGRect(x: gp.x - 3, y: gp.y - 3, width: 6, height: 6)),
                       with: .color(Color(white: 0.7)), lineWidth: 1)
        }
        ctx.fill(Path(ellipseIn: CGRect(x: 0.80 * w, y: 0.84 * h, width: 0.11 * w, height: 0.11 * w)),
                 with: .color(Color(white: 0.45)))              // reel
        ctx.fill(Path(ellipseIn: CGRect(x: 0.835 * w, y: 0.875 * h, width: 0.04 * w, height: 0.04 * w)),
                 with: .color(Color(white: 0.72)))

        // Line rod-tip → fish mouth (white holding, coral slipping) + surface entry ripple.
        var line = Path(); line.move(to: tip)
        line.addQuadCurve(to: mouth, control: CGPoint(x: (tip.x + mouth.x) / 2 + 4, y: (tip.y + mouth.y) / 2))
        let lineCol: Color = model.hookedSpecial == .mine ? .red : (inZone ? .white.opacity(0.95) : Sea.coral)
        ctx.stroke(line, with: .color(lineCol), lineWidth: 1.4)
        ctx.stroke(Path(ellipseIn: CGRect(x: mouth.x - 12, y: surfaceY - 4, width: 24, height: 9)),
                   with: .color(Sea.foam.opacity(0.35)), lineWidth: 1)

        // Catch splash — a big water crown erupts where the fish came out…
        if landing {
            drawCatchSplash(ctx, s, center: CGPoint(x: mouth.x, y: surfaceY), progress: model.surfaceProgress)
            // …and the fish bursts up out of it, arcing off toward the boat (not just empty water).
            if let kind = model.hooked {
                drawCatchBurst(ctx, s, kind: kind, from: CGPoint(x: mouth.x, y: surfaceY),
                               progress: model.surfaceProgress, t: t)
            }
        }

        // --- The fight gauge -------------------------------------------------
        drawFightGauge(ctx, s, marker: model.marker, zoneCenter: model.zoneCenter,
                       zoneHalf: model.zoneHalfWidth, inZone: inZone)
    }

    /// The caught fish leaping up out of the catch splash — swells out of the crown, banks, then exits & fades.
    private static func drawCatchBurst(_ ctx: GraphicsContext, _ s: CGSize, kind: FishKind,
                                       from: CGPoint, progress: Double, t: Double) {
        let w = s.width, h = s.height
        let p = max(0, min(1, progress))
        let y = from.y - p * (from.y + 0.16 * h)                  // surface → up off the top edge
        let x = from.x + sin(p * .pi) * 0.05 * w                  // a gentle lateral arc
        let size = (0.14 + kind.fight * 0.05) * w * (0.85 + 0.35 * sin(p * .pi))   // swells out of the crown
        let lean = sin(p * .pi) * 0.5 + sin(t * 9) * 0.08         // bank through the leap + a little wriggle
        let fade = p < 0.7 ? 1.0 : max(0, 1 - (p - 0.7) / 0.3)
        var c = ctx
        c.opacity = fade
        drawFightingFish(c, kind: kind, mouth: CGPoint(x: x, y: y), size: size, struggle: 0.25, t: t, lean: lean)
    }

    /// Vertical balance gauge on the left: a drifting safe zone + your Crown-controlled marker.
    private static func drawFightGauge(_ ctx: GraphicsContext, _ s: CGSize,
                                       marker: Double, zoneCenter: Double, zoneHalf: Double, inZone: Bool) {
        let w = s.width, h = s.height
        let gx = 0.085 * w, gw = 0.075 * w
        let gTop = 0.34 * h, gH = 0.50 * h          // starts below the score, so it's not in the way
        func y(_ v: Double) -> Double { gTop + min(1, max(0, v)) * gH }

        // Track.
        ctx.fill(Path(roundedRect: CGRect(x: gx, y: gTop, width: gw, height: gH), cornerRadius: gw / 2),
                 with: .color(.black.opacity(0.38)))
        // Moving safe zone.
        let zTop = y(zoneCenter - zoneHalf), zBot = y(zoneCenter + zoneHalf)
        ctx.fill(Path(roundedRect: CGRect(x: gx, y: zTop, width: gw, height: zBot - zTop), cornerRadius: gw / 2),
                 with: .color(inZone ? Sea.teal : Sea.teal.opacity(0.45)))
        // Marker (your control).
        let my = y(marker)
        ctx.fill(Path(roundedRect: CGRect(x: gx - 3, y: my - 4, width: gw + 6, height: 8), cornerRadius: 4),
                 with: .color(inZone ? Sea.gold : Sea.foam))
    }

    // MARK: A detailed, species-distinct fish — hooked, head-up, thrashing -----

    private struct FishStyle {
        let len: Double; let width: Double
        let body: Color; let belly: Color; let fin: Color
        let forked: Bool; let stripes: Bool
    }

    private static func fishStyle(_ kind: FishKind) -> FishStyle {
        switch kind {
        case .herring:  return FishStyle(len: 0.95, width: 0.22,
                                         body: Color(red: 0.74, green: 0.82, blue: 0.90), belly: .white,
                                         fin: Color(red: 0.60, green: 0.70, blue: 0.82), forked: true, stripes: false)
        case .mackerel: return FishStyle(len: 1.05, width: 0.24,
                                         body: Color(red: 0.32, green: 0.62, blue: 0.55), belly: Color(red: 0.86, green: 0.90, blue: 0.86),
                                         fin: Color(red: 0.20, green: 0.45, blue: 0.42), forked: true, stripes: true)
        case .cod:      return FishStyle(len: 1.00, width: 0.34,
                                         body: Color(red: 0.60, green: 0.58, blue: 0.40), belly: Color(red: 0.85, green: 0.83, blue: 0.70),
                                         fin: Color(red: 0.45, green: 0.43, blue: 0.30), forked: false, stripes: false)
        case .salmon:   return FishStyle(len: 1.10, width: 0.30,
                                         body: Color(red: 0.93, green: 0.52, blue: 0.45), belly: Color(red: 0.97, green: 0.80, blue: 0.72),
                                         fin: Color(red: 0.75, green: 0.38, blue: 0.34), forked: false, stripes: false)
        case .tuna:     return FishStyle(len: 1.28, width: 0.30,
                                         body: Color(red: 0.26, green: 0.42, blue: 0.72), belly: Color(red: 0.80, green: 0.85, blue: 0.90),
                                         fin: Color(red: 0.96, green: 0.80, blue: 0.30), forked: true, stripes: false)   // yellow finlets
        case .boot:     return FishStyle(len: 1.0, width: 0.4,
                                         body: Color(red: 0.34, green: 0.26, blue: 0.20), belly: .black, fin: .black,
                                         forked: false, stripes: false)
        }
    }

    private static func drawFightingFish(_ ctx: GraphicsContext, kind: FishKind, mouth: CGPoint,
                                         size: Double, struggle: Double, t: Double, lean: Double = 0) {
        var c = ctx
        c.translateBy(x: mouth.x, y: mouth.y)

        if kind == .boot { drawBoot(c, size: size, t: t); return }

        // Head sits at the origin (the line's end) and points up; thrashing swings the body. `lean`
        // tilts the whole fish (used to bank it through a leap as it bursts out of the water).
        let swing = sin(t * (5 + struggle * 6)) * (0.18 + struggle * 0.5)
        c.rotate(by: .radians(-1.05 + swing + lean))

        let st = fishStyle(kind)
        let len = size * st.len, wid = size * st.width   // body runs along −x (so it hangs down from the head)

        // Body.
        var body = Path()
        body.move(to: CGPoint(x: 0, y: 0))
        body.addQuadCurve(to: CGPoint(x: -len, y: 0), control: CGPoint(x: -len * 0.4, y: -wid))
        body.addQuadCurve(to: CGPoint(x: 0, y: 0), control: CGPoint(x: -len * 0.4, y: wid))
        c.fill(body, with: .color(st.body))
        // Belly highlight.
        var belly = Path()
        belly.move(to: CGPoint(x: -len * 0.05, y: 0))
        belly.addQuadCurve(to: CGPoint(x: -len * 0.9, y: 0), control: CGPoint(x: -len * 0.4, y: wid * 0.85))
        belly.closeSubpath()
        c.fill(belly, with: .color(st.belly.opacity(0.6)))
        // Stripes (mackerel).
        if st.stripes {
            for k in 1...5 {
                let sx = -len * Double(k) / 6.5
                var stripe = Path()
                stripe.move(to: CGPoint(x: sx, y: -wid * 0.45))
                stripe.addQuadCurve(to: CGPoint(x: sx - 3, y: wid * 0.1), control: CGPoint(x: sx - 5, y: -wid * 0.2))
                c.stroke(stripe, with: .color(.black.opacity(0.30)), lineWidth: 2)
            }
        }
        // Dorsal + pectoral fins.
        var dorsal = Path()
        dorsal.move(to: CGPoint(x: -len * 0.32, y: -wid * 0.55))
        dorsal.addLine(to: CGPoint(x: -len * 0.50, y: -wid * 1.05))
        dorsal.addLine(to: CGPoint(x: -len * 0.62, y: -wid * 0.50))
        dorsal.closeSubpath()
        c.fill(dorsal, with: .color(st.fin))
        var pec = Path()
        pec.move(to: CGPoint(x: -len * 0.22, y: wid * 0.35))
        pec.addLine(to: CGPoint(x: -len * 0.42, y: wid * 0.95))
        pec.addLine(to: CGPoint(x: -len * 0.42, y: wid * 0.30))
        pec.closeSubpath()
        c.fill(pec, with: .color(st.fin.opacity(0.9)))
        // Tail.
        let px = -len * 0.94
        var tail = Path()
        if st.forked {
            tail.move(to: CGPoint(x: px, y: 0))
            tail.addLine(to: CGPoint(x: px - wid * 0.85, y: -wid * 0.85))
            tail.addLine(to: CGPoint(x: px - wid * 0.50, y: 0))
            tail.addLine(to: CGPoint(x: px - wid * 0.85, y: wid * 0.85))
            tail.closeSubpath()
        } else {
            tail.move(to: CGPoint(x: px, y: -wid * 0.55))
            tail.addQuadCurve(to: CGPoint(x: px, y: wid * 0.55), control: CGPoint(x: px - wid * 0.95, y: 0))
            tail.closeSubpath()
        }
        c.fill(tail, with: .color(st.fin))
        // Eye near the head.
        c.fill(Path(ellipseIn: CGRect(x: -len * 0.14 - 3, y: -wid * 0.22 - 3, width: 6, height: 6)), with: .color(.white))
        c.fill(Path(ellipseIn: CGRect(x: -len * 0.14 - 1.5, y: -wid * 0.22 - 1.5, width: 3.5, height: 3.5)), with: .color(.black))
    }

    private static func drawBoot(_ ctx: GraphicsContext, size: Double, t: Double) {
        var c = ctx
        c.rotate(by: .radians(sin(t * 3) * 0.12))   // a soggy sway
        let s = size
        let brown = Color(red: 0.30, green: 0.22, blue: 0.17)
        var boot = Path()
        boot.move(to: CGPoint(x: -s * 0.16, y: 0))
        boot.addLine(to: CGPoint(x: s * 0.10, y: 0))
        boot.addLine(to: CGPoint(x: s * 0.12, y: s * 0.55))
        boot.addLine(to: CGPoint(x: s * 0.50, y: s * 0.60))
        boot.addQuadCurve(to: CGPoint(x: s * 0.50, y: s * 0.76), control: CGPoint(x: s * 0.56, y: s * 0.68))
        boot.addLine(to: CGPoint(x: -s * 0.14, y: s * 0.72))
        boot.closeSubpath()
        c.fill(boot, with: .color(brown))
        c.stroke(boot, with: .color(.black.opacity(0.3)), lineWidth: 1)
        var sole = Path()
        sole.move(to: CGPoint(x: -s * 0.14, y: s * 0.72))
        sole.addLine(to: CGPoint(x: s * 0.52, y: s * 0.76))
        sole.addLine(to: CGPoint(x: s * 0.52, y: s * 0.86))
        sole.addLine(to: CGPoint(x: -s * 0.14, y: s * 0.82))
        sole.closeSubpath()
        c.fill(sole, with: .color(.black.opacity(0.6)))
    }

    // MARK: The predator — a big shadow that lunges in to eat your catch -------

    private static func drawPredator(_ ctx: GraphicsContext, _ s: CGSize, target: CGPoint, progress: Double, t: Double) {
        let w = s.width, h = s.height
        let pp = progress
        let from = CGPoint(x: -0.25 * w, y: 1.15 * h)               // lunges in from the deep
        let cur = CGPoint(x: from.x + (target.x - from.x) * pp,
                          y: from.y + (target.y - from.y) * pp)
        let size = (0.42 + 0.30 * pp) * w
        let alpha = min(0.85, 0.2 + pp * 1.2)

        var c = ctx
        c.translateBy(x: cur.x, y: cur.y)
        c.rotate(by: .radians(atan2(target.y - cur.y, target.x - cur.x)))   // aim at the prey

        // Big dark body pointing +x (toward the prey).
        var body = Path()
        body.move(to: CGPoint(x: size * 0.55, y: 0))
        body.addQuadCurve(to: CGPoint(x: -size * 0.5, y: 0), control: CGPoint(x: 0, y: -size * 0.30))
        body.addQuadCurve(to: CGPoint(x: size * 0.55, y: 0), control: CGPoint(x: 0, y: size * 0.30))
        c.fill(body, with: .color(Sea.deep.opacity(alpha)))
        // Tail.
        var tail = Path()
        tail.move(to: CGPoint(x: -size * 0.48, y: 0))
        tail.addLine(to: CGPoint(x: -size * 0.74, y: -size * 0.26))
        tail.addLine(to: CGPoint(x: -size * 0.74, y: size * 0.26))
        tail.closeSubpath()
        c.fill(tail, with: .color(Sea.deep.opacity(alpha)))
        // Toothy maw, gaping wider as it closes in.
        let gape = min(1, pp * 1.6) * size * 0.16
        var jaw = Path()
        jaw.move(to: CGPoint(x: size * 0.55, y: -gape))
        for k in 0...5 {
            let fx = size * 0.55 - Double(k) * size * 0.06
            jaw.addLine(to: CGPoint(x: fx, y: (k % 2 == 0 ? -gape * 0.4 : 0)))
        }
        c.stroke(jaw, with: .color(.white.opacity(0.7 * alpha)), lineWidth: 1.5)
        // Eye.
        c.fill(Path(ellipseIn: CGRect(x: size * 0.28, y: -size * 0.12, width: 5, height: 5)),
               with: .color(.white.opacity(0.85)))
        c.fill(Path(ellipseIn: CGRect(x: size * 0.30, y: -size * 0.105, width: 2.5, height: 2.5)),
               with: .color(.black))

        // Chomp flash when it reaches the prey.
        if pp > 0.55 {
            let f = (pp - 0.55) / 0.45
            let fr = (0.06 + f * 0.05) * w
            ctx.fill(Path(ellipseIn: CGRect(x: target.x - fr, y: target.y - fr, width: fr * 2, height: fr * 2)),
                     with: .color(.white.opacity(0.5 * (1 - f))))
        }
    }

    // MARK: Special hooks — chest, pickaxe, mine (drawn at the hook while reeling) --

    static func drawSpecial(_ ctx: GraphicsContext, _ sp: Special, at c: CGPoint, size: Double, t: Double) {
        switch sp {
        case .chest:   drawChest(ctx, at: c, size: size, t: t)
        case .pickaxe: drawPickaxe(ctx, at: c, size: size, t: t)
        case .mine:    drawMine(ctx, at: c, size: size, t: t)
        }
    }

    private static func drawChest(_ ctx: GraphicsContext, at c: CGPoint, size s: Double, t: Double) {
        let wood     = Color(red: 0.50, green: 0.34, blue: 0.20)
        let woodLit  = Color(red: 0.62, green: 0.44, blue: 0.27)
        let woodDark = Color(red: 0.34, green: 0.22, blue: 0.13)
        let gold     = Sea.gold
        let goldDark = Color(red: 0.74, green: 0.52, blue: 0.15)
        let W = s * 0.5
        let sway = sin(t * 4) * 0.06
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(sway))

        // Soft glow of treasure light behind it.
        g.fill(Path(ellipseIn: CGRect(x: -W * 1.4, y: -W * 1.4, width: W * 2.8, height: W * 2.8)),
               with: .radialGradient(Gradient(colors: [gold.opacity(0.28), .clear]),
                                     center: .zero, startRadius: 0, endRadius: W * 1.4))
        // Body.
        let body = CGRect(x: -W, y: -W * 0.06, width: W * 2, height: W * 0.74)
        g.fill(Path(roundedRect: body, cornerRadius: W * 0.1),
               with: .linearGradient(Gradient(colors: [woodLit, woodDark]),
                                     startPoint: CGPoint(x: 0, y: body.minY), endPoint: CGPoint(x: 0, y: body.maxY)))
        // Domed lid.
        var lid = Path()
        lid.move(to: CGPoint(x: -W, y: -W * 0.02))
        lid.addQuadCurve(to: CGPoint(x: W, y: -W * 0.02), control: CGPoint(x: 0, y: -W * 0.72))
        lid.closeSubpath()
        g.fill(lid, with: .linearGradient(Gradient(colors: [woodLit, wood]),
                                          startPoint: CGPoint(x: 0, y: -W * 0.7), endPoint: CGPoint(x: 0, y: 0)))
        // Gold straps + the seam band + a lock plate.
        for fx in [-0.66, 0.0, 0.66] {
            g.fill(Path(roundedRect: CGRect(x: CGFloat(fx) * W - W * 0.07, y: -W * 0.5, width: W * 0.14, height: W * 1.18),
                        cornerRadius: 1.5), with: .color(goldDark))
        }
        g.fill(Path(CGRect(x: -W, y: -W * 0.07, width: W * 2, height: W * 0.16)), with: .color(gold))
        g.fill(Path(roundedRect: CGRect(x: -W * 0.16, y: -W * 0.02, width: W * 0.32, height: W * 0.3),
                    cornerRadius: 2), with: .color(gold))
        g.fill(Path(ellipseIn: CGRect(x: -W * 0.05, y: W * 0.04, width: W * 0.1, height: W * 0.1)),
               with: .color(woodDark))                                   // keyhole
        g.stroke(Path(roundedRect: body, cornerRadius: W * 0.1), with: .color(.black.opacity(0.25)), lineWidth: 1)

        // Sparkles twinkling around the treasure.
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + t * 0.8
            let tw = 0.5 + 0.5 * sin(t * 5 + Double(k) * 1.7)
            let pos = CGPoint(x: cos(a) * W * 1.25, y: sin(a) * W * 1.0 - W * 0.2)
            let r = W * 0.12 * tw
            for d in [CGPoint(x: r, y: 0), CGPoint(x: 0, y: r)] {
                var ray = Path()
                ray.move(to: CGPoint(x: pos.x - d.x, y: pos.y - d.y))
                ray.addLine(to: CGPoint(x: pos.x + d.x, y: pos.y + d.y))
                g.stroke(ray, with: .color(.white.opacity(0.85 * tw)), lineWidth: 1.2)
            }
        }
    }

    private static func drawPickaxe(_ ctx: GraphicsContext, at c: CGPoint, size s: Double, t: Double) {
        let woodLit  = Color(red: 0.62, green: 0.45, blue: 0.28)
        let woodDark = Color(red: 0.40, green: 0.28, blue: 0.16)
        let steel    = Color(red: 0.72, green: 0.76, blue: 0.82)
        let steelDk  = Color(red: 0.42, green: 0.46, blue: 0.52)
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(-0.5 + sin(t * 4) * 0.06))   // hangs at an angle, sways

        // Handle (shaft) running down-left to up-right.
        let hl = s * 0.62, hw = s * 0.09
        g.fill(Path(roundedRect: CGRect(x: -hw, y: -hl, width: hw * 2, height: hl * 1.8), cornerRadius: hw),
               with: .linearGradient(Gradient(colors: [woodLit, woodDark]),
                                     startPoint: CGPoint(x: -hw, y: 0), endPoint: CGPoint(x: hw, y: 0)))
        // Pick head — a curved double-pointed bar across the top of the handle.
        var head = Path()
        head.move(to: CGPoint(x: -s * 0.62, y: -hl + s * 0.04))
        head.addQuadCurve(to: CGPoint(x: s * 0.62, y: -hl + s * 0.04), control: CGPoint(x: 0, y: -hl - s * 0.30))
        head.addQuadCurve(to: CGPoint(x: s * 0.40, y: -hl + s * 0.02), control: CGPoint(x: 0, y: -hl - s * 0.08))
        head.addQuadCurve(to: CGPoint(x: -s * 0.40, y: -hl + s * 0.02), control: CGPoint(x: 0, y: -hl + s * 0.12))
        head.closeSubpath()
        g.fill(head, with: .linearGradient(Gradient(colors: [steel, steelDk]),
                                           startPoint: CGPoint(x: 0, y: -hl - s * 0.3), endPoint: CGPoint(x: 0, y: -hl + s * 0.1)))
        g.stroke(head, with: .color(.black.opacity(0.28)), lineWidth: 1)
        // Steel highlight + the collar where head meets handle.
        var sheen = Path()
        sheen.move(to: CGPoint(x: -s * 0.5, y: -hl - s * 0.05))
        sheen.addQuadCurve(to: CGPoint(x: s * 0.5, y: -hl - s * 0.05), control: CGPoint(x: 0, y: -hl - s * 0.24))
        g.stroke(sheen, with: .color(.white.opacity(0.5)), lineWidth: 1.2)
        g.fill(Path(roundedRect: CGRect(x: -hw * 1.5, y: -hl - s * 0.02, width: hw * 3, height: s * 0.14),
                    cornerRadius: 2), with: .color(steelDk))
    }

    private static func drawMine(_ ctx: GraphicsContext, at c: CGPoint, size s: Double, t: Double) {
        let shell    = Color(red: 0.17, green: 0.19, blue: 0.23)
        let shellLit = Color(red: 0.30, green: 0.33, blue: 0.38)
        let shellDk  = Color(red: 0.09, green: 0.10, blue: 0.13)
        let R = s * 0.5
        let warn = 0.5 + 0.5 * sin(t * 6)
        var g = ctx
        g.translateBy(x: c.x, y: c.y)
        g.rotate(by: .radians(sin(t * 2.5) * 0.05))

        // Horns (Hertz horns) poking out all around — drawn first so the body covers their roots.
        for k in 0..<9 {
            let a = Double(k) / 9 * 2 * .pi
            var horn = g
            horn.rotate(by: .radians(a))
            horn.fill(Path(roundedRect: CGRect(x: -R * 0.10, y: -R * 1.32, width: R * 0.20, height: R * 0.42),
                           cornerRadius: R * 0.08), with: .color(shellDk))
            horn.fill(Path(ellipseIn: CGRect(x: -R * 0.085, y: -R * 1.34, width: R * 0.17, height: R * 0.17)),
                      with: .color(Color(red: 0.55, green: 0.18, blue: 0.16)))   // dull red horn tip
        }
        // Spherical body, shaded.
        g.fill(Path(ellipseIn: CGRect(x: -R, y: -R, width: R * 2, height: R * 2)),
               with: .radialGradient(Gradient(colors: [shellLit, shell, shellDk]),
                                     center: CGPoint(x: -R * 0.35, y: -R * 0.35), startRadius: 0, endRadius: R * 1.7))
        g.stroke(Path(ellipseIn: CGRect(x: -R, y: -R, width: R * 2, height: R * 2)),
                 with: .color(.black.opacity(0.4)), lineWidth: 1)
        // Rivet band + a blinking warning light.
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            g.fill(Path(ellipseIn: CGRect(x: cos(a) * R * 0.66 - 1.2, y: sin(a) * R * 0.66 - 1.2, width: 2.4, height: 2.4)),
                   with: .color(.black.opacity(0.5)))
        }
        let lr = R * 0.22
        g.fill(Path(ellipseIn: CGRect(x: -lr, y: -lr, width: lr * 2, height: lr * 2)),
               with: .radialGradient(Gradient(colors: [Color.red.opacity(0.4 + 0.6 * warn), Color.red.opacity(0.1)]),
                                     center: .zero, startRadius: 0, endRadius: lr))
        g.fill(Path(ellipseIn: CGRect(x: -R * 0.45, y: -R * 0.5, width: R * 0.4, height: R * 0.3)),
               with: .color(.white.opacity(0.22)))                     // sheen
    }

    // MARK: Rock shatter (cleaved by the pickaxe) & the mine explosion --------------

    static func drawShatter(_ ctx: GraphicsContext, _ s: CGSize, _ sh: Shatter, dur: Double) {
        let c = p(sh.x, sh.y, s)
        let r = sh.r * s.width
        let pr = min(1, sh.age / dur)
        let rockLit = Color(red: 0.55, green: 0.58, blue: 0.63)
        let rockDk  = Color(red: 0.30, green: 0.32, blue: 0.37)

        // A puff of dust expanding and fading.
        let dr = r * (0.8 + 1.4 * pr)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - dr, y: c.y - dr, width: dr * 2, height: dr * 2)),
                 with: .radialGradient(Gradient(colors: [Color(white: 0.7).opacity(0.35 * (1 - pr)), .clear]),
                                       center: c, startRadius: 0, endRadius: dr))
        // A quick white flash at the very start.
        if pr < 0.25 {
            let fr = r * (0.6 + pr)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - fr, y: c.y - fr, width: fr * 2, height: fr * 2)),
                     with: .color(.white.opacity(0.6 * (1 - pr / 0.25))))
        }
        // Fragments flying outward, tumbling and fading.
        let n = 6
        for k in 0..<n {
            let a = hash01(sh.seed * 7 + k * 13) * 2 * .pi
            let spd = (0.6 + 0.8 * hash01(sh.seed * 5 + k)) * r * 2.4
            let d = spd * pr
            let fx = c.x + cos(a) * d
            let fy = c.y + sin(a) * d + pr * pr * r * 1.2      // gravity pulls them down
            let fr = r * (0.34 - 0.12 * Double(k % 3)) * (1 - pr * 0.4)
            let frag = rockShape(CGPoint(x: fx, y: fy), max(2, fr), seed: sh.seed * 31 + k)
            ctx.fill(frag, with: .color((k % 2 == 0 ? rockLit : rockDk).opacity(1 - pr)))
        }
    }

    static func drawExplosion(_ ctx: GraphicsContext, _ s: CGSize, x: Double, y: Double, progress p: Double) {
        let c = CGPoint(x: x * s.width, y: y * s.height)
        let w = s.width
        let pc = min(1, max(0, p))
        let fade = 1 - pc
        let orange = Color(red: 1.0, green: 0.6, blue: 0.2)
        let yellow = Color(red: 1.0, green: 0.86, blue: 0.4)

        // Shockwave rings racing outward.
        for k in 0..<2 {
            let rp = max(0, pc - Double(k) * 0.12)
            let rr = (0.04 + rp * 0.42) * w
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                       with: .color(.white.opacity(0.7 * max(0, 1 - rp))), lineWidth: max(1, 6 * (1 - rp)))
        }
        // Smoke puffs billowing.
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi + 0.4
            let d = (0.05 + pc * 0.22) * w
            let sx = c.x + cos(a) * d, sy = c.y + sin(a) * d - pc * 0.06 * w
            let sr = (0.06 + pc * 0.10) * w
            ctx.fill(Path(ellipseIn: CGRect(x: sx - sr, y: sy - sr, width: sr * 2, height: sr * 2)),
                     with: .color(Color(white: 0.25).opacity(0.5 * fade)))
        }
        // Fireball core.
        let fr = (0.12 + 0.10 * sin(pc * .pi)) * w
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - fr, y: c.y - fr, width: fr * 2, height: fr * 2)),
                 with: .radialGradient(Gradient(colors: [.white.opacity(fade), yellow.opacity(fade), orange.opacity(0.6 * fade), .clear]),
                                       center: c, startRadius: 0, endRadius: fr))
        // Flying debris + sparks.
        let n = 12
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let d = (0.05 + pc * 0.36) * w * (0.7 + 0.5 * sin(Double(i) * 2.3))
            let dx = c.x + cos(a) * d, dy = c.y + sin(a) * d + pc * pc * 0.12 * w
            let sz = max(1.5, (i % 3 == 0 ? 5.0 : 3.0) * fade)
            let col = (i % 2 == 0) ? Color(white: 0.15).opacity(fade) : orange.opacity(fade)
            ctx.fill(Path(ellipseIn: CGRect(x: dx - sz / 2, y: dy - sz / 2, width: sz, height: sz)), with: .color(col))
        }
    }

    // MARK: The catch splash — a stylised water crown with flying droplets --------

    private static func drawCatchSplash(_ ctx: GraphicsContext, _ s: CGSize, center: CGPoint, progress p: Double) {
        let w = s.width, h = s.height
        let pc = min(1, max(0, p))
        let rise = sin(pc * .pi)                          // erupt, peak at p=0.5, then settle
        let foam = Sea.foam                               // near-white churned water
        let body = Color(red: 0.66, green: 0.86, blue: 0.97)
        let cx = center.x, baseY = center.y

        let caustic = Color(red: 0.52, green: 0.92, blue: 1.0)
        // Soft cyan glow behind the splash (matches the water light).
        let gw = (0.15 + 0.07 * rise) * w
        ctx.fill(Path(ellipseIn: CGRect(x: cx - gw, y: baseY - gw, width: gw * 2, height: gw * 1.4)),
                 with: .color(caustic.opacity(0.13 * rise)))

        // Organic caustic ripples bursting outward — the same wavy shapes as the water.
        for k in 0..<3 {
            let rp = pc + Double(k) * 0.18
            guard rp < 1 else { continue }
            let rr = (0.05 + rp * 0.26) * w
            var c = ctx
            c.translateBy(x: cx, y: baseY)
            c.scaleBy(x: 1, y: 0.4)                    // flatten to the surface
            c.stroke(causticBlob(r: rr, seed: k + 3),
                     with: .color(caustic.opacity(0.5 * (1 - rp))), lineWidth: 2 * (1 - rp) + 0.6)
        }

        // Central white-water dome, with a few foam puffs for texture.
        let dw = (0.10 + 0.04 * rise) * w
        let dh = (0.04 + 0.11 * rise) * h
        ctx.fill(Path(ellipseIn: CGRect(x: cx - dw, y: baseY - dh, width: dw * 2, height: dh * 1.5)),
                 with: .color(foam.opacity(0.95 * rise)))           // erupts & settles with `rise`
        for k in 0..<5 {
            let f = Double(k) / 4
            let bx = cx + (f - 0.5) * dw * 1.8
            let by = baseY - (0.02 + 0.09 * sin(f * .pi) * rise) * h
            let r = (5 + 7 * sin(f * .pi)) * (0.6 + 0.5 * rise)
            ctx.fill(Path(ellipseIn: CGRect(x: bx - r, y: by - r, width: r * 2, height: r * 2)),
                     with: .color((k % 2 == 0 ? foam : body).opacity(0.9 * rise)))
        }

        // Droplet spray — round droplets plus a few elongated teardrops, arcing up then falling.
        let drops = 18
        for i in 0..<drops {
            let ang = -Double.pi * 0.95 + Double(i) / Double(drops - 1) * (Double.pi * 0.9)
            let spd = (0.13 + 0.16 * Double((i * 17) % 11) / 11) * w
            let dist = spd * pc * 1.45
            let dx = cx + cos(ang) * dist
            let dy = baseY + sin(ang) * dist + (pc * pc) * 0.26 * h        // gravity pulls them down
            let big = i % 5 == 0
            let dsz = max(1.2, (big ? 5.5 : 3.0) * (1 - pc * 0.55))
            let col = (i % 3 == 0 ? body : foam).opacity(max(0, 1 - pc))   // fully gone by the end
            if big {
                ctx.fill(Path(ellipseIn: CGRect(x: dx - dsz / 2, y: dy - dsz, width: dsz, height: dsz * 2)),
                         with: .color(col))
            } else {
                ctx.fill(Path(ellipseIn: CGRect(x: dx - dsz / 2, y: dy - dsz / 2, width: dsz, height: dsz)),
                         with: .color(col))
            }
        }
    }

}
