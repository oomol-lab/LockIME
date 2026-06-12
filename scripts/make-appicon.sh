#!/bin/bash
# make-appicon.sh — regenerate LockIME's AppIcon.appiconset from the committed
# raster master (scripts/appicon-master.png). Fully headless; no design tool
# required.
#
#   ./scripts/make-appicon.sh
#
# Normalizes the master to a 1024 full-bleed square, composes the macOS-grid
# app icon once at 1024 (insets the art onto the standard ~824px rounded body
# with the system's transparent margin and a soft drop shadow — see
# scripts/icon-tools/ComposeAppIcon.swift), then downscales that single composed
# 1024 into the 7 unique pixel sizes the macOS .appiconset needs
# (16/32/64/128/256/512/1024). Composing once and downscaling keeps the rounded
# body, margin, and shadow identical across every size. Contents.json
# (committed) maps those files into the 10 required @1x/@2x slots.
#
# If the raster master is absent, falls back to rendering the legacy SwiftUI
# vector padlock (scripts/MakeIcon.swift).
set -euo pipefail
cd "$(dirname "$0")/.."

SET="Sources/LockIME/Assets.xcassets/AppIcon.appiconset"
TMP="/tmp/lockime-icon"
MASTER="scripts/appicon-master.png"
COMPOSE="scripts/icon-tools/ComposeAppIcon.swift"

mkdir -p "$TMP"
if [[ -f "$MASTER" ]]; then
  echo "→ normalizing ${MASTER} to 1024×1024…"
  sips -s format png -z 1024 1024 "$MASTER" --out "$TMP/master.png" >/dev/null
else
  echo "→ rendering master via ImageRenderer…"
  swift scripts/MakeIcon.swift
fi

echo "→ composing grid-correct 1024 icon…"
mkdir -p "$SET"
swift "$COMPOSE" "$TMP/master.png" "$SET/icon_1024.png"

echo "→ downscaling into ${SET}…"
for sz in 16 32 64 128 256 512; do
  sips -s format png -z "$sz" "$sz" "$SET/icon_1024.png" --out "$SET/icon_${sz}.png" >/dev/null
done

echo "✓ appiconset updated:"
ls -1 "$SET" | sed 's/^/   /'
