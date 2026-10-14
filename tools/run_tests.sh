#!/usr/bin/env bash
# Runs the headless test suite. Usage: tools/run_tests.sh [path-to-godot]
# On macOS the default is the Godot app in /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-${GODOT:-}}"
if [[ -z "$GODOT" ]]; then
  if command -v godot >/dev/null 2>&1; then
    GODOT=godot
  elif [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
    GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
  else
    echo "Godot not found. Pass its path: tools/run_tests.sh /path/to/Godot" >&2
    exit 2
  fi
fi
# First run on a fresh clone: build the script class cache.
if [[ ! -d .godot ]]; then
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
"$GODOT" --headless --path . res://tests/test_runner.tscn
