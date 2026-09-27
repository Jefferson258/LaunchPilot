#!/usr/bin/env python3
"""Validate the LaunchPilot product registry without accepting duplicate keys."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


class DuplicateKey(ValueError):
    def __init__(self, key: str) -> None:
        super().__init__(f"duplicate JSON key {key!r}")
        self.key = key


def reject_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise DuplicateKey(key)
        result[key] = value
    return result


def main() -> int:
    path = Path(sys.argv[1] if len(sys.argv) > 1 else "config/products.json")
    if len(sys.argv) > 2:
        print("usage: validate-products.py [products.json]", file=sys.stderr)
        return 2
    try:
        with path.open(encoding="utf-8") as handle:
            registry = json.load(handle, object_pairs_hook=reject_duplicates)
    except DuplicateKey as exc:
        print(f"invalid product registry {path}: {exc}", file=sys.stderr)
        return 1
    except (OSError, json.JSONDecodeError) as exc:
        print(f"invalid product registry {path}: {exc}", file=sys.stderr)
        return 1

    if not isinstance(registry, dict):
        print(f"invalid product registry {path}: top level must be an object", file=sys.stderr)
        return 1
    print(f"valid product registry: {path} ({len(registry)} products)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
