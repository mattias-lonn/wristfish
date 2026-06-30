# App Store listing & ASO pack

Working source-of-truth for the App Store launch copy, keywords, and ASO plan.
All availability/competition data was verified against Apple's live APIs
(iTunes Search + top-charts RSS). Game UI strings stay English, so all store
copy is English too.

---

## 1. Name — current shortlist

Replace the working title **Wristfish** (watch-locked, misrepresents the iPhone
version). Top verified-free picks, easy to remember + roll off the tongue:

| Pick | Why | Status |
|------|-----|--------|
| **Tiny Tide** ⭐ | 5/5/5 (memory/flow/fit); sells "watch + phone, tiny session" | Clear |
| **Mellow Minnow** | 5/5/5; internal rhyme, overtly cozy + fishing | Clear |
| **Fin & Tonic** | 5/5/5; playful pun, reads instantly as relaxing fishing | Clear |
| **Stillwake** | 5/4/5; **zero** App Store results — fully ownable | Clear |

Recommendation: **Tiny Tide** (runner-up Mellow Minnow; wildcard Stillwake).
Full 125-name list lives in the chat history / name-finder workflow output.

---

## 2. App Store metadata (ready to paste)

Example uses **Tiny Tide**. Per-name title variants below — subtitle, promo,
keywords and description are name-agnostic.

### Title (≤30 chars) — name + keyword tail
- `Tiny Tide: Cozy Fishing` (23)
- `Mellow Minnow: Cozy Fishing` (27)
- `Fin & Tonic: Cozy Fishing` (25)
- `Stillwake: Cozy Fishing` (23)

### Subtitle (≤30 chars)
- **Primary:** `Relax, sail & catch fish` (24)
- A/B: `Apple Watch fishing game` (24) · `Calm sail & catch on watch` (26) · `Cozy sail, reel & relax` (23)

### Keyword field (≤100 chars) — CORRECTED to 97 chars
No words repeated from title/subtitle (Apple stems + combines automatically):
```
calm,casual,reel,boat,ocean,sea,deep,offline,apple,watch,adventure,chill,zen,peaceful,cute,racing
```
> Note: the original auto-generated field was 144 chars (over the 100 limit) and
> repeated subtitle words — this trimmed version fixes both. Drop `apple` if
> review flags it (allowed here since the app genuinely supports Apple Watch).

### Promotional text (≤170 chars)
- **Primary (147):** `New: chase ripples, dodge the kraken, and unlock cosmetic boats. No timers, no pressure — just you, your tiny boat, and the calm of the open water.`
- A/B (156): `The cozy fishing game made for your wrist. Steer with the Digital Crown, chase ripples, reel in fish, and unlock charming boats — calm whenever you need it.`
- A/B (133): `No grind. No timers. Just a tiny boat, the open water, and the fish below. Race the campaign or drift in endless Open Water freeplay.`

### Description
```
A calm little fishing escape for your wrist.

Steer a tiny boat across a soft, flat-art ocean, cast your line into
the ripples, and reel in the fish below. No timers. No pressure. Just
the gentle rhythm of the tide — a quiet break for whenever your day
needs one.

WHAT YOU DO
Glide across stylized seas, watch for ripples where fish surface, line
up your cast, and reel them in. Dodge the rocks, chase the shimmer of
deep water, and see what's hiding below.

FEATURES
• Calm by design — relaxing, charming, never frantic. Drift, don't grind.
• Simple, satisfying controls — steer, cast, reel.
• Chase the ripples — teal ripples are shallow; deep blue ones hide the trophies.
• Gentle boss encounters — survive the kraken and the goofy sea-boot beast.
• Collect & unlock — gather fish, boots and chests to unlock cosmetic boats.

MODES
• Campaign — relaxed races across handcrafted ocean levels.
• Open Water — endless freeplay to drift, fish, and unwind at your own pace.

MADE FOR APPLE WATCH + iPHONE
On Apple Watch, steer with the Digital Crown — fishing made for your
wrist. On iPhone, just swipe. Your boats and progress come along on both.

If you love cozy fishing games, relaxing games, or calm ocean
adventures, drop a line and drift a while.

Cast. Reel. Unwind.
```

---

## 3. Keyword strategy

- **Primary:** cozy fishing game · relaxing fishing game · calm fishing game · fishing game · boat fishing game
- **Secondary:** casual fishing · reel fishing · catch fish · cute fishing · ocean adventure · sailing game · boat racing · relaxing watch game · fishing apple watch
- **Long-tail:** cozy fishing game offline · no timer no pressure fishing · catch and release fishing game · open water sailing adventure · stress relief ocean game · kraken boss fishing game · digital crown fishing game

Rationale: `cozy fishing game` and `calm fishing game` are the least-saturated,
highest-intent exact terms — our true positioning. The big sim/PvP fishing apps
own the generic high-volume head terms, so we steer into cozy + the near-empty
Apple Watch game niche (mostly utilities, no real games).

---

## 4. Screenshot captions (benefit-led overlays)

Lead with a hero beauty shot, not a UI dump. One promise per frame:
1. `no timers, no pressure — just you and the tide`
2. `cast, reel, relax`
3. `made for Apple Watch — steer with the Digital Crown`
4. `race the campaign or drift in open water`
5. `dodge the kraken`
6. `unlock charming boats`

---

## 5. ASO action plan

- **Title/Subtitle PPO test:** "Cozy Fishing" vs "Calm Fishing Game" vs "Fishing & Boats"; cozy subtitle vs Apple-Watch-niche subtitle.
- **Icon test:** (a) tiny boat on flat teal water + one ripple, (b) jumping fish, (c) boat in a subtle Watch bezel. Soft, text-free, readable at thumbnail size.
- **Screenshot order test:** hero calm-ocean shot first vs "Made for Apple Watch" first.
- **App preview video:** 15–20s, open on the calmest moment (sunset cast + ambient waves), one kraken dodge for intrigue.
- **Ratings prompt:** fire at a positive peak (trophy fish / survived kraken / new boat) — never mid-trip.
- **Localize** title/subtitle/keywords/screenshots for cozy-heavy markets: JA, DE, FR, KO, zh-Hans.
- **Apple featuring pitch:** angles Apple actively curates — "Made for Apple Watch" (thin category) + "Cozy/relaxing games". Provide clean flat-art press assets.
- **Cross-promote the platform combo:** in-app card nudging iPhone players to try it on the wrist (and vice versa); Universal Purchase + Watch-native is a differentiator no big fishing title offers.
- **Keyword-field iteration:** ship launch field, then after 3–4 weeks of App Store Connect data swap the lowest-yield singletons (e.g. `racing`, `angler`) for emerging long-tails.

---

## 6. Competitors studied (for reference)

Tides: A Fishing Game · Pondlife · Creatures of the Deep · Fishing and Life ·
Hooked Inc: Fishing Games · Fishing Clash · DREDGE · Tap Tap Fish (AbyssRium) ·
Arcadia – Watch Games · Stardew Valley · Meowdoku! · Saily Seas.

Key patterns: short evocative brand + colon + literal keyword tail in the title;
subtitle as a keyword tail (not a slogan); empathy/use-case-first description
hook; scannable benefit-led feature bullets; a self-qualifying keyword-magnet
line near the end ("If you love cozy fishing games…"); a 3-beat emotional closer.
