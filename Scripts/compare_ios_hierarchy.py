#!/usr/bin/env python3
"""Normalize and compare AppViewServer MCP GET /hierarchy JSON snapshots."""

from __future__ import annotations

import json
import sys
from typing import Any


def _normalize_node(node: dict[str, Any], path: str) -> list[str]:
    lines: list[str] = []
    oid = node.get("oid", 0)
    class_name = node.get("className", "")
    custom = node.get("customTitle", "")
    hidden = node.get("hidden", False)
    children = node.get("children") or []
    line = f"{path} oid={oid} class={class_name!r} custom={custom!r} hidden={hidden} children={len(children)}"
    lines.append(line)
    for idx, child in enumerate(children):
        child_path = f"{path}/{idx}"
        lines.extend(_normalize_node(child, child_path))
    return lines


def normalize_tree(payload: dict[str, Any]) -> list[str]:
    data = payload.get("data") or payload
    items = data.get("items") or []
    lines: list[str] = []
    for idx, item in enumerate(items):
        lines.extend(_normalize_node(item, str(idx)))
    return lines


def compare(path_a: str, path_b: str) -> int:
    with open(path_a, encoding="utf-8") as f:
        a = json.load(f)
    with open(path_b, encoding="utf-8") as f:
        b = json.load(f)

    lines_a = normalize_tree(a)
    lines_b = normalize_tree(b)

    if lines_a == lines_b:
        print(f"RESULT: PASS — {len(lines_a)} nodes identical")
        return 0

    print(f"RESULT: FAIL — {len(lines_a)} vs {len(lines_b)} normalized lines")
    set_a = set(lines_a)
    set_b = set(lines_b)
    only_a = sorted(set_a - set_b)[:40]
    only_b = sorted(set_b - set_a)[:40]
    if only_a:
        print("\nOnly in first snapshot:")
        for line in only_a:
            print(f"  - {line}")
    if only_b:
        print("\nOnly in second snapshot:")
        for line in only_b:
            print(f"  + {line}")
    return 1


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: compare_ios_hierarchy.py a.json b.json", file=sys.stderr)
        sys.exit(2)
    sys.exit(compare(sys.argv[1], sys.argv[2]))
