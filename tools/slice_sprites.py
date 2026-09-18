#!/usr/bin/env python3
"""Turn a horizontal sprite sheet from ChatGPT into DinoWidget's sprites.

ChatGPT hands back one wide PNG with the frames side by side. This does three
things:

  1. Splits the sheet on the blank columns between frames. Splitting by aspect
     ratio is not safe: a 5-frame sheet and a 3-frame sheet can be the same
     overall width.
  2. Re-anchors every frame into one square canvas, aligned on the feet
     (bottom edge + centroid of the legs), which removes the sideways drift
     that would otherwise make the dino slide while breathing.
  3. Paints blink.png: the eye from the artwork, closed. It is an overlay, so
     it is transparent everywhere except the eyelid, and the app draws it on
     top of the resting pose so the body holds still while the eyes close.

The frames come out in sheet order and are left that way, because the sheet is
one whole breath: the first and last frames are the same resting pose and the
fullest frame sits in the middle. The app walks that as a ramp and loops it.
The eye is found automatically (largest compact dark blob in the head), so a
regenerated sheet with a different pose still works without editing constants.

    python3 tools/slice_sprites.py ~/Downloads/dino.png Resources/sprites
    python3 tools/slice_sprites.py sheet.png out/ --preview

Options: --frames N to force the count, --preview to also write a composite
showing the blink applied, --report for per-frame measurements.
"""

import argparse
import collections
import math
import os
import sys

import pngtool

SOLID = 200          # alpha above this counts as the character
DARK_SUM = 430       # RGB sum below this counts as line art
MARGIN = 10          # transparent breathing room around the character


def solid_bbox(img, threshold=SOLID):
    xs = []
    ys = []
    for y in range(img.h):
        row = y * img.w * 4
        for x in range(img.w):
            if img.px[row + x * 4 + 3] > threshold:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return (min(xs), min(ys), max(xs), max(ys))


def detect_frames(img, threshold=SOLID):
    """Split the sheet on columns that contain no ink.

    More reliable than dividing by the aspect ratio: a 5-frame sheet and a
    3-frame sheet can share the same overall width, so the frame count cannot
    be inferred from the size alone.
    """
    columns = []
    for x in range(img.w):
        has_ink = False
        for y in range(img.h):
            if img.px[(y * img.w + x) * 4 + 3] > threshold:
                has_ink = True
                break
        columns.append(has_ink)

    runs = []
    start = None
    for x, has_ink in enumerate(columns):
        if has_ink and start is None:
            start = x
        elif not has_ink and start is not None:
            runs.append((start, x - 1))
            start = None
    if start is not None:
        runs.append((start, img.w - 1))

    # A single run means the frames touch; only trust the split when the pieces
    # look like siblings.
    if len(runs) < 2:
        return None
    widths = [b - a + 1 for a, b in runs]
    average = sum(widths) / len(widths)
    if any(w < average * 0.5 or w > average * 1.6 for w in widths):
        return None
    return runs


def anchor(img, bbox):
    """(feet_centroid_x, bottom_y) - the landmarks that stay put."""
    x0, y0, x1, y1 = bbox
    band = y0 + (y1 - y0) * 7 // 10
    sx = n = 0
    for y in range(band, y1 + 1):
        row = y * img.w * 4
        for x in range(x0, x1 + 1):
            if img.px[row + x * 4 + 3] > SOLID:
                sx += x
                n += 1
    return (sx / n if n else (x0 + x1) / 2.0, y1)


