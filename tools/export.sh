#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
mkdir -p build/server
touch build/.gdignore
"$GODOT_BIN" --headless --editor --path . --import
"$GODOT_BIN" --headless --editor --path . --export-release macOS build/KOLBB-macOS.zip
"$GODOT_BIN" --headless --editor --path . --export-release 'Linux Server' build/server/kolbb-server.x86_64
cp server/install.sh server/kolbb.service server/kolbb.logrotate build/server/
tar -czf build/KOLBB-Ubuntu-server.tar.gz -C build/server .
echo 'Exported build/KOLBB-macOS.zip and build/KOLBB-Ubuntu-server.tar.gz'
