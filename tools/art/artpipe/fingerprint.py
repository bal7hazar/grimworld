"""Fingerprints of `out/` (ART-02, determinism across machines).

- **files**: SHA-256 over every file of `out/` (name, then bytes), in name order: equal when the
  outputs are byte-identical.
- **pixels and metadata**: SHA-256 over every PNG decoded to RGBA (name, size, pixels) and every
  JSON parsed and re-serialised canonically (sorted keys, no spaces, ASCII), in name order. Equal
  when the atlases hold the same pixels and the same data, whatever compressed them. `preview.html`
  is a viewer built from the same JSON, and is left out.
"""

import hashlib
import json
import zlib

import numpy as np
from PIL import Image, features


def files(out):
    digest = hashlib.sha256()
    for f in sorted(out.iterdir()):
        digest.update(f.name.encode() + f.read_bytes())
    return digest.hexdigest()


def content(out):
    digest = hashlib.sha256()
    for f in sorted(out.iterdir()):
        if f.suffix == ".png":
            px = np.ascontiguousarray(np.array(Image.open(f).convert("RGBA")))
            digest.update(f.name.encode() + b"%dx%d" % (px.shape[1], px.shape[0]) + px.tobytes())
        elif f.suffix == ".json":
            data = json.loads(f.read_text())
            text = json.dumps(data, sort_keys=True, separators=(",", ":"), ensure_ascii=True)
            digest.update(f.name.encode() + text.encode())
    return digest.hexdigest()


def environment():
    """The libraries the bytes depend on, printed next to the fingerprints."""
    return (f"zlib (python) {zlib.ZLIB_RUNTIME_VERSION}, zlib (Pillow) {features.version('zlib')}, "
            f"Pillow {Image.__version__}, NumPy {np.__version__}")


def report(out):
    print(f"out/ sha256: {files(out)}")
    print(f"out/ pixels+metadata sha256: {content(out)}")
    print(f"encoders: {environment()}")
