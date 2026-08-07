#!/bin/sh
# Truth-pin: fail when product facts in this repo drift from ground truth.
# POSIX sh, no dependencies beyond git + grep.
set -eu
cd "$(dirname "$0")/.."

# Tracked text files, minus this script and the CHANGELOG (whose entries may
# legitimately describe historical values).
files=$(git ls-files | grep -vE '^(CHANGELOG\.md|scripts/truthcheck\.sh)$')

fail=0

forbid() {
  pattern="$1"
  why="$2"
  hits=$(printf '%s\n' "$files" | xargs grep -niE -- "$pattern" 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "FORBIDDEN ($why):"
    echo "$hits"
    fail=1
  fi
}

# Stale quota copy: the FREE tier is 100/day, never 100,000 or 100k.
forbid '100,?000 *(requests *)?(per|/) *day' 'stale day quota — FREE is 100/day'
forbid '100k *(per|/) *day' 'stale day quota — FREE is 100/day'
forbid 'free[^.]*1,?000[^0-9]*(per|/) *day' 'free tier paired with 1,000/day'
# Docs live on their own host.
forbid 'livetennisapi\.com/docs' 'docs live at docs.livetennisapi.com'
# Org identity only in metadata and docs.
forbid 'bensynapse' 'use the Live Tennis API org identity'
# The daily reset is a local-midnight-derived instant, not a fixed UTC hour.
forbid 'midnight UTC' 'daily reset is not midnight UTC — use resets_at'

# If the repo states quotas at all, it must state the current FREE quota and
# point at the real docs host.
if printf '%s\n' "$files" | xargs grep -liE 'requests?/day|per.day|quota' >/dev/null 2>&1; then
  if ! printf '%s\n' "$files" | xargs grep -lE '100 requests/day|100/day' >/dev/null 2>&1; then
    echo 'MISSING: quota copy exists but "100/day" (or "100 requests/day") for FREE is absent'
    fail=1
  fi
  if ! printf '%s\n' "$files" | xargs grep -l 'docs\.livetennisapi\.com' >/dev/null 2>&1; then
    echo 'MISSING: quota copy exists but docs.livetennisapi.com is absent'
    fail=1
  fi
fi

if [ "$fail" -ne 0 ]; then
  echo 'truthcheck: FAILED'
  exit 1
fi
echo 'truthcheck: OK'
