#!/usr/bin/env bash
#
# Builds an Android APK for one of the games in this repo, from nothing.
#
#   tools/build_android.sh [game-dir]        # defaults to games/planet-hopper
#
# It provisions everything it needs into $IHIG_TOOLCHAIN (default
# ~/.ihig-toolchain) and is safe to re-run: each step is skipped if its output
# is already present.
#
# Why there is a hand-rolled apksigner in here
# --------------------------------------------
# Godot shells out to the Android SDK's `apksigner` to sign the APK. The SDK is
# only distributed from dl.google.com, which is not reachable from every build
# environment (including the one this was first written in). Everything else
# Godot needs for a non-Gradle export is in the export templates, so instead of
# the full SDK we build a minimal one containing a working `apksigner` on top of
# the `apksig` library from Maven Central. If you do have a real Android SDK,
# set ANDROID_SDK_ROOT and it is used instead.
#
# The signing key is generated locally on first run and kept out of the repo.
# It is a self-signed key, which is fine for sideloading and for CI, but it is
# NOT a key you should publish to Google Play with — generate and safeguard your
# own for that, and pass it via the GODOT_ANDROID_KEYSTORE_RELEASE_* variables.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAME_DIR="$(cd "${1:-$REPO_ROOT/games/planet-hopper}" && pwd)"
GAME_NAME="$(basename "$GAME_DIR")"

GODOT_VERSION="${GODOT_VERSION:-4.6.2-stable}"
GODOT_TEMPLATE_DIR_NAME="${GODOT_VERSION/-/.}"   # 4.6.2-stable -> 4.6.2.stable
APKSIG_VERSION="${APKSIG_VERSION:-2.3.0}"

TOOLCHAIN="${IHIG_TOOLCHAIN:-$HOME/.ihig-toolchain}"
GODOT_BIN="$TOOLCHAIN/godot/Godot_v${GODOT_VERSION}_linux.x86_64"
SHIM_SDK="$TOOLCHAIN/android-sdk"
KEYSTORE="$TOOLCHAIN/keystore/ihig-release.keystore"
OUT_DIR="$REPO_ROOT/build"
OUT_APK="$OUT_DIR/${GAME_NAME}.apk"

KEY_ALIAS="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-ihig}"
KEY_PASS="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-ihigrelease}"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

need() {
	command -v "$1" >/dev/null 2>&1 || { echo "error: '$1' is required but not installed" >&2; exit 1; }
}

need curl
need unzip
need java
need keytool
need javac

# --- Godot engine + export templates -----------------------------------------

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

install_templates() {
	local dest="$HOME/.local/share/godot/export_templates/$GODOT_TEMPLATE_DIR_NAME"
	if [[ -f "$dest/android_release.apk" ]]; then
		say "Export templates already present"
		return
	fi
	say "Downloading export templates (this one is large)"
	local tmp="$TOOLCHAIN/templates"
	mkdir -p "$tmp" "$(dirname "$dest")"
	curl -fsSL --retry 4 --retry-delay 3 \
		-o "$tmp/templates.tpz" \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
	rm -rf "$tmp/templates"
	unzip -oq "$tmp/templates.tpz" -d "$tmp"
	rm -rf "$dest"
	mv "$tmp/templates" "$dest"
	rm -f "$tmp/templates.tpz"
}

# --- Minimal Android SDK (apksigner only) ------------------------------------

build_apksigner() {
	local libdir="$SHIM_SDK/build-tools/35.0.0/lib"
	mkdir -p "$libdir" "$SHIM_SDK/platform-tools"

	if [[ -f "$libdir/apksigner-shim.jar" && -f "$libdir/apksig.jar" ]]; then
		say "apksigner shim already built"
	else
		say "Building apksigner shim on apksig $APKSIG_VERSION"
		local apksig="$libdir/apksig.jar"
		curl -fsSL --retry 4 --retry-delay 3 -o "$apksig" \
			"https://repo1.maven.org/maven2/com/android/tools/build/apksig/${APKSIG_VERSION}/apksig-${APKSIG_VERSION}.jar"

		local work
		work="$(mktemp -d)"
		javac -nowarn -cp "$apksig" -d "$work" \
			"$REPO_ROOT/tools/apksigner-shim/src/ihig/apksigner/ApkSignerCli.java"
		(cd "$work" && jar cf "$libdir/apksigner-shim.jar" .)
		rm -rf "$work"
	fi

	# The wrappers are rewritten every run so a change here takes effect without
	# having to clear the toolchain directory.
	#
	# The --add-exports are not optional: the apksig published to Maven Central
	# predates the module system and reaches into sun.security.* to build the
	# PKCS#7 block for v1 signatures. Without them JDK 9+ throws
	# IllegalAccessError the moment it tries to sign.
	cat > "$SHIM_SDK/build-tools/35.0.0/apksigner" <<'EOF'
#!/bin/sh
# Stand-in for the Android SDK's apksigner. See tools/apksigner-shim/.
unset JAVA_TOOL_OPTIONS
here="$(cd "$(dirname "$0")" && pwd)"
exec java \
	--add-exports java.base/sun.security.x509=ALL-UNNAMED \
	--add-exports java.base/sun.security.pkcs=ALL-UNNAMED \
	--add-exports java.base/sun.security.util=ALL-UNNAMED \
	-cp "$here/lib/apksigner-shim.jar:$here/lib/apksig.jar" \
	ihig.apksigner.ApkSignerCli "$@"
EOF
	chmod +x "$SHIM_SDK/build-tools/35.0.0/apksigner"

	# Godot checks that adb exists before it will export. It is only ever run
	# to deploy to an attached device, which this build does not do.
	# Godot probes for devices after an export. Reporting none (silently, and
	# successfully) is the honest answer here and keeps the build output clean.
	cat > "$SHIM_SDK/platform-tools/adb" <<'EOF'
#!/bin/sh
exit 0
EOF
	chmod +x "$SHIM_SDK/platform-tools/adb"
}

