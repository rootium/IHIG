#!/usr/bin/env bash
#
# Builds one of the games in this repo for any target, from nothing.
#
#   tools/build.sh games/tessera                 # every target
#   tools/build.sh games/tessera web android     # just these
#
# Targets: web, android, linux, windows
#
# Everything it needs is provisioned into $IHIG_TOOLCHAIN (default
# ~/.ihig-toolchain) and every step is skipped when its output already exists,
# so re-running is cheap. The first run downloads Godot plus about 1.3 GB of
# export templates.
#
# Only the Android target needs the signing machinery; see
# tools/build_android.sh and tools/apksigner-shim/ for why signing does not use
# the Android SDK.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$(cd "${1:-$REPO_ROOT/games/tessera}" && pwd)"
GAME_NAME="$(basename "$GAME_DIR")"
shift || true
TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
	TARGETS=(web android linux windows)
fi

GODOT_VERSION="${GODOT_VERSION:-4.6.2-stable}"
GODOT_TEMPLATE_DIR_NAME="${GODOT_VERSION/-/.}"
TOOLCHAIN="${IHIG_TOOLCHAIN:-$HOME/.ihig-toolchain}"
GODOT_BIN="$TOOLCHAIN/godot/Godot_v${GODOT_VERSION}_linux.x86_64"
OUT_DIR="$REPO_ROOT/build"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed"; }
need curl
need unzip

install_godot() {
	if [[ -x "$GODOT_BIN" ]]; then return; fi
	say "Downloading Godot $GODOT_VERSION"
	mkdir -p "$TOOLCHAIN/godot"
	curl -fsSL --retry 4 --retry-delay 3 -o "$TOOLCHAIN/godot/godot.zip" \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
	unzip -oq "$TOOLCHAIN/godot/godot.zip" -d "$TOOLCHAIN/godot"
	chmod +x "$GODOT_BIN"
	rm -f "$TOOLCHAIN/godot/godot.zip"
}

install_templates() {
	local dest="$HOME/.local/share/godot/export_templates/$GODOT_TEMPLATE_DIR_NAME"
	if [[ -f "$dest/web_nothreads_release.zip" ]]; then return; fi
	say "Downloading export templates (this one is large)"
	local tmp="$TOOLCHAIN/templates"
	mkdir -p "$tmp" "$(dirname "$dest")"
	curl -fsSL --retry 4 --retry-delay 3 -o "$tmp/templates.tpz" \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
	rm -rf "$tmp/templates"
	unzip -oq "$tmp/templates.tpz" -d "$tmp"
	rm -rf "$dest"
	mv "$tmp/templates" "$dest"
	rm -f "$tmp/templates.tpz"
}

# One import pass up front; the per-target exports then reuse the cache.
import_project() {
	say "Importing $GAME_NAME"
	"$GODOT_BIN" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true
}

export_preset() {
	local preset="$1" out="$2"
	say "Exporting $GAME_NAME → $preset"
	mkdir -p "$(dirname "$out")"
	"$GODOT_BIN" --headless --path "$GAME_DIR" --export-release "$preset" "$out"
	[[ -e "$out" ]] || die "export finished but $out was not produced"
}

install_godot
install_templates
import_project

for target in "${TARGETS[@]}"; do
	case "$target" in
	web)
		rm -rf "$OUT_DIR/web"
		export_preset "Web" "$OUT_DIR/web/index.html"
		# Pages serves the directory as-is; this stops Jekyll eating files
		# whose names begin with an underscore.
		touch "$OUT_DIR/web/.nojekyll"
		printf '%s: %s\n' "$GAME_NAME" "$(du -sh "$OUT_DIR/web" | cut -f1)"
		;;
	android)
		"$REPO_ROOT/tools/build_android.sh" "$GAME_DIR"
		;;
	linux)
		export_preset "Linux" "$OUT_DIR/pc/${GAME_NAME}-linux-x86_64"
		chmod +x "$OUT_DIR/pc/${GAME_NAME}-linux-x86_64"
		;;
	windows)
		export_preset "Windows" "$OUT_DIR/pc/${GAME_NAME}-windows-x86_64.exe"
		;;
	*)
		die "unknown target '$target' (web, android, linux, windows)"
		;;
	esac
done

say "Done"
find "$OUT_DIR" -maxdepth 2 -type f -newermt '-1 hour' \
	\( -name '*.apk' -o -name '*.exe' -o -name 'index.html' -o -name "${GAME_NAME}-linux*" \) \
	-printf '  %-52p %s bytes\n' 2>/dev/null || true
