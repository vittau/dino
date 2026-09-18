#!/usr/bin/env python3
"""Tiny dependency-free PNG read/write helpers.

Used by the sprite tools so slicing sheets and painting overlays needs no
third-party packages. Supports 8-bit non-interlaced greyscale/RGB/RGBA and
palette PNGs on read; always writes 8-bit RGBA on write.
"""

import struct
import zlib

CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}


class Image:
    """Straight-alpha RGBA image, pixels as bytearray of w*h*4."""

    def __init__(self, w, h, px=None):
        self.w = w
        self.h = h
        self.px = px if px is not None else bytearray(w * h * 4)

    def at(self, x, y):
        i = (y * self.w + x) * 4
        return tuple(self.px[i:i + 4])

    def put(self, x, y, rgba):
        if 0 <= x < self.w and 0 <= y < self.h:
            i = (y * self.w + x) * 4
            self.px[i:i + 4] = bytes(rgba)

    def crop(self, x0, y0, w, h):
        out = Image(w, h)
        for y in range(h):
            src = ((y0 + y) * self.w + x0) * 4
            dst = y * w * 4
            out.px[dst:dst + w * 4] = self.px[src:src + w * 4]
        return out

    def alpha_bbox(self, threshold=8):
        """(x0, y0, x1, y1) of pixels with alpha > threshold, or None."""
        x0, y0, x1, y1 = self.w, self.h, -1, -1
        for y in range(self.h):
            row = y * self.w * 4
            for x in range(self.w):
                if self.px[row + x * 4 + 3] > threshold:
                    if x < x0:
                        x0 = x
                    if x > x1:
                        x1 = x
                    if y < y0:
                        y0 = y
                    if y > y1:
                        y1 = y
        if x1 < 0:
            return None
        return (x0, y0, x1, y1)


def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c


def read(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG: " + path)

    pos = 8
    idat = bytearray()
    w = h = depth = ctype = None
    palette = None

    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if tag == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8:
                raise ValueError(f"unsupported bit depth {depth}")
            if interlace:
                raise ValueError("interlaced PNG not supported")
        elif tag == b"PLTE":
            palette = body
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break

    ch = CHANNELS[ctype]
    raw = zlib.decompress(bytes(idat))
    stride = w * ch
    out = bytearray(stride * h)
    prev = bytearray(stride)

    p = 0
    for y in range(h):
        f = raw[p]
        p += 1
        line = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for i in range(ch, stride):
                line[i] = (line[i] + line[i - ch]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - ch] if i >= ch else 0
                c = prev[i - ch] if i >= ch else 0
                line[i] = (line[i] + _paeth(a, prev[i], c)) & 0xFF
        elif f != 0:
            raise ValueError(f"bad filter {f}")
        out[y * stride:(y + 1) * stride] = line
        prev = line

    img = Image(w, h)
    if ctype == 6:
        img.px = out
    elif ctype == 2:
        for i in range(w * h):
            img.px[i * 4:i * 4 + 3] = out[i * 3:i * 3 + 3]
            img.px[i * 4 + 3] = 255
    elif ctype == 0:
        for i in range(w * h):
            v = out[i]
            img.px[i * 4:i * 4 + 4] = bytes((v, v, v, 255))
    elif ctype == 3:
        for i in range(w * h):
            idx = out[i] * 3
            img.px[i * 4:i * 4 + 4] = bytes(palette[idx:idx + 3]) + b"\xff"
    elif ctype == 4:
        for i in range(w * h):
            v = out[i * 2]
            img.px[i * 4:i * 4 + 4] = bytes((v, v, v, out[i * 2 + 1]))
    return img


def write(path, img):
    raw = bytearray()
    stride = img.w * 4
    for y in range(img.h):
        raw.append(0)
        raw += img.px[y * stride:(y + 1) * stride]

    def chunk(tag, body):
        return (struct.pack(">I", len(body)) + tag + body
                + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", img.w, img.h, 8, 6, 0, 0, 0)
    with open(path, "wb") as fh:
        fh.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                 + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
                 + chunk(b"IEND", b""))