def find_eye(img, bbox):
    """Largest compact dark blob in the head - the eye.

    Returns (cx, cy, rx, ry) or None. The character outline is one huge
    component spanning the whole sprite, so anything bigger than a third of
    the character is rejected.
    """
    W, H = img.w, img.h
    x0, y0, x1, y1 = bbox
    w, h = x1 - x0 + 1, y1 - y0 + 1
    limit_w, limit_h = w * 0.4, h * 0.4

    def dark(x, y):
        i = (y * W + x) * 4
        return img.px[i + 3] > SOLID and sum(img.px[i:i + 3]) < DARK_SUM

    seen = set()
    best = None
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x, y) in seen or not dark(x, y):
                continue
            stack = [(x, y)]
            comp = []
            seen.add((x, y))
            while stack:
                cx, cy = stack.pop()
                comp.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if (nx, ny) in seen or not (x0 <= nx <= x1 and y0 <= ny <= y1):
                        continue
                    if dark(nx, ny):
                        seen.add((nx, ny))
                        stack.append((nx, ny))
            xs = [p[0] for p in comp]
            ys = [p[1] for p in comp]
            cw, ch = max(xs) - min(xs) + 1, max(ys) - min(ys) + 1
            if cw > limit_w or ch > limit_h or len(comp) < 800:
                continue
            # eyes are taller than wide and round-ish, not thin strokes
            if ch < cw * 0.7 or len(comp) / float(cw * ch) < 0.35:
                continue
            if best is None or len(comp) > best[0]:
                best = (len(comp), min(xs), min(ys), max(xs), max(ys))
    if best is None:
        return None
    _, ex0, ey0, ex1, ey1 = best
    return ((ex0 + ex1) / 2.0, (ey0 + ey1) / 2.0,
            (ex1 - ex0 + 1) / 2.0, (ey1 - ey0 + 1) / 2.0)


def dominant(img, box, predicate):
    c = collections.Counter()
    for y in range(box[1], box[3] + 1):
        for x in range(box[0], box[2] + 1):
            i = (y * img.w + x) * 4
            if img.px[i + 3] > SOLID:
                px = tuple(img.px[i:i + 3])
                if predicate(px):
                    c[px] += 1
    return c.most_common(1)[0][0] if c else None


def put_over(img, x, y, color, t):
    """Composite color at coverage t over the pixel already there."""
    if t <= 0 or not (0 <= x < img.w and 0 <= y < img.h):
        return
    i = (y * img.w + x) * 4
    da = img.px[i + 3] / 255.0
    oa = t + da * (1.0 - t)
    if oa <= 0:
        return
    for c in range(3):
        img.px[i + c] = int(min(255, (color[c] * t
                                      + img.px[i + c] * da * (1.0 - t)) / oa + 0.5))
    img.px[i + 3] = int(oa * 255 + 0.5)


def build_blink(size, eye, skin, ink, lid_drop=0.34, thickness=14, pad=7):
    """Transparent overlay: skin patch over the open eye, then a closed lid.

    The patch is opaque on purpose - it has to hide the open eye of whatever
    idle frame is showing underneath - so the lid is composited over it rather
    than replacing it, or the patch would get punched through.
    """
    cx, cy, rx, ry = eye
    out = pngtool.Image(size, size)

    prx, pry = rx + pad, ry + pad
    for y in range(int(cy - pry - 3), int(cy + pry + 4)):
        for x in range(int(cx - prx - 3), int(cx + prx + 4)):
            d = dist_px(x + 0.5, y + 0.5, cx, cy, prx, pry)
            if d > 0:
                continue
            a = min(1.0, -d / 1.5)          # feather the last 1.5px inside
            out.put(x, y, (skin[0], skin[1], skin[2], int(a * 255)))

    # closed lid: shallow arch with rounded, tapering ends
    span = rx - 3
    for x in range(int(cx - span), int(cx + span) + 1):
        u = (x - cx) / span
        yc = cy - (ry * lid_drop) * (1.0 - u * u)
        half = max(1.0, thickness * 0.5 * (1.0 - 0.35 * abs(u) ** 3))
        for y in range(int(yc - half) - 1, int(yc + half) + 2):
            cov = 1.0 - min(1.0, abs(y + 0.5 - yc) / half)
            put_over(out, x, y, ink, cov)
    return out


def dist_px(x, y, cx, cy, rx, ry):
    """Approximate pixel distance from the ellipse boundary (negative inside)."""
    dx = (x - cx) / rx
    dy = (y - cy) / ry
    return (math.sqrt(dx * dx + dy * dy) - 1.0) * min(rx, ry)


