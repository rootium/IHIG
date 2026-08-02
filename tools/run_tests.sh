#!/usr/bin/env bash
#
# Runs every game's headless smoke test.
#
#   tools/run_tests.sh                       # all games
#   tools/run_tests.sh games/dunk-rush       # just one
#   FRAMES=60000 tools/run_tests.sh          # longer soak
#
# Provisions the Godot engine into $IHIG_TOOLCHAIN (default ~/.ihig-toolchain),
# the same place tools/build_android.sh puts it, and is safe to re-run. Only the
# engine is needed here — export templates are a build concern, not a test one,
# which is what keeps this cheap enough to gate every push on.
#
# Why the output is scraped rather than trusted to $?
# ---------------------------------------------------
# Godot exits 0 after a --script run that logged script errors, so an exit code
# alone will happily call a broken game green. A test is therefore only a pass
# if it printed its own OK line and logged nothing that looks like an error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

GODOT_VERSION="${GODOT_VERSION:-4.6.2-stable}"
TOOLCHAIN="${IHIG_TOOLCHAIN:-$HOME/.ihig-toolchain}"
GODOT_BIN="$TOOLCHAIN/godot/Godot_v${GODOT_VERSION}_linux.x86_64"
FRAMES="${FRAMES:-12000}"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31mFAIL: %s\033[0m\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fail "'curl' is required but not installed"
command -v unzip >/dev/null 2>&1 || fail "'unzip' is required but not installed"

install_godot() {
	if [[ -x "$GODOT_BIN" ]]; then
		say "Godot $GODOT_VERSION already present"
		return
	fi
	say "Downloading Godot $GODOT_VERSION"
	mkdir -p "$TOOLCHAIN/godot"
	curl -fsSL --retry 4 --retry-delay 3 \
		-o "$TOOLCHAIN/godot/godot.zip" \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
	unzip -oq "$TOOLCHAIN/godot/godot.zip" -d "$TOOLCHAIN/godot"
	chmod +x "$GODOT_BIN"
	rm -f "$TOOLCHAIN/godot/godot.zip"
}

run_game() {
	local game_dir="$1"
	local name
	name="$(basename "$game_dir")"

	if [[ ! -f "$game_dir/tests/smoke_test.gd" ]]; then
		say "$name has no smoke test — skipping"
		return
	fi

	say "Importing $name"
	# The first import of a fresh clone also compiles every script, so a parse
	# error shows up here rather than halfway through a soak run.
	local import_log
	import_log="$("$GODOT_BIN" --headless --path "$game_dir" --import 2>&1)" || true
	if grep -qE "SCRIPT ERROR|Parse Error|Compile Error" <<<"$import_log"; then
		echo "$import_log" >&2
		fail "$name failed to import"
	fi

	say "Testing $name ($FRAMES frames)"
	# --fixed-fps or the run takes as long as the play it simulates: without it
	# Godot paces its main loop to real time and sleeps most of every frame.
	local log
	log="$("$GODOT_BIN" --headless --fixed-fps 60 --path "$game_dir" \
		--script tests/smoke_test.gd -- "$FRAMES" 2>&1)" || true
	echo "$log"

	if grep -qE "SCRIPT ERROR|Parse Error|Compile Error" <<<"$log"; then
		fail "$name logged a script error"
	fi
	grep -qx "OK" <<<"$log" || fail "$name did not finish its smoke test"
}

install_godot

if [[ $# -gt 0 ]]; then
	for arg in "$@"; do
		run_game "$(cd "$arg" && pwd)"
	done
else
	for project in "$REPO_ROOT"/games/*/project.godot; do
		run_game "$(dirname "$project")"
	done
fi

say "All smoke tests passed"
