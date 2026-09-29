"""PNG writing without Pillow's encoder (ART-02, determinism across machines).

Pillow 12's wheels compress with zlib-ng (`PIL.features.version("zlib")` reads `1.3.1.zlib-ng`),
whose output depends on the build and the CPU's code paths, so the same pixels gave different PNG
bytes on macOS arm64 and Linux x86_64. Here the pixels are filtered in NumPy (Paeth on every row,
integer arithmetic) and compressed by Python's own `zlib` module at level 9. Decoders read the
same pixels either way; only the bytes change.
"""

import struct
import zlib

import numpy as np


def paeth_filter(rgba):
    """Rows of the RGBA image, each prefixed with filter type 4 (Paeth), as bytes."""
    x = rgba.astype(np.int16)
    h, w, _ = x.shape
    a = np.zeros_like(x)
    a[:, 1:] = x[:, :-1]                    # left
    b = np.zeros_like(x)
    b[1:] = x[:-1]                          # up
    c = np.zeros_like(x)
    c[1:, 1:] = x[:-1, :-1]                 # up-left
    p = a + b - c
    pa, pb, pc = np.abs(p - a), np.abs(p - b), np.abs(p - c)
    pred = np.where((pa <= pb) & (pa <= pc), a, np.where(pb <= pc, b, c))
    rows = ((x - pred) & 0xFF).astype(np.uint8).reshape(h, w * 4)
    return np.concatenate([np.full((h, 1), 4, np.uint8), rows], axis=1).tobytes()


def chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))


def write(path, rgba):
    """Write an RGBA uint8 array as an 8-bit RGBA PNG."""
    h, w, _ = rgba.shape
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    body = zlib.compress(paeth_filter(rgba), 9)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", body)
                     + chunk(b"IEND", b""))
