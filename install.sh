#!/usr/bin/env bash
# Dev install: symlink package/ into the local plasmoid dir and refresh plasmashell.
set -euo pipefail
ID=com.github.thewrz.cellsignal
SRC="$(cd "$(dirname "$0")" && pwd)/package"
DST="$HOME/.local/share/plasma/plasmoids/$ID"
mkdir -p "$(dirname "$DST")"
[ -e "$DST" ] && rm -rf "$DST"
ln -s "$SRC" "$DST"
rm -rf "$HOME/.cache/plasmashell/qmlcache" 2>/dev/null || true
echo "linked $DST -> $SRC"
echo "test with: plasmoidviewer -a $ID   (or restart plasmashell: systemctl --user restart plasma-plasmashell)"
