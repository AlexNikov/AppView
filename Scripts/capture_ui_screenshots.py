#!/usr/bin/env python3
"""Fetch /ui/view/{oid}/screenshot for inspector nodes listed in /ui/hierarchy JSON."""
from __future__ import annotations

import argparse
import base64
import json
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Optional

SCREENSHOT_TIMEOUT_SEC = 30
SCREENSHOT_RETRIES = 2

# Reuse tree normalization from hierarchy compare.
sys.path.insert(0, str(Path(__file__).resolve().parent))
from compare_ui_hierarchy import (  # noqa: E402
    inspector_window,
    load,
    normalize_class_name,
    normalize_identifier,
    normalize_label,
    prune_inspector_noise,
)

CAPTURE_SUFFIXES = (
    "AVSplitView",
    # AVPreviewView omitted: width follows iOS preview scale and differs between captures.
    "AVHierarchyView",
    "AVDashboardCardView",
    "AVDashboardSectionView",
    "AVDashboardCardTitleControl",
    "AVDashboardAttributeClassView",
    "AVDashboardAttributeRelationView",
    "AVDashboardAttributeRectView",
    "AVDashboardAttributeColorView",
    "AVDashboardAttributeColorContainerView",
    "AVDashboardAttributeSwitchView",
    "AVDashboardAttributeNumberInputView",
    "AVDashboardAttributeTextView",
)

MAX_HIERARCHY_ROWS = 24


def node_path(prefix: str, node: dict) -> str:
    cn = normalize_class_name(node.get("className", ""))
    label = normalize_label(cn, node.get("label", "") or "")
    ident = normalize_identifier(cn, node.get("identifier", "") or "")
    parts = [cn]
    if label:
        parts.append(f"[{label}]")
    if ident and ident not in (label, ""):
        parts.append(f"({ident})")
    name = "".join(parts) if len(parts) > 1 else cn
    return f"{prefix}/{name}" if prefix else name


def should_capture(node: dict, hierarchy_row_count: list[int]) -> bool:
    if node.get("hidden"):
        return False
    fr = node.get("frame", {})
    w = float(fr.get("width", 0))
    h = float(fr.get("height", 0))
    if w < 12 or h < 12:
        return False
    cn = normalize_class_name(node.get("className", ""))
    if cn.endswith("AVHierarchyRowView"):
        if hierarchy_row_count[0] >= MAX_HIERARCHY_ROWS:
            return False
        hierarchy_row_count[0] += 1
        return True
    return any(cn.endswith(s) for s in CAPTURE_SUFFIXES)


def walk_capture(
    node: dict,
    prefix: str,
    port: int,
    out_dir: Path,
    manifest: dict,
    hierarchy_row_count: list[int],
) -> None:
    path = node_path(prefix, node)
    if should_capture(node, hierarchy_row_count):
        oid = node.get("oid")
        if oid is not None:
            safe = re.sub(r"[^A-Za-z0-9._-]+", "_", path)[:180]
            fname = f"{safe}.png"
            url = f"http://127.0.0.1:{port}/ui/view/{oid}/screenshot"
            last_err: Optional[Exception] = None
            for attempt in range(SCREENSHOT_RETRIES + 1):
                try:
                    with urllib.request.urlopen(url, timeout=SCREENSHOT_TIMEOUT_SEC) as resp:
                        doc = json.load(resp)
                    b64 = doc.get("data", {}).get("imageBase64") or doc.get("imageBase64")
                    if b64:
                        out_dir.mkdir(parents=True, exist_ok=True)
                        png = base64.b64decode(b64)
                        (out_dir / fname).write_bytes(png)
                        manifest[path] = {
                            "file": fname,
                            "oid": oid,
                            "className": node.get("className"),
                            "frame": node.get("frame"),
                        }
                    last_err = None
                    break
                except (urllib.error.URLError, TimeoutError, json.JSONDecodeError, KeyError) as e:
                    last_err = e
                    if attempt < SCREENSHOT_RETRIES:
                        time.sleep(1.5 * (attempt + 1))
            if last_err is not None:
                manifest[path] = {"error": str(last_err), "oid": oid}

    for child in node.get("children", []):
        walk_capture(child, path, port, out_dir, manifest, hierarchy_row_count)
    if "contentView" in node:
        walk_capture(node["contentView"], path, port, out_dir, manifest, hierarchy_row_count)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--hierarchy", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    data = load(args.hierarchy)
    win = inspector_window(data)
    if not win:
        print("capture_ui_screenshots: no AVSplitView inspector window", file=sys.stderr)
        return 1

    win = prune_inspector_noise(win)
    out_dir = Path(args.out)
    manifest: dict = {}
    walk_capture(win, "", args.port, out_dir, manifest, [0])

    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    ok = sum(1 for v in manifest.values() if "file" in v)
    err = sum(1 for v in manifest.values() if "error" in v)
    print(f"capture_ui_screenshots: {ok} ok, {err} failed, {len(manifest)} paths -> {out_dir}")
    return 0 if ok > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
