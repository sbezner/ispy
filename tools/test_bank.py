#!/usr/bin/env python3
"""
Real-photo color test bank for I Spy: Colors.

The Swift unit tests (ColorDetectorTests) check the color logic on flat pixel
arrays. They do NOT exercise the real camera path: a photo squished to 100x100
(ImageAnalyzer) and run through match-fraction + contiguous-blob detection
(ColorDetector.analyze). That path is where real-world bugs hide — e.g. a deep
magenta eggplant scoring as pink instead of purple.

This harness closes that gap. It is a faithful Python port of ColorDetector +
ImageAnalyzer (keep the constants below in sync with the Swift source). It reads
real photos listed in photos/manifest.json, runs each through the full pipeline,
and asserts the colors the app SHOULD and SHOULD NOT find.

Usage:
    python3 tools/test_bank.py            # run the bank, print pass/fail
    python3 tools/test_bank.py -v         # also print all 9 color scores

Exit code is non-zero if any test fails, so it doubles as a regression check
after tuning a color.

Adding a test: drop a photo in photos/ and add an entry to photos/manifest.json:
    { "file": "red_firetruck.jpeg", "label": "toy fire truck",
      "expect_pass": ["red"], "expect_fail": ["pink", "orange"] }

Requires Pillow:  python3 -m pip install pillow
"""
import json
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("This tool needs Pillow. Install it with:  python3 -m pip install pillow")

# ---------------------------------------------------------------------------
#  PORT OF ColorDetector.swift  (keep these in sync with the Swift source)
# ---------------------------------------------------------------------------
SAMPLE_SIZE = 100                 # ImageAnalyzer.sampleSize
MIN_MATCH_FRACTION = 0.03         # ColorDetector.minMatchFraction
MIN_BLOB_FRACTION = 0.02          # ColorDetector.minBlobFraction
MIN_CHROMA_SATURATION = 0.20      # ColorDetector.minChromaSaturation
MIN_CHROMA_VALUE = 0.18           # ColorDetector.minChromaValue

COLORS = ["red", "orange", "yellow", "green", "blue", "purple", "pink", "white", "black"]

HUE_BANDS = {
    "red":    (345, 14),          # wraps around 0
    "orange": (14, 45),
    "yellow": (45, 66),
    "green":  (66, 168),
    "blue":   (168, 252),
    "purple": (252, 330),         # through the magenta-purples (eggplant ~319 deg)
    "pink":   (330, 345),         # pink is matched by is_pink, not this band
}


def hsv(r, g, b):
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    h = 0.0
    if d > 0:
        if mx == r:
            h = 60 * (((g - b) / d) % 6)
        elif mx == g:
            h = 60 * (((b - r) / d) + 2)
        else:
            h = 60 * (((r - g) / d) + 4)
    if h < 0:
        h += 360
    s = 0.0 if mx == 0 else d / mx
    return (h, s, mx)


def hue_contains(band, h):
    lo, hi = band
    return (lo <= h < hi) if lo <= hi else (h >= lo or h < hi)


def saturation_floor(color):
    return MIN_CHROMA_SATURATION * 0.7 if color in ("orange", "purple") else MIN_CHROMA_SATURATION


def is_pink(c):
    h, s, v = c
    if v < MIN_CHROMA_VALUE:
        return False
    pink_floor = MIN_CHROMA_SATURATION * 0.55
    if 330 <= h < 345 and s >= pink_floor:
        return True
    reddish = h >= 345 or h < 14
    if reddish and v >= 0.80 and pink_floor <= s <= 0.55:
        return True
    return False


def pixel_matches(c, color):
    h, s, v = c
    if color == "white":
        return s <= 0.16 and v >= 0.74
    if color == "black":
        return v <= 0.28
    if color == "pink":
        return is_pink(c)
    if s < saturation_floor(color) or v < MIN_CHROMA_VALUE:
        return False
    return hue_contains(HUE_BANDS[color], h)