def over(base, top):
    """Composite top over base, straight alpha."""
    out = pngtool.Image(base.w, base.h)
    for i in range(0, len(base.px), 4):
        ba = base.px[i + 3] / 255.0
        ta = top.px[i + 3] / 255.0
        oa = ta + ba * (1 - ta)
        if oa <= 0:
            continue
        for c in range(3):
            out.px[i + c] = int(min(255, (top.px[i + c] * ta
                                          + base.px[i + c] * ba * (1 - ta)) / oa + 0.5))
        out.px[i + 3] = int(oa * 255 + 0.5)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet")
    ap.add_argument("outdir", nargs="?", default="Resources/sprites")
    ap.add_argument("--frames", type=int, default=None)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    sheet = pngtool.read(args.sheet)
    if args.frames:
        columns = [(i * (sheet.w // args.frames), (i + 1) * (sheet.w // args.frames) - 1)
                   for i in range(args.frames)]
    else:
        columns = detect_frames(sheet) or []
        if not columns:
            n = max(1, round(sheet.w / sheet.h))
            fw = sheet.w // n
            columns = [(i * fw, (i + 1) * fw - 1) for i in range(n)]

    frames = []
    for index, (cx0, cx1) in enumerate(columns):
        f = sheet.crop(cx0, 0, cx1 - cx0 + 1, sheet.h)
        bb = solid_bbox(f)
        if bb is None:
            sys.exit(f"frame {index + 1} is empty")
        frames.append((f, bb, anchor(f, bb)))
    if args.report:
        print(f"detected {len(frames)} frame(s)")

    # one square canvas that fits every frame around its own anchor
    need = []
    for f, bb, (ax, ay) in frames:
        need.append(max(ax - bb[0], bb[2] - ax))       # half width
    for f, bb, (ax, ay) in frames:
        need.append(bb[3] - bb[1] + 1)                 # height
    size = int(max(need)) + MARGIN * 2 + 1

    os.makedirs(args.outdir, exist_ok=True)
    placed = []
    for i, (f, bb, (ax, ay)) in enumerate(frames):
        off_x = int(round(size / 2.0 - ax))
        off_y = int(round(size - MARGIN - ay))
        canvas = pngtool.Image(size, size)
        for y in range(f.h):
            for x in range(f.w):
                j = (y * f.w + x) * 4
                if f.px[j + 3]:
                    canvas.put(x + off_x, y + off_y, f.px[j:j + 4])
        path = os.path.join(args.outdir, f"idle_{i + 1}.png")
        pngtool.write(path, canvas)
        placed.append((canvas, off_x, off_y))
        if args.report:
            print(f"frame {i + 1}: bbox={bb} anchor=({ax:.1f},{ay}) "
                  f"offset=({off_x},{off_y})")
        print("wrote", path, f"{size}x{size}")

    # blink overlay, built in the first frame's canvas space
    canvas, off_x, off_y = placed[0]
    f, bb, _ = frames[0]
    eye = find_eye(f, bb)
    if eye is None:
        print("warning: no eye found, skipping blink.png")
        return
    ink = dominant(f, (int(eye[0] - eye[2]) - 8, int(eye[1] - eye[3]) - 8,
                       int(eye[0] + eye[2]) + 8, int(eye[1] + eye[3]) + 8),
                   lambda p: sum(p) < DARK_SUM) or (50, 22, 25)
    skin = dominant(f, (int(eye[0] - eye[2]) - 24, int(eye[1] - eye[3]) - 24,
                        int(eye[0] + eye[2]) + 24, int(eye[1] + eye[3]) + 24),
                    lambda p: sum(p) > 430 and p[1] > p[0]) or (122, 210, 144)
    if args.report:
        print(f"eye: centre=({eye[0]:.0f},{eye[1]:.0f}) r=({eye[2]:.0f},{eye[3]:.0f})"
              f" ink={ink} skin={skin}")
    eye_canvas = (eye[0] + off_x, eye[1] + off_y, eye[2], eye[3])
    blink = build_blink(size, eye_canvas, skin, ink)
    blink_path = os.path.join(args.outdir, "blink.png")
    pngtool.write(blink_path, blink)
    print("wrote", blink_path, f"{size}x{size}")

    if args.preview:
        side = pngtool.Image(size * 2 + 20, size)
        for y in range(size):
            for x in range(size):
                j = (y * size + x) * 4
                side.put(x, y, canvas.px[j:j + 4])
        combined = over(canvas, blink)
        for y in range(size):
            for x in range(size):
                j = (y * size + x) * 4
                side.put(x + size + 20, y, combined.px[j:j + 4])
        pngtool.write("/tmp/blink_preview.png", side)
        print("wrote /tmp/blink_preview.png (left: idle, right: with blink)")


if __name__ == "__main__":
    main()
