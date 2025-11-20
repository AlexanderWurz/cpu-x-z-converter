#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONVERTER="$ROOT/src/convert_more.sh"
OUTDIR="/tmp/cpu-x-z-out"
DIFFDIR="/tmp/cpu-x-z-diffs"
mkdir -p "$OUTDIR" "$DIFFDIR"

passed=0
failed=0
total=0

for case in "$ROOT"/tests/*; do
  [ -d "$case" ] || continue
  total=$((total+1))
  basename_case=$(basename "$case")
  infile=$(ls "$case"/*cpu-x*.txt 2>/dev/null | head -n1 || true)
  expected=$(ls "$case"/*cpu-z*.txt "$case"/*CPU-Z*.txt 2>/dev/null | head -n1 || true)
  if [ -z "$infile" ] || [ -z "$expected" ]; then
    printf "Skipping %s: missing input or expected file\n" "$basename_case"
    continue
  fi
  out="$OUTDIR/out_${basename_case}.txt"
  diffout="$DIFFDIR/diff_${basename_case}.patch"
  echo "Running converter for $basename_case -> $out"
  "$CONVERTER" "$infile" > "$out"
  if diff -u "$expected" "$out" > "$diffout"; then
    echo "[PASS] $basename_case"
    passed=$((passed+1))
    rm -f "$diffout"
  else
    echo "[FAIL] $basename_case -> diff saved to $diffout"
    failed=$((failed+1))
  fi
done

echo
echo "Summary: total=$total passed=$passed failed=$failed"
if [ "$failed" -gt 0 ]; then
  exit 2
fi
exit 0
