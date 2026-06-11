#!/bin/bash
# make-appicon.sh — regenerate LockIME's AppIcon.appiconset from the committed
# raster master (scripts/appicon-master.png). Fully headless; no design tool
# required.
#
#   ./scripts/make-appicon.sh
#
# Normalizes the master to a 1024 full-bleed square, downscales with sips into
# the 7 unique pixel sizes the macOS .appiconset needs
# (16/32/64/128/256/512/1024), then applies the rounded-rect alpha mask that
# older Launchpad/Finder surfaces do not apply for us. Contents.json
# (committed) maps those files into the 10 required @1x/@2x slots.
#
# If the raster master is absent, falls back to rendering the legacy SwiftUI
# vector padlock (scripts/MakeIcon.swift).
set -euo pipefail
cd "$(dirname "$0")/.."

SET="Sources/LockIME/Assets.xcassets/AppIcon.appiconset"
TMP="/tmp/lockime-icon"
MASTER="scripts/appicon-master.png"
MASK="scripts/icon-tools/MaskAppIcon.swift"

mkdir -p "$TMP"
if [[ -f "$MASTER" ]]; then
  echo "→ normalizing ${MASTER} to 1024×1024…"
  sips -s format png -z 1024 1024 "$MASTER" --out "$TMP/master.png" >/dev/null
else
  echo "→ rendering master via ImageRenderer…"
  swift scripts/MakeIcon.swift
fi

echo "→ downscaling into ${SET}…"
mkdir -p "$SET"
mask_args=()
for sz in 16 32 64 128 256 512; do
  raw="$TMP/icon_${sz}-raw.png"
  sips -s format png -z "$sz" "$sz" "$TMP/master.png" --out "$raw" >/dev/null
  mask_args+=("$raw" "$SET/icon_${sz}.png")
done
mask_args+=("$TMP/master.png" "$SET/icon_1024.png")
swift "$MASK" "${mask_args[@]}"

echo "✓ appiconset updated:"
ls -1 "$SET" | sed 's/^/   /'
