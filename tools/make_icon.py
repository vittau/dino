#!/usr/bin/env python3
"""Composite a sprite frame over a solid background for the app icon.

The idle frames are transparent, but a macOS icon wants a solid tile. This
flattens the sprite onto an opaque background (black by default) so the icon
no longer floats on transparency.

    python3 tools/make_icon.py Resources/sprites/idle_1.png /tmp/icon.png
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngtool


def parse_color(text):
    text = text.lstrip("#")
    if len(text) != 6:
        raise argparse.ArgumentTypeError("expected RRGGBB")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("sprite")
    ap.add_argument("out")
    ap.add_argument("--bg", type=parse_color, default=(0, 0, 0),
                    help="background colour as RRGGBB (default 000000)")
    args = ap.parse_args()

    img = pngtool.read(args.sprite)
    bg = args.bg
    out = pngtool.Image(img.w, img.h)
    for y in range(img.h):
        for x in range(img.w):
            r, g, b, a = img.at(x, y)
            if a == 255:
                out.put(x, y, (r, g, b, 255))
            elif a == 0:
                out.put(x, y, (bg[0], bg[1], bg[2], 255))
            else:
                f = a / 255
                out.put(x, y, (
                    int(r * f + bg[0] * (1 - f) + 0.5),
                    int(g * f + bg[1] * (1 - f) + 0.5),
                    int(b * f + bg[2] * (1 - f) + 0.5),
                    255))
    pngtool.write(args.out, out)


if __name__ == "__main__":
    main()
