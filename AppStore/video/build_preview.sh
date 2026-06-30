#!/bin/bash
# ============================================================================================
# ONE-COMMAND RECREATION of the exact Tiny Tide marketing PREVIEW VIDEO.
#   bash AppStore/video/build_preview.sh
# It produces AppStore/video/tinytide_app_preview.mp4 — the device-frame poster
# (poster_template.png) with the iPhone + Apple-Watch green screens replaced by live, in-sync
# gameplay: opens on 1337 pts, weave past rocks/lighthouses/drifting-boats with ripples always
# on the water, two short casts that land on a vak → reel → CATCH, then the kraken rises and is
# fought off (harpoons + tentacle dodging) → "DROVE IT OFF!". 30s, ending on the victory.
#
# HOW IT'S DETERMINISTIC / IN SYNC: the WF_DEMO harness (AppStore/video/wf_demo.patch, applied
# below) makes the game play itself from a fixed script identically on both devices, with
# scrollPlatformFactor forced to 1.0 so the world advances the same. Each device is recorded,
# then both clips are anchored to the first CATCH! white-splash (frame-accurate) and cut to a 30s
# window. Green is removed via a DESPILLED poster (poster_despill.png) + per-screen stencil masks
# so there's no green rim and the foreground gull / bezels aren't clipped.
#
# Prereqs: Xcode + the two simulators below booted, ffmpeg, python3 + Pillow.
# Safe to re-run: it applies the harness patch, then reverts it, leaving the repo clean.
# ============================================================================================
set -e
IOS=10E0AEEE-1026-492C-85B8-FCC869BCA058           # iPhone 17 sim
WATCH=63F3908E-842E-43CB-96AA-2B3A3AEBAF25          # Apple Watch Ultra 3 sim
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

cleanup() { (cd "$REPO" && git apply -R "$HERE/wf_demo.patch" 2>/dev/null) || true; }   # always revert harness
trap cleanup EXIT

# 0) Apply the WF_DEMO harness, build BOTH targets.
cd "$REPO"
git apply "$HERE/wf_demo.patch"
xcodebuild -project Wristfish.xcodeproj -scheme "Wristfish Watch App" -configuration Debug \
  -destination "platform=watchOS Simulator,id=$WATCH" -derivedDataPath build/ddpw build >/dev/null
xcodebuild -project Wristfish.xcodeproj -scheme "Wristfish iOS" -configuration Debug \
  -destination "platform=iOS Simulator,id=$IOS" -derivedDataPath build/ddp build >/dev/null

cd "$HERE"
python3 masks.py     # regenerate phone/watch masks + crops + poster_despill.png + regions.json

# 1) Record each device in demo mode (WF_DEMO=1 auto-starts LevelConfig.demo, opening on 1337 pts). ~40s.
for pair in "$IOS:com.dropdev.tinytide:ios_demo.mov:Debug-iphonesimulator:$REPO/build/ddp" \
            "$WATCH:com.dropdev.tinytide.watchkitapp:watch_demo.mov:Debug-watchsimulator:$REPO/build/ddpw"; do
  IFS=: read -r UDID BUNDLE OUT CFG DD <<< "$pair"
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$UDID" "$(ls -d "$DD"/Build/Products/$CFG/*.app | head -1)"
  SIMCTL_CHILD_WF_DEMO=1 xcrun simctl launch "$UDID" "$BUNDLE"
  sleep 2
  xcrun simctl io "$UDID" recordVideo --codec=h264 --force "$OUT" & RP=$!
  sleep 40; kill -INT $RP; wait $RP 2>/dev/null || true
done

# 2) Anchor on the first CATCH splash; cut aligned clips [c1-182 .. c1+718) → 900 frames / 30s,
#    ~6s lead-in, ending on the "DROVE IT OFF!" victory. (catch lands at clip-frame 182.)
python3 - <<'PY'
import subprocess
def firstcatch(p):
    L=list(subprocess.run(['ffmpeg','-v','error','-i',p,'-vf','fps=30,scale=1:1','-f','rawvideo','-pix_fmt','gray','pipe:'],capture_output=True).stdout)
    for i in range(15,len(L)):
        if L[i]>sorted(L[i-15:i-3])[6]+34 and L[i]>150: return i
    return 257
def cut(src,out,c1):
    s=max(0,c1-182)
    subprocess.run(['ffmpeg','-y','-loglevel','error','-i',src,'-vf',
        f'fps=30,trim=start_frame={s}:end_frame={s+900},setpts=PTS-STARTPTS','-an',
        '-c:v','libx264','-crf','14','-pix_fmt','yuv420p',out],check=True)
cut('ios_demo.mov','ios_clip.mp4',firstcatch('ios_demo.mov'))
cut('watch_demo.mov','watch_clip.mp4',firstcatch('watch_demo.mov'))
PY

# 3) Composite the synced clips into the green screens (alpha from masks, over the despilled poster).
python3 composite.py ios_clip.mp4 watch_clip.mp4 tinytide_app_preview.mp4 31
ffmpeg -y -loglevel error -ss 26.5 -i tinytide_app_preview.mp4 -vframes 1 tinytide_preview_hero.png
echo "wrote $HERE/tinytide_app_preview.mp4 (+ hero). Harness will be reverted on exit."
