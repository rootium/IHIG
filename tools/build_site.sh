#!/usr/bin/env bash
#
# Rebuilds the web exports under docs/, which is what GitHub Pages serves.
#
#   tools/build_site.sh              # all three games
#   tools/build_site.sh lumen        # just one
#
# Why this exists rather than a `cp -r build/web/. docs/`:
#
# Every game in this repo exports a byte-identical 37 MB index.wasm — that file
# is the Godot engine, not the game. The game is the pck beside it, which is
# tens of kilobytes. Three self-contained copies would mean a visitor who tries
# a second game downloads the same 37 MB a second time.
#
# So docs/ keeps ONE copy, in docs/engine/, and each game's shell is built to
# point at it (see the GODOT_CONFIG block in each games/*/shell.html). The two
# audio worklets are resolved from the same path by the loader, so they live in
# docs/engine/ too. This script is what puts them there; copying an export
# directory in by hand would leave a per-game index.wasm that nothing loads and
# an engine directory that has gone stale.
#
# The hand-written parts of the site — index.html, get/, shots/, download/ —
# are not touched.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GODOT_VERSION="${GODOT_VERSION:-4.6.2-stable}"
TOOLCHAIN="${IHIG_TOOLCHAIN:-$HOME/.ihig-toolchain}"
GODOT_BIN="${GODOT_BIN:-$TOOLCHAIN/godot/Godot_v${GODOT_VERSION}_linux.x86_64}"

GAMES=("$@")
if [[ ${#GAMES[@]} -eq 0 ]]; then
	GAMES=(tessera lumen planet-hopper)
fi

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror: %s\033[0m\n' "$*" >&2; exit 1; }

[[ -x "$GODOT_BIN" ]] || die "Godot not found at $GODOT_BIN — run tools/build.sh once to provision it, or set GODOT_BIN."

mkdir -p docs/engine

for game in "${GAMES[@]}"; do
	[[ -d "games/$game" ]] || die "no such game: games/$game"
	say "Exporting $game for web"
	out="build/web-$game"
	rm -rf "$out"
	mkdir -p "$out"
	"$GODOT_BIN" --headless --path "games/$game" --export-release "Web" "../../$out/index.html"

	mkdir -p "docs/$game"
	# Per game: the loader, the pck, the page, and the icons the page references.
	# Deliberately NOT index.wasm — that is the shared engine.
	for f in index.html index.js index.pck index.icon.png index.apple-touch-icon.png index.png; do
		[[ -f "$out/$f" ]] && cp "$out/$f" "docs/$game/"
	done
	rm -f "docs/$game/index.wasm"
done

# The engine, taken from whichever game was built last. It is the same file in
# every export; the check below is what makes that an assertion rather than an
# assumption, because a mismatch means the exports disagree on engine version
# and sharing one would silently ship the wrong runtime for the others.
last="build/web-${GAMES[-1]}"
say "Installing the shared engine from $last"
for pair in "index.wasm:godot.wasm" \
            "index.audio.worklet.js:godot.audio.worklet.js" \
            "index.audio.position.worklet.js:godot.audio.position.worklet.js"; do
	src="${pair%%:*}"
	dst="${pair##*:}"
	[[ -f "$last/$src" ]] || die "$last/$src is missing"
	for game in "${GAMES[@]}"; do
		other="build/web-$game/$src"
		[[ -f "$other" ]] || continue
		if ! cmp -s "$last/$src" "$other"; then
			die "$src differs between $game and ${GAMES[-1]}; the exports are not on the same engine, so they cannot share one."
		fi
	done
	cp "$last/$src" "docs/engine/$dst"
done

say "docs/ is $(du -sh docs | cut -f1)"
printf '\nPreview it with:\n  python3 -m http.server 8000 --directory docs\n\n'
