# YouTube Playables: where these games actually stand

Notes for deciding whether to take these games to
[YouTube Playables](https://developers.google.com/youtube/gaming/playables),
written after measuring rather than guessing. Nothing here has been submitted;
this is the homework.

## The requirements

From Google's published certification pages:

| | Limit | Ideal |
| --- | --- | --- |
| Initial bundle | under 15 MB | 5 MB |
| Total bundle | under 250 MB | 15 MB |
| Any single file | under 30 MB | under 512 KB |
| Time to interactive | 5 seconds | — |
| Saved game data | under 3 MB | under 500 KB |

Games must not make external calls; everything ships in the bundle. Godot is on
the list of supported engines.

Access is **not self-serve**. It is an interest form, partner onboarding and an
approval that takes weeks to months, so none of this is same-week work no matter
what the build looks like.

## What we actually ship, measured

Godot 4.6.2, GL Compatibility, no threads. Every game exports a
**byte-identical** `index.wasm` — that file is the engine. The game is the pck
beside it.

| File | Raw | gzip -9 | brotli -11 |
| --- | --- | --- | --- |
| `godot.wasm` (engine) | 37.70 MB | 9.38 MB | **6.61 MB** |
| loader `index.js` | 0.32 MB | 0.08 MB | ~0.06 MB |
| Tessera pck | 1.21 MB | 1.16 MB | ~1.10 MB |
| Lumen pck | 0.06 MB | 0.05 MB | ~0.05 MB |
| Planet Hopper pck | 0.06 MB | 0.06 MB | ~0.05 MB |

Initial bundle per game:

| Game | Raw | gzip | brotli |
| --- | --- | --- | --- |
| Tessera | 39.2 MB | 10.6 MB | **~7.8 MB** |
| Lumen | 38.1 MB | 9.5 MB | **~6.7 MB** |
| Planet Hopper | 38.1 MB | 9.5 MB | **~6.7 MB** |

## The one question that decides it

**Are the size limits measured on the raw file or on the transfer?**

- Measured on the **transfer**: brotli puts every game at 6.7–7.8 MB, inside the
  15 MB initial-bundle limit with room to spare, and inside the 30 MB per-file
  cap. Godot is viable.
- Measured **raw**: the 37.7 MB wasm breaks the 30 MB per-file cap on its own,
  before any game content exists. No amount of pck trimming helps, because the
  problem is not the game.

This has not been resolved. Google's certification pages return 403 without
developer-portal access, so the answer is behind the approval process. Per-file
caps usually describe decode and memory rather than transfer, which is the
pessimistic reading — but that is inference, not the documentation.

**Ask this first, before doing any engine work.** Everything below is wasted
effort if the answer is "transfer", and insufficient if the answer is "raw".

## Levers, if the answer is "raw"

Roughly in order of payoff per unit of pain. Only the first is measured.

1. **Brotli precompression** — measured: 37.70 MB → 6.61 MB. Free, and worth
   doing regardless. Does nothing for a raw-bytes limit.
2. **A custom export template with unused modules disabled.** The stock template
   carries a great deal these games never touch. Godot's own docs put a stripped
   web build at roughly half the stock size; that would be an estimated ~18-20 MB
   raw, which clears the 30 MB per-file cap but is still far outside a 15 MB
   initial bundle. Costs a from-source engine build in CI. **Estimated, not
   measured.**
3. **Drop 3D entirely.** Lumen and Planet Hopper are 2D and never instance a
   single 3D node; a 2D-only template is dramatically smaller. Tessera cannot do
   this — it is a 3D game.

Even stacked, these do not obviously reach the 5 MB ideal, and the 5 second
time-to-interactive is a separate problem: the browser still has to compile the
wasm on a mid-range phone.

## The other option

**Godot is not a requirement.** It is what these were written in, not something
the games need.

Lumen is the natural candidate for a rewrite: a 2D grid, procedural drawing, no
assets, and the whole simulation is one traced beam. In TypeScript on a canvas
it would be a few hundred KB total — comfortably inside even the 5 MB ideal, and
interactive in well under a second. `scripts/beam.gd` and `scripts/generator.gd`
are about 400 lines between them and are pure logic with no engine dependency.

Planet Hopper is a similar shape. Tessera is the one that genuinely wants an
engine, and it is also the one whose 1.2 MB pck means the engine is 97% of its
download.

## Where this leaves things

The browser build on GitHub Pages is the right first step either way: it is what
an application would link to, and the shared-engine layout in `docs/` means
someone can try all three without paying for the runtime three times. That work
is done and does not depend on any of the above.

The Playables decision should wait on the raw-versus-transfer answer, which
comes with portal access, which comes from the interest form. Filling in that
form is the actual next action — not an engine rebuild.
