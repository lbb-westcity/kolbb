#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
"$GODOT_BIN" --headless --path . --script tests/improvements.gd
"$GODOT_BIN" --headless --path . --script tests/hud.gd
"$GODOT_BIN" --headless --path . --script tests/settings_ui.gd
"$GODOT_BIN" --headless --path . --script tests/pause_ui.gd
"$GODOT_BIN" --headless --path . --script tests/rules.gd
"$GODOT_BIN" --headless --path . --script tests/skills_test.gd
"$GODOT_BIN" --headless --path . --script tests/littleblack.gd
"$GODOT_BIN" --headless --path . --script tests/balance.gd
"$GODOT_BIN" --headless --path . --script tests/vfx.gd
"$GODOT_BIN" --headless --path . --script tests/roster_network.gd
"$GODOT_BIN" --headless --path . --script tests/rollback_test.gd
"$GODOT_BIN" --headless --path . --script tests/soak.gd
"$GODOT_BIN" --headless --path . --script tests/moves_ui.gd
