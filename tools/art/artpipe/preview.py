"""preview.html: every animation of the atlases, playing, for the owner's review.

Self-contained apart from the atlas PNGs beside it (the JSON is embedded, so the page also works
opened from disk). Frames are drawn from the atlas exactly as the client will: trimmed frames
offset by spriteSourceSize inside their cell.
"""

import json

PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Grim World sprites (generated preview)</title>
<style>
body{margin:0;padding:16px;font:14px system-ui,sans-serif;background:#1d1f24;color:#ddd}
h1{font-size:18px;margin:0 0 8px} h2{font-size:15px;margin:22px 0 4px;color:#fff}
.bar{display:flex;gap:16px;flex-wrap:wrap;align-items:center;margin-bottom:8px}
.sprite small{color:#9aa}.cards{display:flex;flex-wrap:wrap;gap:10px}
.card{background:var(--bg);border:1px solid #444;padding:6px;text-align:center}
.card canvas{display:block;image-rendering:pixelated}.card div{font-size:12px;margin-top:4px;color:#ccc}
</style></head><body>
<h1>Grim World sprites</h1>
<div class="bar">
<label>zoom <select id="zoom"><option>1</option><option selected>2</option><option>3</option></select></label>
<label><input type="checkbox" id="mirror"> face left (mirror)</label>
<label><input type="checkbox" id="guides" checked> cell, baseline, anchor</label>
<label>background <select id="bg"><option value="#2b2e36">dark</option>
<option value="#7aa35a">grass</option><option value="#e8e8e8">light</option><option value="#ff00ff">magenta</option></select></label>
</div>
<div id="root"></div>
<script>
const DATA = __DATA__;
const imgs = DATA.pages.map(p => { const i = new Image(); i.src = p.image; return i; });
const root = document.getElementById('root'), opt = id => document.getElementById(id);
const players = [];
for (const [name, sp] of Object.entries(DATA.index.sprites)) {
  const page = DATA.atlases[sp.page];
  const sec = document.createElement('div'); sec.className = 'sprite';
  sec.innerHTML = `<h2>${name} <small>${sp.role} &middot; cell ${sp.cell.w}&times;${sp.cell.h}
    &middot; atlas page ${sp.page} &middot; ${DATA.origins[name]}</small></h2><div class="cards"></div>`;
  for (const [an, info] of Object.entries(sp.animations)) {
    const keys = page.animations[name + '/' + an];
    const card = document.createElement('div'); card.className = 'card';
    const cv = document.createElement('canvas'); card.appendChild(cv);
    const cap = document.createElement('div');
    cap.textContent = `${an} · ${info.frames} frames · ${info.fps} fps${info.loop ? '' : ' · once'}`;
    card.appendChild(cap); sec.querySelector('.cards').appendChild(card);
    players.push({cv, keys, page, sp, info, t0: 0});
  }
  root.appendChild(sec);
}
function draw(p, now) {
  const z = +opt('zoom').value, {cv, sp} = p, ctx = cv.getContext('2d');
  cv.width = sp.cell.w * z; cv.height = sp.cell.h * z;
  cv.parentNode.style.setProperty('--bg', opt('bg').value);
  ctx.imageSmoothingEnabled = false;
  const n = p.keys.length, tick = Math.floor(now / 1000 * p.info.fps);
  const i = p.info.loop ? tick % n : Math.min(tick % (n + Math.ceil(p.info.fps / 2)), n - 1);
  const f = p.page.frames[p.keys[i]], fr = f.frame, o = f.spriteSourceSize;
  ctx.save();
  if (opt('mirror').checked) { ctx.translate(cv.width, 0); ctx.scale(-1, 1); }
  ctx.drawImage(imgs[sp.page], fr.x, fr.y, fr.w, fr.h, o.x * z, o.y * z, fr.w * z, fr.h * z);
  ctx.restore();
  if (opt('guides').checked) {
    ctx.strokeStyle = 'rgba(255,255,255,.35)'; ctx.strokeRect(.5, .5, cv.width - 1, cv.height - 1);
    ctx.strokeStyle = 'rgba(255,60,60,.8)'; ctx.beginPath();
    ctx.moveTo(0, sp.baseline * z + .5); ctx.lineTo(cv.width, sp.baseline * z + .5); ctx.stroke();
    ctx.strokeStyle = 'rgba(60,200,255,.8)'; ctx.beginPath();
    ctx.moveTo(cv.width / 2 + .5, sp.baseline * z - 8); ctx.lineTo(cv.width / 2 + .5, sp.baseline * z + 8); ctx.stroke();
  }
}
function loop(now) { for (const p of players) draw(p, now); requestAnimationFrame(loop); }
requestAnimationFrame(loop);
</script></body></html>
"""


def write(path, pages, index, origins):
    data = {"pages": index["pages"], "index": index, "atlases": pages, "origins": origins}
    path.write_text(PAGE.replace("__DATA__", json.dumps(data, separators=(",", ":"))))
