#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")/.."
GODOT_BIN="${GODOT_BIN:-/Applications/Godot.app/Contents/MacOS/Godot}"
mkdir -p build/server build/windows
touch build/.gdignore
"$GODOT_BIN" --headless --editor --path . --import
"$GODOT_BIN" --headless --editor --path . --export-release macOS build/KOLBB-macOS.zip
"$GODOT_BIN" --headless --editor --path . --export-release Windows build/windows/KOLBB.exe
(cd build/windows && zip -q ../KOLBB-Windows-x64.zip KOLBB.exe)
"$GODOT_BIN" --headless --editor --path . --export-release 'Linux Server' build/server/kolbb-server.x86_64
cp server/install.sh server/kolbb.service server/kolbb.logrotate build/server/
COPYFILE_DISABLE=1 tar --no-xattrs -czf build/KOLBB-Ubuntu-server.tar.gz -C build/server .
echo 'Exported build/KOLBB-macOS.zip, build/KOLBB-Windows-x64.zip and build/KOLBB-Ubuntu-server.tar.gz'
