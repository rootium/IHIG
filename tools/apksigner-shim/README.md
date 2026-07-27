# apksigner shim

A minimal stand-in for the Android SDK's `apksigner`, built on the `apksig`
library from Maven Central.

## Why this exists

Godot's Android export shells out to `apksigner` to sign the APK it produces.
`apksigner` ships only as part of the Android SDK build-tools, which Google
distributes exclusively from `dl.google.com`. That host is not reachable from
every build environment — it was blocked in the one this repo was first built
in — and there is no mirror on Maven Central or GitHub.

Everything *else* Godot needs for a non-Gradle Android export is already inside
the export templates: the template APK, the native libraries, and Godot's own
zipalign implementation. Signing was the only gap. `apksig`, the library that
`apksigner` is a thin CLI over, *is* on Maven Central — so this is that thin CLI,
re-implemented against the three invocations Godot actually makes:

```
apksigner --version
apksigner sign --verbose --ks K --ks-pass pass:P --ks-key-alias A app.apk
apksigner verify --verbose app.apk
```

`tools/build_android.sh` compiles this into a directory shaped like an Android
SDK (`build-tools/35.0.0/apksigner`, plus a no-op `platform-tools/adb` that
Godot checks for) and points Godot's editor settings at it.

If you have a real Android SDK, set `ANDROID_SDK_ROOT` and the build uses that
instead — this shim is a fallback, not a preference.

## What it signs

**APK Signature Scheme v2 only.** Godot refuses to build for anything below API
24 (Android 7.0), and every Android release from 7.0 onward verifies v2, so v2
alone covers every device Godot's output can run on.

v1 (JAR) signing is deliberately disabled. The newest `apksig` on Maven Central
is 2.3.0, which builds its PKCS#7 signature block through
`sun.security.pkcs.PKCS7.encodeSignedData` — a JDK-internal method that no
longer exists in JDK 9+. Asking for `--v1-signing-enabled true` returns a clear
error rather than a stack trace. v3 and v4 postdate 2.3.0 entirely; those flags
are parsed and ignored.

Alignment is not touched. Godot zipaligns before calling out, and apksig
preserves existing entry alignment.

## Limits

This is scoped to what Godot needs, not to being a general `apksigner`
replacement. Unknown options are rejected loudly rather than silently skipped,
so if a future Godot version changes its invocation the build fails with a
readable message instead of producing a subtly wrong APK.
