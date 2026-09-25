#!/usr/bin/env python3
"""Enforce a minimum line-coverage threshold on an lcov trace file.

Usage: check_coverage_threshold.py <coverage.lcov> <threshold-percent>

Parses LF (lines found) / LH (lines hit) records, aggregates across all
source files in the trace, and exits non-zero when the overall line
coverage percentage falls below the threshold. CI pins this at 90% for
the WineVaultDomain package (issue #8 quality gate).
"""

import sys


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(f"usage: {argv[0]} <coverage.lcov> <threshold-percent>", file=sys.stderr)
        return 2
    trace_path, threshold_raw = argv[1], argv[2]
    try:
        threshold = float(threshold_raw)
    except ValueError:
        print(f"threshold must be a number, got: {threshold_raw}", file=sys.stderr)
        return 2

    lines_found = 0
    lines_hit = 0
    per_file: list[tuple[str, int, int]] = []
    file_found = file_hit = 0
    file_name = ""
    seen_sf = False

    def close_file() -> None:
        nonlocal file_found, file_hit, seen_sf
        if seen_sf:
            per_file.append((file_name, file_hit, file_found))
        file_found = file_hit = 0
        seen_sf = False

    with open(trace_path, encoding="utf-8") as trace:
        for raw in trace:
            record = raw.strip()
            if record.startswith("SF:"):
                close_file()
                file_name = record[3:]
                seen_sf = True
            elif record.startswith("LF:"):
                file_found += int(record[3:])
            elif record.startswith("LH:"):
                file_hit += int(record[3:])
            elif record == "end_of_record":
                close_file()
    close_file()

    lines_found = sum(found for _, _, found in per_file)
    lines_hit = sum(hit for _, hit, _ in per_file)
    if lines_found == 0:
        print(f"ERROR: {trace_path} contains no line records", file=sys.stderr)
        return 1

    percent = lines_hit * 100.0 / lines_found
    print(f"Line coverage: {lines_hit}/{lines_found} = {percent:.2f}% "
          f"(threshold {threshold:.2f}%)")
    for name, hit, found in sorted(per_file):
        ratio = (hit * 100.0 / found) if found else 0.0
        print(f"  {ratio:6.2f}% {hit:5}/{found:<5} {name}")

    if percent < threshold:
        print(f"FAIL: coverage {percent:.2f}% is below the {threshold:.2f}% gate",
              file=sys.stderr)
        return 1
    print("PASS: coverage gate satisfied")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
