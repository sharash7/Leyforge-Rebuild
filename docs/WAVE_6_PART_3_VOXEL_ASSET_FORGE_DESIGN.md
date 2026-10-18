# W6.3 — Voxel Asset Forge design

**OWNER RATIFIED — BOUNDED W6.3 IMPLEMENTATION AUTHORIZED 2026-10-18.**
The owner approved D1–D8 against `main` at
`3579e765a63293ea5ca28b50b22d9fa231f0995d`, including the clarifications below.
Implementation and verification status is recorded in
[the W6.3 implementation guide](WAVE_6_PART_3_IMPLEMENTATION.md).
Automated certification and owner acceptance remain separate requirements.

The following design was originally prepared as a documentation-only proposal.
Its original inspection baseline and engineering contracts are retained:
Prepared 2026-10-18 (Australia/Perth), inspecting `main` at
`d886702bac6a8ca9aec245ed08ca74371f7136c6` in
`D:\AI\Projects\Leyforge-Rebuild`. [W6.2 is owner accepted](WAVE_6_PART_2_CLOSURE.md).
The design itself did not implement runtime features. The owner now approves
the specified bounded schema, tools and runtime proof. Preserve the [Forge-first sequence](WAVE_6_PART_1_READINESS_UI_AND_INTEGRATION_FOUNDATION.md#owner-established-wave-6-sequence)
and [ownership boundaries](ARCHITECTURE_BOUNDARIES.md).

## Inspected interfaces and research

| Existing path | Current behavior and design consequence |
| --- | --- |
| [Document](../src/forge_eng/editing/content_document.gd) | `open` accepts only `content/blocks/wave_1_blocks.json`; `apply_edit` accepts only solid-block name/colour. Revisions invalidate validation. Add a separate bounded voxel document; do not weaken existing permissions or pretend arbitrary documents already work. |
| [History](../src/forge_eng/history/edit_history.gd) | Copies linear commands and maintains a redo cursor; push truncates redo. Reuse storage with voxel command application owned by the new document. |
| [Publication](../src/forge_eng/import_export/content_publication.gd) | Strict duplicate-key parser, deterministic JSON, base hash, guarded single target, draft replay, Windows atomic replace/recovery and writer mutex. Current guard and `user://forge/session.json` are catalog-specific. Voxel creation needs an explicit absent-target guard and separate draft namespace. |
| [Validation](../src/forge_eng/validation/content_validation.gd) | Runtime loaders run in a staged project; results include revision, diagnostics and references. Add asset checks with the same diagnostic shape; avoid running the complete catalog worker for each mouse motion. |
| [References](../src/forge_eng/references/content_references.gd) | Derived canonical reference locations, not a registry. Resolve material swatches through the existing catalog; no parallel gameplay material registry. |
| [Preview](../tools/forge/workspaces/preview_test/preview_viewport.gd) | Isolated SubViewport/World3D, `selection_ray`, camera state separate from revision, `show_selection` builds a padded plugin-meshed cube. Bounds/framing and LMB orbit are currently tailored to a unit cube. Add an asset input and editing input mode without breaking Content Presentation. |
| [Shell](../tools/forge/forge.gd), [presentation](../tools/forge/workspaces/block_surface/content_presentation.gd) | Explicit tabs and a split browser/editor, one catalog session. Add explicit Voxel Asset navigation and independent document status, not workspace discovery or a generic plugin bus. |
| [Block catalog](../src/lfe/content/block_catalog.gd), [library factory](../src/lfe/voxel/blocky_library_factory.gd) | Stable content/numeric world voxel IDs; factory emits cubes with unit AABB collision. No arbitrary asset loader or baked-model consumer exists. Asset cells must never become new world voxel IDs. |
| [Compatibility fingerprint](../src/lfe/networking/compatibility_manifest.gd) | Hashes every content path/raw byte except `.gitkeep`. New source under `content/` changes compatibility even if unused in terrain; backups/exports must remain outside it. |
| [Interaction bounds](../src/lfe/voxel/voxel_interaction_rules.gd), [save](../src/lfe/persistence/world_save.gd) | Unit world-cell AABBs; save/content versions 4/1. Preserve these and protocol 7, stored worldgen v1/v2 and HOST ownership. |

Primary documentation checked on 2026-10-18 supports the candidate approach:
[Godot Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html)
provides projected rays; [ArrayMesh](https://docs.godotengine.org/en/stable/tutorials/3d/procedural_geometry/arraymesh.html)
provides explicit vertex/index surfaces. These are suitable for grid picking and
integer-derived mesh buffers. This suitability is a design inference, not a fresh
engine probe. [VoxelBlockyModelMesh](https://voxel-tools.readthedocs.io/en/latest/api/VoxelBlockyModelMesh/)
documents custom models within unit-cell bounds;
[VoxelBlockyModel](https://voxel-tools.readthedocs.io/en/latest/api/VoxelBlockyModel/)
distinguishes box collision from mesh collision. A later terrain adapter is
plausible, but neither those latest docs nor W6.2's cube preview prove the
installed plugin supports every proposed custom-model behavior. No engine/plugin
upgrade or dependency is proposed. The W6.3 runtime proof below uses native mesh
buffers and explicit box collision, without depending on that future adapter.

## Owner decisions — D1–D8 approved

All eight recommendations below were explicitly approved by the owner's W6.3
implementation authorization on 2026-10-18. Alternatives remain design context.

| Decision | Recommendation | Tradeoff / alternative |
| --- | --- | --- |
| D1: dimensions | Fixed 16×16×16 editing box; 4,096 cells maximum, initially empty; no resize in W6.3 | Enough for a small stepped model; 8³ is simpler but coarse, 32³ gives detail at 8× the cells. Larger/non-cubic assets require later bounded scope. |
| D2: scale/origin | 16 fine voxels/metre, 0.0625 m per cell, lower corner origin, +Y up, front −Z | Exact binary fractions and unit-block fit. Bottom-centre pivots suit props but need a later explicit pivot/attachment contract. |
| D3: canonical schema | One strict UTF-8 JSON source per namespaced asset ID, sparse integer cells with stable palette keys, schema 1 | Readable review and one-file atomic publication; dense or binary grids are smaller but harder to inspect. No MagicaVoxel/glTF import now. |
| D4: palette/material | Up to 32 stable local swatch keys, each literal opaque colour or reference to an existing solid block's presentation colour | Useful material references without inventing material gameplay. Dedicated PBR/material assets, alpha, textures and physical properties are deferred. |
| D5: tools/history | Select, Place, Remove, Paint; single-cell brush plus bounded box application; one gesture = one command | Delivers spatial modelling and grouped undo. Flood, extrusion, symmetry, transforms and animation would widen the first workflow. |
| D6: bake/export | Deterministic versioned data bundle (`.mesh.json`) containing mesh, collision and dependency hashes; reconstruct native ArrayMesh at load | Auditable bytes without engine resource UID serialization; larger than binary `.res`. Binary/glTF output can follow demonstrated demand. |
| D7: runtime proof | Separate runtime test scene using LFE loader and published source/bake, no Forge imports; no default world placement | Proves consumption now without save/network changes. Wiring a new model into the existing terrain catalog/gameplay needs separately approved content and adapter work. |
| D8: publication | Publish canonical source as one guarded file; bake separately to an external profile/export folder and verify it against source/dependency hashes | Avoids pretending two-file replacement is atomic. Shipping prebuilt artifacts later requires a separately approved packaging contract. |

D7 is part of the recommended minimum W6.3 acceptance. If the owner wants actual
terrain replacement rather than the standalone runtime scene, revise scope and
verification before implementation; do not silently add catalog fields/content.

## First usable creator workflow

1. Home → Voxel Asset → New. Choose a unique namespaced ID and name; see empty
   16³ bounds, a one-metre ruler and active XZ construction plane at cell Y=0.
2. Place cells on that plane, then on exposed faces. Build a small stepped shape
   entirely through viewport input. Select a cell or box, remove a notch and paint
   surfaces using both a literal swatch and an existing block colour reference.
3. Drag a multi-cell stroke and apply a box operation. Undo/redo each as a group;
   undo then make another change and verify redo clears. Camera moves never count.
4. Save draft, close and reopen. Recover the same asset, palette and history/redo
   cursor. Canonical content is still untouched. See recovery/conflict state clearly.
5. Validate and preview the exact draft revision; inspect compact errors or cell
   highlights and source/material references. Review creation or before/after diff.
6. Explicitly Publish source in a disposable content root, then Bake the published
   bytes. Open Runtime Test in a separate OS process; the LFE consumer checks
   source/dependency hashes, renders the bundle and exercises box collision.

All example assets are created in isolated fixtures by tests/owner during later
implementation. This plan adds no actual content, asset files or saved drafts.

## Source, identity, coordinates and materials

Candidate canonical path: `content/voxel_assets/<namespace>/<name>.voxel.json`.
Require lowercase ASCII namespace/name (`[a-z][a-z0-9_]*` for each); identity is
`namespace:name`, must equal the path and must be unique across voxel asset
sources. Asset identity is distinct from block/item ID and world voxel number.
Reject reserved/unsafe Windows filenames, path escape, reparse-point ancestors,
case-fold collisions and unsupported fields. No rename/delete or ID allocation
into the world catalog in W6.3. Display name changes never change identity.

Illustrative schema only (one occupied cell, not a new asset):

```json
{
  "schema_version": 1,
  "id": "example:step",
  "asset_version": 1,
  "display_name": "Step study",
  "dimensions": [16, 16, 16],
  "voxels_per_metre": 16,
  "origin": [0, 0, 0],
  "palette": [
    {"key": "stone", "block_ref": "leyforge:stone"},
    {"key": "trim", "color": "#D09040FF"}
  ],
  "cells": [[0, 0, 0, "stone"]],
  "collision": "occupied_boxes"
}
```

Required fields are exactly those illustrated. `schema_version` describes the
format; `asset_version` is a positive publication revision, starting at 1 and
increasing once for a changed successful publish. Draft revision is independent.
A no-op publish preserves bytes/version. References to future asset instances
use immutable ID plus a pinned published version/hash; no instance schema is
added now. Unknown schema/artifact/compiler versions fail clearly, with no
automatic source or game-save migration. The compiler has its own version.

Cells use integer `(x,y,z)` with `0 <= axis < 16`; omitted cells are empty. No
duplicate coordinates, empty swatch sentinel or floating coordinates. Sort cells
lexicographically by `(x,y,z)`, palette by key, JSON object keys by ordinal order;
UTF-8 without BOM, two-space indentation, LF and one final newline. All numeric
schema values are integers with explicit range/type checks (booleans rejected).
Empty drafts are saveable, but publish/bake requires at least one occupied cell.

Asset-local metres are `(cell + corner_offset) / 16`, with origin at the minimum
corner and cell centres at `(cell + 0.5) / 16`. +X right, +Y up, −Z front,
right-handed axes. Box extends from `(0,0,0)` to `(1,1,1)`; selection and editing
use half-open cell bounds, while the outer maximum face is displayed for picking.
Coordinates shown to the creator are cell indices plus metres. No source-space
translation, negative cells or object transforms in this slice.

A game world block stays one metre with its existing numeric voxel identity,
collision, inventory quantity and HOST transaction. Fine cells describe internal
asset geometry only: 16 cells per edge do not produce 4,096 world blocks or
network edits. A future unit-cell block adapter can use the baked mesh; larger
decorations/creatures/structures need later placement, pivot and simulation rules.

Each palette entry has a stable local `key` and exactly one of `color` or
`block_ref`. Literal colour is `#RRGGBBAA` with alpha FF; normalize hex to uppercase.
`block_ref` resolves only an existing solid block's presentation colour through
LfeBlockCatalog. It does not copy hardness, drops, collision, recipes or authority.
Unknown/non-solid references block publish/bake. Keep reference and resolved
colour/dependency hash distinct; a changed catalog makes validation/bake stale.
Paint assigns a key to occupied cells; palette edits recolour all referencing
cells as one command. Disallow deleting in-use keys. Maximum 32 swatches is a
deliberate first-workflow bound, not a universal material-system limit.

## Picking, selection, tools and grouped history

Convert pointer position from viewport container coordinates into actual
SubViewport pixels (including stretch); project the camera ray and transform
into asset-local coordinates. Clip against editing AABB, then use integer-grid
3D DDA to find the first occupied cell and entry face. Specify X then Y then Z
tie order at edges/corners and a scale-relative epsilon; test all six faces,
parallel rays, inside origins and the maximum boundary. Picking reads source
occupancy, not an asynchronous mesh/physics result.

Place targets the empty adjacent face cell, or a chosen cell on the active
construction plane when the asset is empty/ray misses. Plane axis and index are
visible, bounded 0–15; invalid/outside targets show a red ghost and make no edit.
Remove and Paint target the hit occupied cell; Paint never creates geometry.
Place over occupied, Remove empty and Paint same key are no-ops. No operation
wraps, clamps silently or edits through the frontmost surface. Hidden interiors
can be exposed by removal or accessed with an explicitly selected plane/box.

Select click chooses the hit cell; Shift adds/removes cells. Box selection uses
two picked/plane anchors to define an inclusive integer box, with bounds/count
shown before Apply. Place fills empty cells in the box, Remove clears occupied
cells and Paint changes occupied cells only. No continuous box drag commits
until Apply. Selection is editor-only; edits may prune empty selected cells.

A brush is one cell per sampled target; traverse intervening grid cells so fast
drags have no event-rate holes. A stroke snapshots tool, swatch and initial
selection, deduplicates touched coordinates and collects sorted before/after
values. Commit once on pointer release, validate the whole transaction first,
and add one immutable history command with label and cell count. The 4,096-cell
limit bounds each command. Invalid batch rejects all cells. Empty commands add
no history. Cancel/Escape, focus loss or leaving the viewport cancels the pending
stroke; release pointer capture and keep committed content intact.

Undo/redo restores exact cell/palette state atomically, increments document
revision and invalidates validation/bake. Branching clears redo only on a new
committed edit. Palette commands use the same history boundary. Camera, selection,
panel sizes and tool changes never enter content history; publish is not an undo
command. Persist before/after commands and cursor and verify replay on recovery.

## Workflow-sized UI changes

Retain native Godot shell/navigation and Content Presentation. Add a clear Voxel
Asset entry and breadcrumb with active document. Use resizable split panels for
asset list, central viewport and palette/selection inspector; retain minimum
viewport space and allow side panels to collapse at 960×540. Persist layout only
in the Forge profile. Allow full names in the selected header and tooltip/wrapped
details; searchable list rows must distinguish otherwise truncated IDs.

Provide a dedicated compact Select/Place/Remove/Paint toolbar with swatch, box
Apply/Cancel and construction-plane controls. LMB edits/selects in asset mode;
RMB drag orbits, MMB pans, wheel zooms, F frames selection (asset if empty).
Display this asset-mode mapping; W6.2 preview retains its existing mapping.
Frame uses actual bounds, viewport aspect and camera FOV, with a safe minimum
distance/near plane for one fine cell. Offer front/top/side camera buttons and a
labelled XYZ orientation indicator. No transform gizmo or full modelling suite.

Show fine grid on the active plane, metre bounds/ruler, origin axes, hit-face
ghost and selection outline. Grid density follows zoom to avoid visual noise.
Status shows ID/name, draft dirty/saved/recovery state, publication version,
selected cell/count, tool, swatch and validation revision. Compact errors/warnings
and stale-bake badge remain visible; expandable diagnostics focus affected cells
or palette entries. Put hashes, paths, dependency references and raw details in
collapsible technical sections. These changes directly serve voxel authoring;
no major visual redesign, docking framework or new dependencies.

Text fields, menus and palette controls consume their own input. Shortcuts act
only on the focused document/viewport; text undo remains text undo. No camera or
painting during text entry, pointer capture from a modal dialog, navigation or
window focus loss. Test tool transitions and reopening alongside the catalog draft.

## Drafts, validation and publication

Use a separate candidate `user://forge/voxel_assets/<namespace>/<name>.draft.json`
under the existing external Forge profile; never reuse/convert/delete the owner's
catalog `session.json`. Envelope contains draft format version, root/path/ID,
base raw-byte hash (or explicit absent-target marker), draft revision, payload,
history and cursor. UI/camera state is optional separate profile data. Save after
each committed command, plus explicit Save/close; atomic temp/replace, last good
recovery copy and failure reporting must be proved on Windows. Do not auto-save
in-progress gestures. Reopen parses strictly, checks root/base/dependencies and
replays history before adopting state. Corrupt/unknown/conflicted files remain
available for export or explicit discard, never silent merge/overwrite.

Fast local schema/cell checks precede commands. Full Validate resolves references
and runs the LFE source reader/compiler in an isolated candidate root. Extend the
existing result with severity/code/source/ID/field and optional cell/palette key;
sort deterministically. Associate results with revision plus dependency hashes.
Errors block publication/bake, warnings require visible review. Empty asset,
duplicate cells/keys/IDs, invalid dimensions/type/scale, unknown keys/version,
unresolved references, stale base or excessive input size give actionable errors.
Cap source at 1 MiB, 4,096 cells and 32 swatches before allocating; bound decoded
bake counts separately to six quads per cell and 4,096 collision boxes.

Publish review shows destination, create/update, version, bounds, occupied and
changed-cell counts, palette/reference changes and optional expanded cell diff.
Require current successful validation and explicit creator confirmation. Guard
every ancestor/path and case collision, lock root/ID, recheck base/dependencies,
flush same-volume sibling temp, retain out-of-content recovery and atomically
replace existing source. New files require no-overwrite atomic rename after an
absent-target check. External writers remain unsupported; observed changes block
publish. On failure preserve source/draft and recover interrupted temps before
normal loading/fingerprinting. No-op does not rewrite bytes or advance version.
Do not modify the existing catalog publisher's allowlist to accept arbitrary JSON.

## Deterministic geometry, collision, bake and runtime

Recommend a small pure LFE compiler shared by Forge preview/export and runtime
source verification, not a Forge dependency in runtime. Emit only exposed faces
between occupied and empty cells; adjacent occupied cells suppress internal faces
regardless of swatch. Use flat axis normals, fixed Godot clockwise winding and
vertex colours with the existing sRGB material convention. No textures, smoothing,
AO, transparency, LOD or greedy mesh optimization initially. Iterate cells in
lexicographic order, faces −X,+X,−Y,+Y,−Z,+Z, fixed corners/triangle indices.
Positions use integer fine-grid corners divided by 16; occupied bounds remain
separate from editing bounds. This keeps data reproducible across UI/camera state.

For `occupied_boxes`, deterministically merge occupied cells into disjoint axis
boxes: visit first unclaimed cell in lexicographic order, expand +X, then +Y,
then +Z only across full unclaimed occupied slabs, mark claimed and repeat.
Ignore colour for collision. Exact union must equal occupancy; holes stay holes.
Emit integer min/size boxes, derive metre-space BoxShape3D from them. Worst case
4,096 boxes; warn above 256 and measure before accepting the performance bound.
No dynamic rigid body, automatic convex hull, terrain collider replacement or
assumption that VoxelBoxMover and native mesh collision are interchangeable.

Bake consumes published source raw bytes, resolved dependency bytes and fixed
compiler options. Candidate single-file output:
`<Forge-profile>/forge/voxel_assets/bakes/<bake-key>.mesh.json`; explicit export
may copy it to a creator-selected external directory. Reject output inside
`content/` or an owner save/draft path. A bake key hashes a length-framed tuple of
source SHA-256, ordered relative dependency paths/hashes, compiler/artifact
versions and options. Bundle embeds those values, ID/asset version, dimensions,
scale, ordered integer mesh corners/normals/indices/colours and collision boxes.
No timestamp, absolute path, UID, camera state or random ordering. Same inputs
must produce byte-identical UTF-8/LF bundles and hash. Reject unsupported versions,
NaN/noninteger/out-of-range arrays, invalid indices/counts and missing dependencies.
Only create native resources from validated data; never load scripts/scenes from
the bundle. Verify source/dependency hashes against the selected published root.

Source publish and bake are explicit separate operations, not a multi-file
transaction. A bake failure leaves published source valid, marks runtime output
unavailable/stale and keeps the previous valid bake. Flush/atomic rename the
complete bundle outside content before marking success. A draft may preview in
memory but cannot masquerade as a published bake. The canonical source is the
only authored definition; derived bundles are replaceable and never edited.

Candidate runtime proof: `scenes/testing/voxel_asset_runtime.tscn` plus
`src/game/app/voxel_asset_runtime.gd` instantiate the LFE bundle loader, render a
MeshInstance3D and create static collision boxes in a standalone test room.
Source/root/bundle are explicit arguments and must match. A labelled one-metre
reference and ray/shape collision probes demonstrate size, colour, holes and
occupied geometry in a fresh process. No Forge code, gameplay world, save,
network or automatic hot reload. Packaging for this proof includes the source,
catalog dependency and bundle in the isolated test root; normal game shipping
does not start depending on an author's external profile.

This is a real runtime consumer proposed within W6.3, not a claim that terrain
already consumes arbitrary models. Future game consumers use the same LFE reader,
validated bundle and stable ID; a unit-block adapter may populate a custom blocky
model later. Keep the old library factory's cube fallback byte/behavior-compatible
until that separate integration is approved. No existing block mappings, defaults,
content versions, save layouts, protocols or worldgen outputs change here.
New canonical source publication necessarily changes the existing content hash;
fresh peers must have identical content and old saved-world compatibility needs
explicit owner review before production distribution. Test in disposable roots;
do not weaken compatibility checks to make authoring work.

## Exact candidate implementation paths

All paths are repository-relative candidates under the inspected repository,
not files created by this plan or an approved implementation allowlist.

| Candidate path | Ownership / work |
| --- | --- |
| `content/voxel_assets/<namespace>/<name>.voxel.json` | Canonical source only after creator publication; no shipped demonstration asset requested |
| `src/lfe/content/voxel_asset.gd` | Pure bounded source parser/reference adapter and data contract |
| `src/lfe/voxel/voxel_asset_compiler.gd` | Deterministic mesh/collision data compilation shared by preview and runtime |
| `src/lfe/voxel/voxel_asset_loader.gd` | Validate bake/source/dependencies; reconstruct native resources |
| `src/forge_eng/editing/voxel_asset_document.gd` | New/create/open, cell/palette transactions, revision and selection-independent history |
| `src/forge_eng/history/edit_history.gd` | Reuse existing command storage; extend only if the concrete grouped workflow requires it |
| `src/forge_eng/validation/voxel_asset_validation.gd` | Revision/dependency-aware authoring diagnostics using LFE validators |
| `src/forge_eng/import_export/voxel_asset_publication.gd` | Separate voxel drafts, safe create/replace/recovery and bake output |
| `src/forge_eng/import_export/content_publication.gd` | Reuse strict parser/serialization helpers; extraction only if demonstrated, preserve catalog guards |
| `src/forge_eng/references/content_references.gd` | Bounded derived material-reference locations if needed; no new registry |
| `tools/forge/workspaces/voxel_asset/voxel_asset.gd` | Creator panel, tools, palette, selection and construction plane |
| `tools/forge/workspaces/voxel_asset/voxel_picking.gd` | Local-grid ray picking/box anchors |
| `tools/forge/workspaces/preview_test/preview_viewport.gd` | Asset mesh input, bounds-aware framing, separate edit/camera modes |
| `tools/forge/forge.gd`, `tools/forge/workspaces/home/home.gd`, `tools/forge/workspaces/validation/validation.gd` | Explicit navigation, active document/status, compact diagnostics and publication review |
| `scenes/testing/voxel_asset_runtime.tscn`, `src/game/app/voxel_asset_runtime.gd` | Standalone LFE runtime consumer; no main-scene/project switch |
| `tests/forge/w6_3_focused.gd`, `tests/forge/w6_3_process.gd`, `tests/forge/w6_3_runtime.gd` | Data/fault tests, graphical creator workflow and independent runtime proof |
| `tools/development/verify_wave_6_part_3.ps1`, `tools/development/w6_3_verify.py` | Proposed isolated focused/full gate; extend launcher only if required by actual new entry point |
| This design, W6.2 closure, `README.md`, `docs/development/CODEX_WORKFLOW.md` | Status/specification/acceptance evidence updates |

Before implementation inventory exact paths and required owned UID sidecars;
preserve all unrelated dirty files and receipts. New geometry/compiler capability
is justified only by this consumer. No new dependencies, engines/plugins, generic
asset registry, workspace bus or broad refactoring.

## Verification and owner-visible acceptance plan

This planning task runs static documentation/link/whitespace/scope checks only.
It does not run W6.3 tests or refresh W6.2 certification. A later approved W6.3
implementation must provide the candidate entry point:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_6_part_3.ps1
```

`-FocusedOnly` is diagnostic and uncertified. Full certification requires focused
data/fault coverage, separate graphical creator and runtime OS processes, then
the **complete W6.2 gate**, including its unchanged full W6.1/W5.9 chain and
660-second soak. Use the approved shutdown-fixed console/adjacent graphical
runner, isolated writable project/profile/content roots, short temp paths and
no owner drafts/saves. No shortened nested regression or copied historical PASS.

| Area | Required fresh proof / owner-visible example |
| --- | --- |
| Source/identity/bounds | Strict schema/duplicate keys, absent cells, all bounds, ID/path collisions, unknown versions, oversized input, dependency resolution and preserved old catalog behavior |
| Picking/tools | All six faces, edge/corner tie order, empty grid/plane, transformed viewport pixels, fast stroke gaps, no painting through front faces, invalid/outside clicks make no edits |
| Commands | Place multi-cell stroke, remove notch, paint box; one undo/redo per gesture; cancelled/no-op stroke adds nothing; branching and palette command replay match exact bytes |
| Draft/recovery | Save/close/reopen with redo cursor; corrupt/truncated history, disk/replace failure, interrupted write and external conflict retain last good data; catalog draft hash unchanged |
| Validation/UI | Empty/invalid/reference/stale errors focus cells or palette; compact summary; resizable panels, full-name access, useful framing at 1920×1080, 1280×720 and 960×540; text/modal/focus isolation |
| Geometry/collision | One-cell and asymmetric stepped fixtures; exact positions/normals/winding/colours, no internal faces; box union equals occupied cells with empty notch, bounds and worst-case measured cost |
| Publish/bake | Confirm new source vs update/version; no-op bytes preserved; reparse/path/base/dependency conflicts and crash stages; identical bundle bytes across repeated builds/processes/enumeration order; stale/corrupt bake rejected |
| Runtime | Fresh process imports no Forge classes; loads the creator-published result through LFE, correct one-metre scale/colours and collision on occupied cells with notch clear; unsupported bundle fails visibly |
| Compatibility | Existing content loaders/cube factory behavior, content fingerprint changes for authored source, mismatched peers rejected, save v4/protocol 7/worldgen v1/v2 unchanged via full regression |

Owner acceptance at the later published implementation commit should report each
workflow example actually tried: create stepped asset from empty; place/remove/
paint/ref swatches; select/box and grouped undo/redo/branch; save/reopen/recovery;
validation/conflict and publication review; runtime size/colour/collision; camera/
text focus; three viewport sizes and layout controls. Record missing observations
as missing. Automated receipts and owner acceptance remain separate requirements.

Retain append-only `.verification/wave6/w6_3/run-<timestamp>/` receipts, ordered
checks, raw logs, screenshots/input/process reports, source/runner/dependency
manifests, protected-file inventories, failure fixtures, bundle hashes and nested
regression paths. Reconcile final owned Git blobs before certification publication.
Do not certify later dirty or documentation snapshots using a historical receipt.

## Risks, dependencies and future consumers

The main risks are input/picking ambiguity at fine scale, stroke/recovery
atomicity, Windows create-versus-replace semantics, box-count/render performance,
source/dependency/bake staleness and the content fingerprint's saved-world impact.
Resolve these with focused tests before UI polish; establish measured worst-case
timings and box budgets in the implementation evidence. Latest external API docs
are research only: inspect actual runner/plugin capabilities in isolated probes
if the approved implementation needs them. Any need for new dependencies,
catalog/gameplay content, engine upgrade or migration requires a new scope decision.

Stable asset IDs, local integer cells, explicit scale and a reusable LFE loader
leave room for block/material assets, tools/equipment, decorative models, flora,
structures, creature model authoring and building/vessel designers. Those are
future consumers, not W6.3 workspaces. Rigging/animation, sockets, PBR materials,
multi-part assemblies, larger grids, functional blocks, terrain placement,
destruction, ownership, network replication and saved instances need their own
contracts. Do not prebuild their schemas or UI now.

## Owner visual and architectural clarifications

The editor must author genuine 3D pixel-art geometry: independently placed,
removed and coloured cubes, hard edges, aligned cells and visible depth. No
smoothing, bevels, subdivision or fake 2D replacement. Normal lighting is allowed.
Block-shaped detailed and small non-block-shaped examples use the same modeller
in disposable fixtures; demonstration assets must not enter production content.

The unified Forge retains four major domains: **Asset Forge**, **Entity Forge**,
**Blueprint Forge** and **World Forge**. W6.3 implements shared voxel authoring,
camera/picking, tools, palette references, history, drafts, validation, preview,
compilation, publication/recovery and LFE runtime loading where needed by this
workflow. It does not implement all future workspaces or a generic workspace bus.

Full **Block Forge remains planned and important**. Voxel Asset Forge supplies
reusable geometry; later block definitions may pin an asset ID/version/hash.
Block gameplay properties, 32×32 textures, hardness, gathering/mining, drops,
placement, collision integration and damage states remain later Block Forge work.
The pickaxe example does not prioritize Item/Tool/Equipment Forge above Block Forge.
Existing numeric world voxel IDs and the canonical block catalogue stay unchanged.

World blocks remain authoritative 1 m cubes. Initial model geometry has explicit
dimensions `[16,16,16]` and density `16` fine voxels/metre (0.0625 m per cell,
4,096 positions). Base block **textures remain 32×32 pixels**; geometry cells
are separate from surface pixels. Only opaque colour/material swatches ship in
W6.3. Larger/non-cubic dimensions, independent densities, advanced material
references and per-face textures need later scoped support; no resize UI now.

Future mining may show cracks, chipped corners, missing fragments and local fine
voxel pieces while retaining one authoritative world block. W6.3 implements no
mining damage, per-cell world saves, terrain replication or harvesting changes.
Persistent sub-block sculpting requires a separate architecture decision.

## W6.3.1 — Repository Alignment, Audit & Amendments

Planned **after W6.3 automated certification and owner acceptance**, before
W6.4 Macro World Generation. W6.4–W6.18 numbering stays unchanged. This is a
review-first checkpoint, not authorization to execute an audit or fill gaps now.

Later reconcile W6.1–W6.3 coverage, Forge-ENG, four Forge domains, full Block/
Material/Texture/Item/Tool/Equipment Forge requirements, expanded equipment
positions, canonical ownership, selected Overworld content targets, 32×32 texture
standards, fine voxel architecture, mining-damage visuals, publication/baking,
runtime consumers, multiplayer, persistence/migrations and W6.4–W6.18 dependencies.
Classify findings A (immediate prerequisite correction), B (scheduled in Wave 6),
C (justified later wave) or D (already covered/no action). Do not invent missing
canonical content selections. W6.3.1 execution and W6.4 remain unauthorized.
