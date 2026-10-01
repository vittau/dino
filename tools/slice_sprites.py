#!/usr/bin/env python3
"""Turn a horizontal sprite sheet into Dino's sprites.

ChatGPT hands back one wide PNG with the frames side by side. This does three
things:

  1. Splits the sheet on the blank columns between frames. Splitting by aspect
     ratio is not safe: a 5-frame sheet and a 3-frame sheet can be the same
     overall width.
  2. Re-anchors every frame into one square canvas, aligned on the feet
     (bottom edge + centroid of the legs), which removes the sideways drift
     that would otherwise make the dino slide while breathing.
  3. Paints two pixel-art eyelid frames from the resting pose.

The frames come out in sheet order and are left that way, because the sheet is
one whole breath: the first and last frames are the same resting pose and the
fullest frame sits in the middle. The app walks that as a ramp and loops it.
The eye is found automatically (largest compact dark blob in the head), so a
regenerated sheet with a different pose still works without editing constants.

    python3 tools/slice_sprites.py ~/Downloads/dino.png Resources/sprites
    python3 tools/slice_sprites.py sheet.png out/ --preview
    python3 tools/slice_sprites.py --blink-only --preview

Options: --frames N forces the count; --blink-only rebuilds the eyelids from
the installed idle frames when the original sheet is unavailable. --preview
writes the open/half/closed composite; --report prints frame measurements.
"""

import argparse
import collections
import glob
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


def build_blink(resting, eye, skin, ink, closed):
    """Repair the eye with neighboring face pixels and draw a stepped eyelid.

    A complete frame keeps the face's original alpha and gradient; an overlay
    would make the repaired area more opaque than the surrounding pixels.
    """
    cx, cy, rx, ry = eye
    out = pngtool.Image(resting.w, resting.h, bytearray(resting.px))
    left, right = int(cx - rx - 12), int(cx + rx + 12)
    top, bottom = int(cy - ry - 12), int(cy + ry + 12)
    lid_y = int(cy + (9 if closed else -8))

    def face_sample(x, y):
        r, g, b, a = resting.at(x, y)
        return (r, g, b, a) if a > SOLID else (*skin, 255)

    for y in range(top, bottom + 1):
        if not 0 <= y < resting.h:
            continue
        # Half shut: the lower half of the original eye remains visible.
        if not closed and y > lid_y + 5:
            continue
        lc = face_sample(left - 1, y)
        rc = face_sample(right + 1, y)
        for x in range(left, right + 1):
            original = resting.at(x, y)
            if y > cy + 25 and x < cx - 5 and original[0] > 170 \
                    and original[0] > original[1] * 1.1 \
                    and 80 < original[1] < 200 and original[2] > 100:
                continue
            mix = (x - left) / (right - left)
            color = tuple(round(lc[k] * (1 - mix) + rc[k] * mix) for k in range(4))
            out.put(x, y, color)

    # Six source pixels per step, with a slight downward curve at the ends.
    block = 6
    for x0 in range(left + block, right - block, block):
        u = abs((x0 + block / 2 - cx) / rx)
        y0 = lid_y + round(9 * u * u / block) * block
        thickness = block if u > 0.82 else block + 2
        for y in range(y0, y0 + thickness):
            for x in range(x0, min(x0 + block, right)):
                out.put(x, y, (*ink, resting.at(x, y)[3]))
    return out


def write_blinks(canvas, outdir, report=False, preview=False):
    bb = solid_bbox(canvas)
    eye = find_eye(canvas, bb)
    if eye is None:
        sys.exit("no eye found in resting frame")
    ink = dominant(canvas, (int(eye[0] - eye[2]) - 8, int(eye[1] - eye[3]) - 8,
                            int(eye[0] + eye[2]) + 8, int(eye[1] + eye[3]) + 8),
                   lambda p: sum(p) < DARK_SUM) or (50, 22, 25)
    skin = dominant(canvas, (int(eye[0] - eye[2]) - 24, int(eye[1] - eye[3]) - 24,
                             int(eye[0] + eye[2]) + 24, int(eye[1] + eye[3]) + 24),
                    lambda p: sum(p) > 430 and p[1] > p[0]) or (122, 210, 144)
    if report:
        print(f"eye: centre=({eye[0]:.0f},{eye[1]:.0f}) r=({eye[2]:.0f},{eye[3]:.0f})"
              f" ink={ink} skin={skin}")
    blink = build_blink(canvas, eye, skin, ink, closed=True)
    half = build_blink(canvas, eye, skin, ink, closed=False)
    os.makedirs(outdir, exist_ok=True)
    for name, image in (("blink.png", blink), ("blink_half.png", half)):
        path = os.path.join(outdir, name)
        pngtool.write(path, image)
        print("wrote", path, f"{canvas.w}x{canvas.h}")
    if preview:
        side = pngtool.Image(canvas.w * 3 + 40, canvas.h)
        for index, view in enumerate((canvas, half, blink)):
            x0 = index * (canvas.w + 20)
            for y in range(canvas.h):
                for x in range(canvas.w):
                    side.put(x0 + x, y, view.at(x, y))
        pngtool.write("/tmp/blink_preview.png", side)
        print("wrote /tmp/blink_preview.png (open, half, closed)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sheet", nargs="?")
    ap.add_argument("outdir", nargs="?", default="Resources/sprites")
    ap.add_argument("--frames", type=int, default=None)
    ap.add_argument("--preview", action="store_true")
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--blink-only", action="store_true",
                    help="regenerate blinks from the existing final idle frame")
    args = ap.parse_args()

    if args.blink_only:
        paths = glob.glob(os.path.join(args.outdir, "idle_*.png"))
        if not paths:
            ap.error("no idle frames found for --blink-only")
        last = max(paths, key=lambda p: int(os.path.basename(p)[5:-4]))
        existing = pngtool.read(last)
        write_blinks(existing, args.outdir, args.report, args.preview)
        return
    if not args.sheet:
        ap.error("a sprite sheet is required unless --blink-only is used")

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

    write_blinks(placed[-1][0], args.outdir, args.report, args.preview)


if __name__ == "__main__":
    main()
