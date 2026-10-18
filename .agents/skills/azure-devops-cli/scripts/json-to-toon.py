#!/usr/bin/env python3
"""JSON stdin/file → TOON stdout. Fallback when agentic-tool is not on PATH.

Requires: pip install toon-format==0.9.0b1
"""
from __future__ import annotations

import argparse
import json
import sys

try:
    from toon_format import encode, count_tokens
except ImportError:
    print(
        "toon-format not installed. Run: pip install 'toon-format==0.9.0b1'",
        file=sys.stderr,
    )
    sys.exit(1)


def main() -> int:
    parser = argparse.ArgumentParser(description="Encode JSON to TOON format")
    parser.add_argument("--stdin", action="store_true", help="Read JSON from stdin")
    parser.add_argument("--file", metavar="PATH", help="Read JSON from file")
    parser.add_argument("--stats", action="store_true", help="Print token stats to stderr")
    args = parser.parse_args()

    if args.file:
        with open(args.file, encoding="utf-8") as f:
            raw = f.read()
    elif args.stdin or not sys.stdin.isatty():
        raw = sys.stdin.read()
    else:
        parser.print_help()
        return 1

    data = json.loads(raw)
    compact_json = json.dumps(data, separators=(",", ":"))
    toon = encode(data)

    if args.stats:
        json_t = count_tokens(compact_json)
        toon_t = count_tokens(toon)
        saved = int((json_t - toon_t) / json_t * 100) if json_t > 0 else 0
        print(f"# tokens json={json_t} toon={toon_t} saved={saved}%", file=sys.stderr)

    sys.stdout.write(toon)
    if not toon.endswith("\n"):
        sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
