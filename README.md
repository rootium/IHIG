# IHIG

A monorepo of small games.

Each game is a self-contained Godot 4 project under `games/`, with nothing
shared between them but the build tooling — shared code can move into a
`shared/` addon once two games actually want the same thing.

## Games

| Game | Directory | Targets | Status |
| --- | --- | --- | --- |
| [Tessera](games/tessera) | `games/tessera` | web · Android · Windows · Linux | Playable — a puzzle game in four spatial dimensions |
| [Lumen](games/lumen) | `games/lumen` | Android | Playable (working title) — one-thumb light-routing puzzle |
| [Planet Hopper](games/planet-hopper) | `games/planet-hopper` | Android | Playable (working title) — endless one-thumb orbit climber |

**[▶ Play Tessera in the browser](https://rootium.github.io/IHIG/)** ·
[downloads](https://rootium.github.io/IHIG/get/)

The three are deliberately not the same kind of game. Planet Hopper is
continuous, physical and played on reflex. Lumen is a still board you think at.
Tessera is the big one: a 3D game whose world has a fourth spatial axis you can
step along and rotate into view, forty-three chambers deep, shipping to the web
and desktop as well as to a phone.

## Building

```sh
tools/build.sh games/tessera                 # web, android, linux, windows
tools/build.sh games/tessera web android     # or pick targets
tools/build_android.sh games/lumen           # the older games are Android-only
```

The script provisions everything it needs into `~/.ihig-toolchain` (override
with `IHIG_TOOLCHAIN`) and is safe to re-run — each step is skipped when its
output already exists. The first run downloads roughly 1.3 GB of Godot export
templates. Output lands in `build/`.

Requirements on the host: `curl`, `unzip`, `python3`, and for the Android target
also `java`, `javac` and `keytool` (a JDK 17+ is fine).

## The web build and GitHub Pages

`docs/` holds the built web export. `.github/workflows/pages.yml` mirrors it
onto the `gh-pages` branch on every push, and GitHub serves that branch at
[rootium.github.io/IHIG](https://rootium.github.io/IHIG/).

**If the site is not up yet**, Pages has never been switched on for this
repository, and neither a workflow nor this session can switch it on — creating
a Pages site needs a permission the Actions token is not granted. One click
fixes it: *Settings → Pages → Source: Deploy from a branch → `gh-pages` / `/`
(root)*. The branch is already there and already correct.

The export is committed rather than built in CI:
a Godot web export needs the engine plus 1.3 GB of templates, and making every
deploy re-download them to rebuild bytes that are already known would be slower
and much easier to break. To refresh it:

```sh
tools/build.sh games/tessera web
rm -rf docs && mkdir -p docs && cp -r build/web/. docs/
```

The web export is built **without thread support** on purpose. Threads need
`SharedArrayBuffer`, which needs COOP/COEP response headers, which GitHub Pages
cannot send. Building without them is what lets the same files drop straight
onto Pages and work.

Desktop binaries are not committed — they are about a hundred megabytes each,
which is more than a git repository should carry. They are one command away
from a clone.

### About signing

The Android build generates a self-signed key at `~/.ihig-toolchain/keystore/`
on first run and signs with it. That is fine for sideloading and for CI, but it
is **not** a key to publish to Google Play with. For a real release, generate
your own key, keep it somewhere safe, and point the build at it:

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/path/to/your.keystore
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=your-alias
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...
tools/build.sh games/tessera android
```

No keys or passwords are stored in this repo, and `*.keystore` / `*.jks` /
`*.p12` are gitignored.

APKs are signed with **APK Signature Scheme v2 only**. Godot will not build for
below API 24 (Android 7.0), and every release from 7.0 onward verifies v2, so
v1/JAR signing is not needed. See [`tools/apksigner-shim`](tools/apksigner-shim)
for why signing does not use the Android SDK.

## Layout

```
games/<name>/            a Godot 4 project, one per game
tools/build.sh           provisions the toolchain and exports any target
tools/build_android.sh   the Android path, including signing
tools/apksigner-shim/    minimal apksigner used when the Android SDK is unreachable
tools/tessera/           Tessera's level generator, solver and music renderer
docs/                    the built web export, served by GitHub Pages
build/                   local build output (gitignored)
```

`export_presets.cfg` is committed for each game. It normally holds signing
secrets and is gitignored in most Godot projects; here the keystore comes from
environment variables instead, so the file is safe to track and the build works
straight from a clone.