# --- Signing key --------------------------------------------------------------

create_keystore() {
	if [[ -n "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]]; then
		say "Using keystore from GODOT_ANDROID_KEYSTORE_RELEASE_PATH"
		KEYSTORE="$GODOT_ANDROID_KEYSTORE_RELEASE_PATH"
		return
	fi
	if [[ -f "$KEYSTORE" ]]; then
		say "Signing key already present"
		return
	fi
	say "Generating a self-signed release key"
	mkdir -p "$(dirname "$KEYSTORE")"
	keytool -genkeypair -v \
		-keystore "$KEYSTORE" -storetype PKCS12 \
		-storepass "$KEY_PASS" -keypass "$KEY_PASS" \
		-alias "$KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 10000 \
		-dname "cn=IHIG, ou=Games, o=IHIG, c=US" >/dev/null
	chmod 600 "$KEYSTORE"
}

# --- Godot editor settings ----------------------------------------------------

configure_editor_settings() {
	say "Pointing Godot at the toolchain"
	# Creating the settings file is a side effect of the first project import.
	"$GODOT_BIN" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true

	local settings
	settings="$(ls -1 "$HOME/.config/godot"/editor_settings-*.tres 2>/dev/null | head -1 || true)"
	if [[ -z "$settings" ]]; then
		echo "error: could not find Godot editor settings to configure" >&2
		exit 1
	fi

	local sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$SHIM_SDK}}"
	local jdk="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")}"

	SETTINGS_FILE="$settings" SDK_PATH="$sdk" JDK_PATH="$jdk" python3 - <<'PY'
import os, re

path = os.environ["SETTINGS_FILE"]
wanted = {
    "export/android/android_sdk_path": os.environ["SDK_PATH"],
    "export/android/java_sdk_path": os.environ["JDK_PATH"],
}

with open(path, encoding="utf-8") as f:
    lines = f.read().splitlines()

for key, value in wanted.items():
    entry = '%s = "%s"' % (key, value)
    pattern = re.compile(r"^%s\s*=" % re.escape(key))
    for i, line in enumerate(lines):
        if pattern.match(line):
            lines[i] = entry
            break
    else:
        lines.append(entry)

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
print("  android_sdk_path = %s" % wanted["export/android/android_sdk_path"])
print("  java_sdk_path    = %s" % wanted["export/android/java_sdk_path"])
PY
}

# --- Export -------------------------------------------------------------------

export_apk() {
	say "Exporting $GAME_NAME"
	mkdir -p "$OUT_DIR"
	rm -f "$OUT_APK"

	export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYSTORE"
	export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$KEY_ALIAS"
	export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$KEY_PASS"

	"$GODOT_BIN" --headless --path "$GAME_DIR" --export-release "Android" "$OUT_APK"

	if [[ ! -f "$OUT_APK" ]]; then
		echo "error: export finished but $OUT_APK was not produced" >&2
		exit 1
	fi
}

verify_apk() {
	say "Verifying signature"
	"$SHIM_SDK/build-tools/35.0.0/apksigner" verify --verbose "$OUT_APK"
	printf '\n\033[1;32mBuilt %s (%s)\033[0m\n' "$OUT_APK" "$(du -h "$OUT_APK" | cut -f1)"
	echo "Install with: adb install -r $OUT_APK"
}

install_godot
install_templates
build_apksigner
create_keystore
configure_editor_settings
export_apk
verify_apk
