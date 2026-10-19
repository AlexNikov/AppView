#!/usr/bin/env python3
"""Compare inspector view screenshots captured from ObjC vs Swift (matched by tree path)."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image


def load_manifest(dir_path: Path) -> dict:
    p = dir_path / "manifest.json"
    if not p.is_file():
        return {}
    return json.loads(p.read_text(encoding="utf-8"))


def image_diff_ratio(a: Image.Image, b: Image.Image) -> float:
    """Mean grayscale pixel delta after normalizing to a common thumbnail size."""
    import numpy as np

    thumb = (160, 160)
    a_thumb = a.convert("L").resize(thumb, Image.Resampling.LANCZOS)
    b_thumb = b.convert("L").resize(thumb, Image.Resampling.LANCZOS)
    da = np.asarray(a_thumb, dtype=np.float32)
    db = np.asarray(b_thumb, dtype=np.float32)
    return float(np.mean(np.abs(da - db)) / 255.0)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("objc_dir")
    ap.add_argument("swift_dir")
    ap.add_argument("--threshold", type=float, default=0.02, help="Max mean diff ratio (default 2%%)")
    ap.add_argument("--report", default="", help="Write markdown report path")
    args = ap.parse_args()

    o_dir = Path(args.objc_dir)
    s_dir = Path(args.swift_dir)
    o_man = load_manifest(o_dir)
    s_man = load_manifest(s_dir)

    common = sorted(set(o_man) & set(s_man))
    only_o = sorted(set(o_man) - set(s_man))
    only_s = sorted(set(s_man) - set(o_man))

    mismatches: list[tuple[str, float, str]] = []
    missing_file: list[str] = []
    compared = 0

    for path in common:
        if "AVPreviewView" in path:
            continue
        o_entry, s_entry = o_man[path], s_man[path]
        if "error" in o_entry or "error" in s_entry:
            mismatches.append((path, 1.0, "capture error"))
            continue
        o_file = o_dir / o_entry["file"]
        s_file = s_dir / s_entry["file"]
        if not o_file.is_file() or not s_file.is_file():
            missing_file.append(path)
            continue
        o_img = Image.open(o_file)
        s_img = Image.open(s_file)
        if abs(o_img.width - s_img.width) > 4 or abs(o_img.height - s_img.height) > 4:
            mismatches.append((path, 1.0, f"size {o_img.size} vs {s_img.size}"))
            compared += 1
            continue
        ratio = image_diff_ratio(o_img, s_img)
        compared += 1
        if ratio > args.threshold:
            mismatches.append((path, ratio, f"{o_img.size} vs {s_img.size}"))

    lines = [
        f"Compared paths: {compared}",
        f"Common manifest paths: {len(common)}",
        f"Only ObjC: {len(only_o)}",
        f"Only Swift: {len(only_s)}",
        f"Mismatches (>{args.threshold:.1%} diff): {len(mismatches)}",
    ]

    if mismatches:
        lines.append("\nTop screenshot diffs:")
        for path, ratio, note in sorted(mismatches, key=lambda x: -x[1])[:30]:
            lines.append(f"  {ratio:.3%}  {path}  ({note})")
    if only_o:
        lines.append(f"\nScreenshots only ObjC ({len(only_o)}):")
        for p in only_o[:15]:
            lines.append(f"  {p}")
    if only_s:
        lines.append(f"\nScreenshots only Swift ({len(only_s)}):")
        for p in only_s[:15]:
            lines.append(f"  {p}")

    report_text = "\n".join(lines)
    print(report_text)

    if args.report:
        Path(args.report).write_text(
            "# UI screenshot comparison\n\n```\n" + report_text + "\n```\n",
            encoding="utf-8",
        )

    if compared == 0:
        print("RESULT: FAIL — no screenshot pairs compared")
        return 1
    if mismatches or only_o or only_s:
        print("RESULT: FAIL — screenshot parity")
        return 1
    print("RESULT: PASS — screenshots match within threshold")
    return 0


if __name__ == "__main__":
    sys.exit(main())
