#!/usr/bin/env bash
# Build a store-uploadable .plasmoid (zip of package/ contents).
set -euo pipefail
cd "$(dirname "$0")"
VER=$(python3 -c "import json; print(json.load(open('package/metadata.json'))['KPlugin']['Version'])")
mkdir -p dist
OUT="dist/cellsignal-v${VER}.plasmoid"
rm -f "$OUT"
(cd package && zip -qr "../$OUT" .)
echo "built $OUT"
