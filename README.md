# IHIG

A monorepo of small mobile games. Android is the only target for now.

Each game is a self-contained Godot 4 project under `games/`, with nothing
shared between them yet — shared code can move into a `shared/` addon once two
games actually want the same thing.

## Games

| Game | Directory | Status |
| --- | --- | --- |
| [Planet Hopper](games/planet-hopper) | `games/planet-hopper` | Playable (working title) |

## Building an APK

```sh
tools/build_android.sh                      # defaults to games/planet-hopper
tools/build_android.sh games/some-other-game
```

The script provisions everything it needs into `~/.ihig-toolchain` (override
with `IHIG_TOOLCHAIN`) and is safe to re-run — each step is skipped when its
output already exists. The first run downloads roughly 1.3 GB of Godot export
templates. Output lands in `build/<game>.apk`.

Requirements on the host: `curl`, `unzip`, `java`, `javac`, `keytool`
(a JDK 17+ is fine) and `python3`.

### About signing

The build generates a self-signed key at `~/.ihig-toolchain/keystore/` on first
run and signs with it. That is fine for sideloading and for CI, but it is **not**
a key to publish to Google Play with. For a real release, generate your own key,
keep it somewhere safe, and point the build at it:

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/your.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=your-alias
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
tools/build_android.sh
```

No keys or passwords are stored in this repo, and `*.keystore` / `*.jks` /
`*.p12` are gitignored.

APKs are signed with **APK Signature Scheme v2 only**. Godot will not build for
below API 24 (Android 7.0), and every release from 7.0 onward verifies v2, so
v1/JAR signing is not needed. See [`tools/apksigner-shim`](tools/apksigner-shim)
for why signing does not use the Android SDK.

## Layout

```
games/<name>/         a Godot 4 project, one per game
tools/build_android.sh provisions the toolchain and exports an APK
tools/apksigner-shim/  minimal apksigner used when the Android SDK is unreachable
build/                 APK output (gitignored)
```

`export_presets.cfg` is committed for each game. It normally holds signing
secrets and is gitignored in most Godot projects; here the keystore comes from
environment variables instead, so the file is safe to track and the build works
straight from a clone.
