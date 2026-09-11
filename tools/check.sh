#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT_BIN" --headless --path . --script tests/rules.gd
"$GODOT_BIN" --headless --path . --script tests/skills_test.gd
"$GODOT_BIN" --headless --path . --script tests/littleblack.gd
"$GODOT_BIN" --headless --path . --script tests/roster_network.gd
"$GODOT_BIN" --headless --path . --script tests/rollback_test.gd
"$GODOT_BIN" --headless --path . --script tests/soak.gd
