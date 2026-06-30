from PIL import Image, ImageFilter
from collections import deque
import json
# Build per-device stencil masks from the green screens + a despilled poster (green -> dark navy so any
# sub-pixel leak is invisible). The watch overlaps the phone, so the green AROUND the watch case is actually
# phone-screen green: we assign every green pixel by its CONNECTED COMPONENT (phone screen vs watch screen),
# NOT by bounding box — otherwise the watch bbox steals the phone green around the case and it shows as a
# dark/green square. Tiny strays (e.g. a sliver trapped by the gull) fold into the nearest screen.
post = Image.open('poster_template.png').convert('RGB'); W, H = post.size; P = post.load()
def strictGreen(r, g, b): return g > 120 and r < 120 and b < 120 and g > r + 60 and g > b + 60
def anyGreen(r, g, b):    return g > 90  and g > r + 15 and g > b + 15
DARK = (10, 14, 22)

# --- connected components of strict green (stride-2), labelled ---
S = 2; gw, gh = W // S, H // S
g = [[strictGreen(*P[i*S, j*S]) for i in range(gw)] for j in range(gh)]
label = [[-1]*gw for _ in range(gh)]; comps = []; cid = 0
for j in range(gh):
    for i in range(gw):
        if g[j][i] and label[j][i] == -1:
            q = deque([(i, j)]); label[j][i] = cid; cells = []
            while q:
                x, y = q.popleft(); cells.append((x, y))
                for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)):
                    nx, ny = x+dx, y+dy
                    if 0 <= nx < gw and 0 <= ny < gh and g[ny][nx] and label[ny][nx] == -1:
                        label[ny][nx] = cid; q.append((nx, ny))
            xs = [c[0]*S for c in cells]; ys = [c[1]*S for c in cells]
            comps.append({'id': cid, 'n': len(cells), 'cx': sum(xs)/len(xs), 'cy': sum(ys)/len(ys)}); cid += 1
order = sorted(comps, key=lambda c: c['n'], reverse=True)
phoneC, watchC = order[0], order[1]
assign = {}
for c in comps:
    if c['id'] == phoneC['id']: assign[c['id']] = 'p'
    elif c['id'] == watchC['id']: assign[c['id']] = 'w'
    else:
        dp = (c['cx']-phoneC['cx'])**2+(c['cy']-phoneC['cy'])**2
        dw = (c['cx']-watchC['cx'])**2+(c['cy']-watchC['cy'])**2
        assign[c['id']] = 'w' if dw < dp else 'p'

# --- full-res masks: each green pixel -> its component's screen ---
pm = Image.new('L', (W, H), 0); wm = Image.new('L', (W, H), 0); pmp = pm.load(); wmp = wm.load()
for y in range(H):
    yy = y // S
    for x in range(W):
        if not strictGreen(*P[x, y]): continue
        xx = x // S
        lb = label[yy][xx]
        if lb == -1:                                   # boundary pixel: borrow a neighbour cell's component
            for dj in (0, -1, 1):
                for di in (0, -1, 1):
                    nj, ni = yy+dj, xx+di
                    if 0 <= ni < gw and 0 <= nj < gh and label[nj][ni] != -1:
                        lb = label[nj][ni]; break
                if lb != -1: break
        a = assign.get(lb)
        if a is None:
            dp = (x-phoneC['cx'])**2+(y-phoneC['cy'])**2; dw = (x-watchC['cx'])**2+(y-watchC['cy'])**2
            a = 'w' if dw < dp else 'p'
        (wmp if a == 'w' else pmp)[x, y] = 255
pm = pm.filter(ImageFilter.MaxFilter(3)); wm = wm.filter(ImageFilter.MaxFilter(3))   # 1px safety
pbb = pm.getbbox(); wbb = wm.getbbox()
pm.save('phone_mask.png'); wm.save('watch_mask.png')
pm.crop(pbb).save('phone_mask_crop.png'); wm.crop(wbb).save('watch_mask_crop.png')

# --- despilled poster: any greenish pixel -> dark navy (video covers it; only sub-pixel edges show) ---
desp = post.copy(); D = desp.load()
for y in range(H):
    for x in range(W):
        if anyGreen(*P[x, y]): D[x, y] = DARK
desp.save('poster_despill.png')

meta = {'poster': [W, H], 'phone_bbox': list(pbb), 'watch_bbox': list(wbb)}
json.dump(meta, open('regions.json', 'w'), indent=2)
print(json.dumps(meta)); print('phone crop', pm.crop(pbb).size, 'watch crop', wm.crop(wbb).size)
