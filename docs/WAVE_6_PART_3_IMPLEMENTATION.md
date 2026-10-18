# W6.3 — Voxel Asset Forge implementation

Owner authorization: 2026-10-18, `main` starting at
`3579e765a63293ea5ca28b50b22d9fa231f0995d`. D1–D8 are approved in the
[design](WAVE_6_PART_3_VOXEL_ASSET_FORGE_DESIGN.md). W6.2 is formally
[CLOSED — OWNER ACCEPTED](WAVE_6_PART_2_CLOSURE.md).

Status: **implementation candidate; complete certification and owner acceptance
required**. Focused results alone cannot certify or authorize publication of the
stage. Append-only receipts under `.verification/wave6/w6_3/run-*/` identify the
exact tested source. No owner acceptance is claimed by this document.

## Launch and edit

From `D:\AI\Projects\Leyforge-Rebuild`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\run_forge.ps1
```

The launcher copies/imports a disposable project and selects this repository as
the explicit canonical authoring root. The separate Forge profile is under
`APPDATA/LeyforgeForge`. No game save is opened. Use a disposable checkout/content
root for owner publication tests; canonical changes affect multiplayer content
compatibility. The real production content contains no W6.3 demonstration assets.

Open **Voxel Asset**. Enter `namespace:name` and a display name, then **New** for
an empty volume. **Open source** selects an existing published asset by ID;
**Reopen draft** restores its independent voxel draft. Existing catalogue controls
at the shell top continue to address the W6.2 catalogue document; voxel controls
are inside the Voxel Asset workspace.

The volume contains 16×16×16 cells at 16 cells/metre: 0.0625 m cubes, lower-corner
origin, +X right, +Y up, −Z front. Dimensions and density are separate source
fields. Base block textures remain 32×32 pixels and texture painting is deferred.

- LMB uses Select, Place, Remove or Paint. Place on the construction plane or an
  exposed face; Remove/Paint use the frontmost occupied cell. Invalid targets are
  red and reject the edit. Paint never creates geometry.
- Drag LMB for one grouped stroke; release commits atomically. Escape, leaving
  the viewport, navigation, camera capture or focus loss cancels unfinished work.
- RMB drag orbits; MMB pans; wheel zooms; F frames selection/model. Front, Top and
  Side views share that camera. Camera/selection never change document history.
- Shift-select toggles cells. Box anchors choose two bounded cells/plane targets;
  change plane axis/index for a 3D region, inspect the count, then Apply box.
  Select creates a selection; other tools apply one atomic command to the region.
- Choose a swatch or enter a new stable local key and Apply swatch. Choose an
  opaque colour or enable a solid block colour reference (e.g. `leyforge:stone`).
  Palette changes are reversible. References copy no gameplay properties.
- Voxel Undo/Redo operate on whole commands. A new edit clears redo. Save voxel
  draft or close preserves commands and cursor. The inspector scrolls and can
  collapse using Inspector at constrained sizes.

## Drafts, source publication and runtime bake

Voxel drafts use `user://forge/voxel_assets/<namespace>/<name>.draft.json`, never
the W6.2 `user://forge/session.json`. The envelope contains initial/base/source
data, base hash or ABSENT, dependency identities, revision, commands and cursor.
Reopening replays commands before adopting state. Invalid/corrupt files remain;
Export recovery draft copies the saved bytes. Recover backup draft explicitly
selects `.bak`. Interrupted `.pending` data is exported before reopening the last
good draft. External source/dependency conflicts become read-only recovered state;
export or explicitly discard rather than silently merge.

Validate checks finished geometry and resolved references at the current revision.
Review / Publish shows identity, destination, version, occupancy, palette and
before/after source. Explicit confirmation publishes one bounded source file:
`content/voxel_assets/<namespace>/<name>.voxel.json`. New files use no-overwrite
rename; replacements retain recovery outside content. Base/dependency conflicts,
unsafe Windows paths, case collisions and reparse ancestors fail. No-op publication
preserves raw bytes and version. Changed publication advances version once.

Bake consumes published bytes separately. The deterministic `.mesh.json` bundle
is under `user://forge/voxel_assets/bakes/<bake-key>.mesh.json`, outside content
and game saves. Export bake selects an external directory, rejecting content and
owner/Forge profiles. A failed bake leaves source and previous output available.
Runtime test launches a separate process using only the LFE source reader,
compiler, bundle loader and native mesh/box resources. It includes a one-metre
reference. It does not place anything into gameplay or a saved world.

## Verification and boundaries

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_6_part_3.ps1 -FocusedOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_6_part_3.ps1
```

The full command must pass focused source/failure/picking/history tests, rendered
pointer/keyboard workflows at 1920×1080, 1280×720 and 960×540, separate rendered
LFE runtime/collision proof, and the complete W6.2 → W6.1 → W5.9 regression chain
including its original 660-second soak and Waves 0–5. A failed receipt remains
failed. Final source/runner manifests, protected inventories, logs, screenshots,
input reports, disposable source and bake fixtures identify the tested bytes.

The required W6.1 regression exposed shared-desktop pointer interference in its
GUI test helper. The failed full receipt at
`.verification/wave6/w6_1/run-20261018T142654625758400/` and focused reproductions
are retained. Instrumented input shows a foreign mouse exit between the injected
press and delayed release; the button receives down/up without pressed. The
necessary test-only change in `tests/ui/w6_1_process.gd` queues an ordinary click
pair together (as the Forge harness does), retains pointer/signal diagnostics and
the original assertions, and avoids a secondary empty recipe-list exception after
a failed open. Focused source-matched regression at
`.verification/wave6/w6_1/run-20261018T143550375719000/` passed all 14 layout/context
views plus feedback/lifecycle and rendered drop checks. No gameplay input owner,
network contract, assertion threshold or soak duration changes. This focused PASS
is not complete W6.3 certification; the full chain must still run against final source.

The editor supports only the initial 16³/32-swatch format. No resizing, textures,
smoothing, transform/rigging tools, material graphs, terrain adapters, new numeric
world voxel IDs, gameplay items, save/protocol changes or mining damage are added.
LFE owns runtime data/compile/load, Forge-ENG owns document/validation/publication,
and the existing Forge shell/viewport owns creator interaction. Full Block Forge
will integrate stable asset references with block definitions later. No duplicate
content registry or future workspace framework is introduced.

W6.3.1 Repository Alignment, Audit & Amendments is planned after full W6.3
certification **and owner acceptance**, before W6.4. The design records its future
review coverage and A/B/C/D classifications; neither checkpoint nor W6.4 starts here.
