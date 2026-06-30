# Marketing assets — what we want & how to make it

How we produce (1) cut-out element art and (2) paired App Store screenshots. Read this before
regenerating anything so the look stays consistent. Game UI strings stay English, so all store
copy is English too. **Every temp harness below is added, used, then reverted** — finish with
`grep -rn 'TEMP-' "Wristfish Watch App/"` = 0 and both targets building green.

> **Output lives in the project and is always overwritten.** Cut-out assets go to **`AppStore/assets/`**
> and screenshots to **`AppStore/screenshots/`** (committed with the repo). Regenerating an image
> **replaces** the existing file in place (same filename), so the project always holds the current set —
> never write a new variant alongside the old one, overwrite it.

---

## 1. The golden rule: native size + uniform context scale

The Canvas art mixes **proportional** sizes (fractions of width `w`) with **absolute pixels**
(a fish eye is `6px`, line widths `2–3px`, mine rivets `2.4px`). So you can NOT enlarge an element
by passing a bigger `size:` — the absolute details stay small and proportions break (this is why
the fish eyes once looked tiny, and the boat rod too short).

**Always** draw the element at its exact in-game size, then scale the whole `GraphicsContext`:

```swift
var g = ctx
g.translateBy(x: cx, y: cy); g.scaleBy(x: k, y: k); g.translateBy(x: -cx, y: -cy)
drawWhatever(g, …, /* native game size */)
```

In-game native sizes the posters use: fish `(0.13 + kind.fight*0.05)*w*1.2`; specials `0.17*w*1.2`;
boot-catch `0.186*w`; kraken/boot-beast creature at `emerge=1`; gull `0.060*w*0.85`; rock `r≈0.07`;
lighthouse `r≈0.06`; vak = deep `drawRipple`.

---

## 2. Transparency: TWO-BACKGROUND extraction (not chroma key)

Chroma key can't handle translucent art (foam, wake, lighthouse beams, vak rings — they're *mostly*
background). So render each element **over solid black AND solid white**, then recover true alpha:

```
a       = 1 − (white − black)        # per pixel; (white−black) == (1−a)
straight = black / a                 # un-premultiplied colour (F = Cb / a)
```

This recovers correct alpha for opaque AND translucent pixels, with no green/spill fringing.
PIL (no numpy): `alpha = ImageChops.invert(ImageChops.subtract(white, black).convert("L"))`,
colour via `ImageMath.unsafe_eval("convert(min((cb*255)/(a+1),255),'L')", …)`.

Pipeline per element:
- Crop the status bar / home indicator first: top `210px`, bottom `110px` (elements are centred).
- Extract alpha + colour, then crop to the alpha bbox **thresholded at >12** (so faint glow halos
  don't bloat the crop) + `16px` pad → save **`wristfish_<name>_cropped.png`** only. (We keep only the
  cropped cut-outs — no full-frame versions.)
- Keep each element's `big(k)` scale small enough that nothing (incl. soft shadows / light beams)
  touches the frame edge; the extractor logs `<-- CLIPS` if the bbox hits an edge. Current safe
  scales: boat `4.6`, pickaxe `(0.50w)/native`, lighthouse `2.2`, cast meter `1.2`.

### Asset harness (TEMP) — `WF_POSTER` + `WF_BG`
- `WristfishApp.swift` `body`: if `WF_POSTER` is set, show a `Canvas` that fills the background from
  `WF_BG` (`black` / `white` / `sea`) then calls `GameArt.renderPoster(ctx, size, key)`.
- `GameArt.swift`: append `static func renderPoster(_:_:_:)` (+ `posterKraken` / `posterBootBeast`
  creature-only copies). It draws ONE element, no background, at native size inside a `big(k){…}`
  context-scale closure. Recoverable from session history; keep this doc in sync.

### Capture loop (iOS sim)
```bash
for key in fish_herring … cast_meter; do
  for bg in black white; do
    xcrun simctl terminate $SIM $BUNDLE 2>/dev/null
    SIMCTL_CHILD_WF_POSTER=$key SIMCTL_CHILD_WF_BG=$bg xcrun simctl launch $SIM $BUNDLE
    python3 -c "import time; time.sleep(1.2)"
    xcrun simctl io $SIM screenshot scratchpad/${key}_${bg}.png  # temp; the PIL pass writes the cut-out to AppStore/assets/
  done
done
```
(zsh does NOT word-split `$VAR` — use an explicit list or `${=VAR}`.)

---

## 3. Element asset inventory (in `AppStore/assets/`)

Each is `wristfish_<name>_cropped.png` (transparent, tight) — overwritten in place on every regen.

- **Fish:** `fish_herring` `fish_mackerel` `fish_cod` `fish_salmon` `fish_tuna`
- **Items:** `item_chest` `item_pickaxe` `item_bomb` (sea mine) `item_boot`
- **Rocks:** `rock_1` `rock_2` `rock_3` `rock_4` (seeds 7 / 23 / 51 / 88)
- **Lighthouses:** `lighthouse_1` `lighthouse_2` (seeds 12 / 64; translucent beams preserved by two-bg)
- **Monsters:** `kraken` `bootbeast` (creature only, no murk)
- **Cast meter:** `cast_meter` (boat + golden cast line + aim reticle over the water, no water, cropped)
- **Other:** `gull` `vak` `boat_clean`
- **Speeding boat:** `boat_speeding` (transparent, real game wake via two-bg)

All are `wristfish_<name>_cropped.png` (transparent, tight). No full-frame versions are kept.