def largest_blob(mask, w, h):
    visited = bytearray(len(mask))
    best = 0
    for start in range(len(mask)):
        if not mask[start] or visited[start]:
            continue
        size = 0
        stack = [start]
        visited[start] = 1
        while stack:
            i = stack.pop()
            size += 1
            x, y = i % w, i // w
            for n, ok in ((i - 1, x > 0), (i + 1, x < w - 1),
                          (i - w, y > 0), (i + w, y < h - 1)):
                if ok and mask[n] and not visited[n]:
                    visited[n] = 1
                    stack.append(n)
        if size > best:
            best = size
    return best


def analyze(hsvs, target):
    """Mirrors ColorDetector.analyze: match fraction + largest contiguous blob."""
    total = SAMPLE_SIZE * SAMPLE_SIZE
    mask = bytearray(total)
    match_count = 0
    for i, c in enumerate(hsvs):
        if pixel_matches(c, target):
            mask[i] = 1
            match_count += 1
    match_fraction = match_count / total
    blob_fraction = largest_blob(mask, SAMPLE_SIZE, SAMPLE_SIZE) / total
    passed = match_fraction >= MIN_MATCH_FRACTION and blob_fraction >= MIN_BLOB_FRACTION
    return match_fraction, blob_fraction, passed


def downsample(path):
    """Mirrors ImageAnalyzer.downsampledPixels: squish to SAMPLE_SIZE square."""
    img = Image.open(path).convert("RGB").resize((SAMPLE_SIZE, SAMPLE_SIZE), Image.BILINEAR)
    return [hsv(r / 255, g / 255, b / 255) for (r, g, b) in img.getdata()]


# ---------------------------------------------------------------------------
#  Test bank runner
# ---------------------------------------------------------------------------
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PHOTOS_DIR = os.path.join(REPO_ROOT, "photos")
MANIFEST = os.path.join(PHOTOS_DIR, "manifest.json")

GREEN, RED, GRAY, BOLD, RESET = "\033[32m", "\033[31m", "\033[90m", "\033[1m", "\033[0m"


def main():
    verbose = "-v" in sys.argv or "--verbose" in sys.argv
    if not os.path.exists(MANIFEST):
        sys.exit(f"No manifest found at {MANIFEST}")
    with open(MANIFEST) as f:
        tests = json.load(f).get("tests", [])

    print(f"{BOLD}I Spy: Colors — real-photo test bank{RESET}  ({len(tests)} photo(s))\n")
    failures = 0

    for t in tests:
        path = os.path.join(PHOTOS_DIR, t["file"])
        label = t.get("label", t["file"])
        if not os.path.exists(path):
            print(f"  {RED}MISSING{RESET}  {label}  ({t['file']})")
            failures += 1
            continue

        hsvs = downsample(path)
        scores = {col: analyze(hsvs, col) for col in COLORS}
        expect_pass = t.get("expect_pass", [])
        expect_fail = t.get("expect_fail", [])

        problems = []
        for col in expect_pass:
            if not scores[col][2]:
                problems.append(f"expected {col} to PASS but it failed")
        for col in expect_fail:
            if scores[col][2]:
                problems.append(f"expected {col} to FAIL but it passed")

        ok = not problems
        if not ok:
            failures += 1
        mark = f"{GREEN}PASS{RESET}" if ok else f"{RED}FAIL{RESET}"
        want = " ".join(f"+{c}" for c in expect_pass) + " " + " ".join(f"-{c}" for c in expect_fail)
        print(f"  {mark}  {BOLD}{label}{RESET}  {GRAY}({want.strip()}){RESET}")
        for p in problems:
            print(f"        {RED}- {p}{RESET}")
        if verbose:
            for col in COLORS:
                mf, bf, p = scores[col]
                tag = "PASS" if p else "no"
                print(f"        {GRAY}{col:7} match {mf*100:5.1f}%  blob {bf*100:5.1f}%  {tag}{RESET}")

    print()
    if failures:
        print(f"{RED}{BOLD}{failures} test(s) failed.{RESET}")
        sys.exit(1)
    print(f"{GREEN}{BOLD}All {len(tests)} test(s) passed.{RESET}")


if __name__ == "__main__":
    main()
