"""Atlas packing: trimmed frames on shelves, PNG pages + TexturePacker "hash" JSON for PixiJS 8.

A sprite never straddles two pages, so each page is a self-contained atlas that PixiJS loads with
`Assets.load` and one `Spritesheet`. Everything is deterministic: fixed order, no timestamps.
"""

import json

import numpy as np
from PIL import Image


class Page:
    def __init__(self, side, pad):
        self.side, self.pad = side, pad
        self.shelves = []       # [y, height, used_x]
        self.placed = []        # (key, x, y, w, h)
        self.next_y = pad

    def try_add(self, items):
        """Place (key, w, h) items, tallest first; returns True and commits, or False untouched."""
        shelves = [list(s) for s in self.shelves]
        next_y = self.next_y
        out = []
        for key, w, h in sorted(items, key=lambda i: (-i[2], i[0])):
            for sh in shelves:
                if h <= sh[1] and sh[2] + w + self.pad <= self.side:
                    out.append((key, sh[2], sh[0], w, h))
                    sh[2] += w + self.pad
                    break
            else:
                if next_y + h + self.pad > self.side or w + 2 * self.pad > self.side:
                    return False
                shelves.append([next_y, h, self.pad + w + self.pad])
                out.append((key, self.pad, next_y, w, h))
                next_y += h + self.pad
        self.shelves, self.next_y = shelves, next_y
        self.placed += out
        return True


def trim(cell):
    ys, xs = np.where(cell[..., 3] > 0)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    return cell[y0:y1, x0:x1], (int(x0), int(y0))


def pack(sprites, s, out_dir):
    """sprites: ordered list of dicts (name, cell_w, cell_h, baseline, anims=[{name, fps, loop,
    cells}]). Writes atlas-N.png / atlas-N.json and returns (index, page names)."""
    side, pad = s["atlas_max"], s["atlas_padding"]
    pages, page_of, trimmed = [], {}, {}
    for sp in sprites:
        items = []
        for anim in sp["anims"]:
            for i, cell in enumerate(anim["cells"]):
                key = f'{sp["name"]}/{anim["name"]}/{i:02d}'
                crop, off = trim(cell)
                trimmed[key] = (crop, off)
                items.append((key, crop.shape[1], crop.shape[0]))
        for n, page in enumerate(pages):
            if page.try_add(items):
                page_of[sp["name"]] = n
                break
        else:
            page = Page(side, pad)
            if not page.try_add(items):
                raise SystemExit(f'{sp["name"]}: does not fit one {side} x {side} page')
            pages.append(page)
            page_of[sp["name"]] = len(pages) - 1

    index = {"pages": [], "sprites": {}}
    for n, page in enumerate(pages):
        height = max(y + h for _, _, y, _, h in page.placed) + pad
        height = -(-height // 4) * 4
        width = max(x + w for _, x, _, w, _ in page.placed) + pad
        width = -(-width // 4) * 4
        img = np.zeros((height, width, 4), np.uint8)
        frames, animations, rates = {}, {}, {}
        pos = {key: (x, y, w, h) for key, x, y, w, h in page.placed}
        for sp in [q for q in sprites if page_of[q["name"]] == n]:
            for anim in sp["anims"]:
                keys = []
                for i in range(len(anim["cells"])):
                    key = f'{sp["name"]}/{anim["name"]}/{i:02d}'
                    x, y, w, h = pos[key]
                    crop, (ox, oy) = trimmed[key]
                    img[y:y + h, x:x + w] = crop
                    frames[key] = {
                        "frame": {"x": x, "y": y, "w": w, "h": h},
                        "rotated": False,
                        "trimmed": True,
                        "spriteSourceSize": {"x": ox, "y": oy, "w": w, "h": h},
                        "sourceSize": {"w": sp["cell_w"], "h": sp["cell_h"]},
                        "anchor": {"x": 0.5, "y": round(sp["baseline"] / sp["cell_h"], 6)},
                    }
                    keys.append(key)
                animations[f'{sp["name"]}/{anim["name"]}'] = keys
                rates[f'{sp["name"]}/{anim["name"]}'] = {"fps": anim["fps"], "loop": anim["loop"]}
        png, jsn = f"atlas-{n}.png", f"atlas-{n}.json"
        Image.fromarray(img, "RGBA").save(out_dir / png, optimize=False, compress_level=9)
        data = {
            "frames": frames,
            "animations": animations,
            "meta": {
                "app": "grimworld tools/art",
                "version": "1",
                "image": png,
                "format": "RGBA8888",
                "size": {"w": width, "h": height},
                "scale": "1",
                "animationRates": rates,
            },
        }
        (out_dir / jsn).write_text(json.dumps(data, indent=1) + "\n")
        index["pages"].append({"json": jsn, "image": png, "w": width, "h": height})
    for sp in sprites:
        index["sprites"][sp["name"]] = {
            "role": sp["role"], "page": page_of[sp["name"]],
            "cell": {"w": sp["cell_w"], "h": sp["cell_h"]},
            "baseline": sp["baseline"],
            "animations": {a["name"]: {"frames": len(a["cells"]), "fps": a["fps"], "loop": a["loop"]}
                           for a in sp["anims"]},
        }
    return index