> Translucent effects (wake, foam, beams, vak rings) only survive via the two-background pass. The
> render of the same element over black and white must be pixel-identical except the background
> (use fixed `t`, never `model.elapsed`).

---

## 4. App Store screenshots — paired watch + iPhone

Saved to `AppStore/screenshots/` as `wristfish_<scene>_iphone.png` and `wristfish_<scene>_watch.png`
(overwritten in place). **Score must match within a pair** (same `WF_SCORE`); different scenes may
use different scores.

### Screenshot harness (TEMP) — `WF_SCENE` + `WF_SCORE`
- `GameModel.swift`: `static let debugScene = env["WF_SCENE"]`; a `debugFrozen` flag; `applyDebugScene()`
  called at the end of `start()` that forces the phase + scene state and sets `score`/`displayScore`
  from `WF_SCORE`, then sets `debugFrozen = true`. `tick()` early-returns when `debugFrozen` so the
  frame holds perfectly still.
- `RootView.swift`: in `.onAppear`, if `WF_SCENE` is set and ≠ `menu`, auto-`startGame(.freeplay)`
  after ~0.4s (a one-shot `autoStarted` guard).

### Scenes used (and the scores shipped)
| scene | what it shows | score |
|-------|---------------|-------|
| `reel` | reeling a salmon (rod, fish, fight gauge) | 1840 |
| `boss` | the kraken rising | 2310 |
| `bootbeast` | the boot-beast | 1490 |
| `sea` | open water with rocks + vak | 1560 |
| `cast` | casting at a vak (line + aim reticle) | 1980 |
| `finish` | crossing the checkered finish line | 2640 |
| `sleigh` | the tuna sleigh ride (towed by a hooked tuna) | 2180 |
| `catch` | the CATCH! splash with the fish bursting out | 2090 |
| `menu` | the main menu | — |

> The forced scenes also set `boatSpeed = 1` + a `wakeTrail`, so the boat shows its real wake (it
> reads as moving/“gassing”) in every top-down scene — otherwise a freshly-frozen boat looks static.

Scene specifics that make each shot tell its story:
- **boss:** a tentacle is set mid-slam **beside** the boat — `Tentacle(x: 0.63, age: 1.40)` (just past
  `tentTele 1.1 + tentStrike 0.35`) — plus a telegraph ring on the other side `Tentacle(x: 0.36, age: 0.55)`.
- **bootbeast:** boots are caught in the air — `BootThrow(x:0.40, age:0.80)` and `(x:0.62, age:0.92)`
  (past `bootTele 0.6`, mid `bootDrop 0.4`), plus one telegraph `(x:0.50, age:0.30)`.
- **catch:** the taut line is hidden on a successful land (see permanent art below), so there's no stray
  line running into the deep behind the leaping fish.
- **cast:** shot at **sunset** — set `elapsed = 0.56 * dayLength` (freeplay has `fixedTimeOfDay = nil`,
  so `timeOfDay = elapsed/dayLength = 0.56`, the peak of `GameArt.sunsetAmount`). `fixedTimeOfDay` is a
  `let`, so drive the time via `elapsed`, not by mutating the config.

### Capture loop (both sims)
```bash
# iPhone sim + Apple Watch Ultra sim, same WF_SCORE per scene
SIMCTL_CHILD_WF_SCENE=$scene SIMCTL_CHILD_WF_SCORE=$score xcrun simctl launch $SIM $BUNDLE
python3 -c "import time; time.sleep(2.6)"   # 0.4s auto-start + game start + render
xcrun simctl io $SIM screenshot AppStore/screenshots/wristfish_${scene}_<device>.png
```
Bundle ids: iOS `com.dropdev.WristfishiOS`, watch `com.dropdev.Wristfish.watchkitapp`.
The on-screen score HUD is shown in every gameplay view on both devices.

---

## 5. Background policy

| Asset type | Background |
|------------|-----------|
| All cut-out elements (fish, items, rocks, lighthouses, monsters, gull, vak, boat, cast meter, speeding boat) | **Transparent** via two-background, cropped only |
| Paired App Store screenshots | the real game scene (sea / boss / menu), boat showing its wake |

---

## 6. Checklist when regenerating

1. **Assets:** add the asset harness (§2), build iOS, render every key over black+white (+ sea for the
   speeding boat), run the two-background PIL pass → `AppStore/assets/` (cut-outs) and `AppStore/screenshots/` (screenshots). Spot-check a few on grey.
2. **Screenshots:** add the screenshot harness (§4), build BOTH targets, install on the iPhone and the
   Apple Watch Ultra sims, capture each scene on both with the same `WF_SCORE`. Verify the score
   matches per pair and is visible on both devices.
3. **Revert** every temp harness — `grep -rn 'TEMP-' "Wristfish Watch App/"` = 0, both targets green.
4. Permanent art that grew out of this work (kept in the game): the **Old Boot**, rebuilt from scratch
   as a clean, realistic work-boot — a leather upper (shaft → ankle → vamp → rounded toe → achilles
   heel) over a proper sole where the heel and ball sit on the ground and the arch lifts between them;
   just a few details (dark opening, vamp seam, collar seam, soft highlight, back pull-tab) and **no
   sea-clutter** (the earlier laced L-shape and the seaweed/barnacle/drip were scrapped). Plus: pointed
   wake that tucks behind the stern; fishing rod drawn behind the angler; and **no taut line on a
   successful land** in `drawReelingFP` (gated on `!landing`) so the catch shot has no red line.
