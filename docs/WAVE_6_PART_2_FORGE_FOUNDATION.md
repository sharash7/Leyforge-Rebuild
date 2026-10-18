# W6.2 — Forge-ENG & Unified Forge Foundation

**PROPOSED SPECIFICATION — awaiting owner approval.** Prepared 2026-10-18
(Australia/Perth) against `main` at `16d6ccd2da86a0f71d2929e18caa373c0206d48b`.
This task authorizes documentation and publication only. No W6.2 implementation
or verification harness is authorized or created by this document.

[W6.1 is owner accepted](WAVE_6_PART_1_CLOSURE.md). Preserve the owner-established
[Forge-first W6.2–W6.18 sequence](WAVE_6_PART_1_READINESS_UI_AND_INTEGRATION_FOUNDATION.md#owner-established-wave-6-sequence)
and [architecture boundaries](ARCHITECTURE_BOUNDARIES.md).

## Inspected foundations and bounded need

| Existing owner / format | Finding and consequence |
| --- | --- |
| [Block catalog](../src/lfe/content/block_catalog.gd), [canonical blocks/items](../content/blocks/wave_1_blocks.json) | Schema 1, namespaced content IDs, stable numeric voxel mappings; blocks and item-only definitions already share one catalog. Reuse `load_from_path`, `content_definition`, voxel lookup and existing validation. No new registry. |
| [Recipe catalog](../src/lfe/content/recipe_catalog.gd), [recipes](../content/recipes/wave_4_recipes.json) | Schema 1 includes hand/Workbench/Kiln, references, quantities, fuel and shaped/shapeless grids. `load_path(path, catalog)` validates against a supplied catalog; recipe authoring is excluded. |
| [Crate](../content/world_objects/wave_3_crate.json), [sources](../content/world_objects/wave_4_sources.json) | Existing world-resource/creation owners load these definitions. Inspect them for inbound references and regression validation; do not invent a generic entity registry or editor for them. |
| [Voxel library factory](../src/lfe/voxel/blocky_library_factory.gd) | Builds solid cubes/empty models from catalog IDs/colours and supplies the runtime material. Real 3D preview should exercise this factory and the installed voxel plugin. Arbitrary authored geometry is absent. |
| [Compatibility manifest](../src/lfe/networking/compatibility_manifest.gd) | Fingerprints sorted relative content paths plus raw file bytes, excluding only `.gitkeep`. Even formatting changes alter admission compatibility. Drafts/backups must stay outside `content/`. |
| [Forge-ENG](../src/forge_eng/), [Forge workspace skeleton](../tools/forge/workspaces/) | Only `.gitkeep` reservations, including Home, voxel asset, validation and preview/test. There is no working shell, history service, 3D editor or shared authoring format to extend. Reserved families are not a checklist to implement. |

The first production pain is changing an existing block's presentation safely:
today this requires hand-editing a shared JSON file without an authoring preview,
draft history or publish conflict check. W6.2 addresses that one workflow. It
does not claim to complete Block Surface Forge or Voxel Asset Forge.

## First usable creator workflow

Launch a separate Forge scene in the existing Godot project, without starting
the playground, HOST/JOIN sessions, world generation or save loading. Home shows
the selected repository root, canonical content path and validation state. An
explicit built-in navigation list opens **Content Presentation**, **Validation**
and **3D Preview** in one application. Other reserved workspaces remain labelled
future coverage, with no empty functioning editor claims or plugin discovery.

1. Browse/search existing canonical block IDs, choose `leyforge:stone`, inspect
   its immutable ID/voxel ID and referenced definition. Item-only entries are
   read-only; air/non-solid entries are labelled and not editable in this slice.
2. Edit only the existing solid block's `display_name` and `color` through a
   labelled text field and colour picker. The picker updates an interactive 3D
   preview immediately after draft validation. No JSON editing is required.
3. Undo/redo, switch views, save a local draft, close and reopen it. Dirty state
   and draft/canonical identity remain visible. Discard requires an explicit UI
   choice when it would lose edits; navigation never silently publishes.
4. Validate and inspect a field/path-specific error list and before/after diff.
   Publish explicitly to the one existing canonical catalog only when clean,
   conflict-free and valid. Reopen it with the runtime catalog and show success.
5. Start a fresh isolated game using that published candidate and verify the
   name/colour are consumed. Content publication never hot-reloads a running
   game, changes a live HOST or writes a game save.

This is a single-document session: one catalog draft and one canonical target.
Selecting another block preserves that draft/history. Undo/redo covers edit
commands, not filesystem publication; reverting a publication requires another
reviewed publish. No new canonical content ships merely to demonstrate the tool.

## Shared editing, validation and publication contract

Forge-ENG owns a small document session: canonical relative path, immutable base
raw-byte SHA-256, parsed full document, draft revision, dirty state and linear
command history. Commands carry target canonical ID, field, before/after values;
reject unknown IDs, unsupported fields and invalid types without partial edits.
One committed colour gesture is one undo step; a new edit after undo clears redo.
Navigation and camera movement do not enter content history. Preserve all
uneditable fields and array order, and reject duplicate JSON keys on load rather
than accepting a lossy parse. IDs and numeric voxel mappings cannot be renamed,
deleted or reassigned; no automatically allocated IDs in W6.2.

Reuse existing runtime loaders on a disposable staged content tree using their
path-taking entry points. Forge-only checks cover edit permissions, strict
`#RRGGBBAA` colour syntax, nonempty names, paths and draft/publication state.
Do not reimplement runtime domain validation. A derived, discardable reference
view resolves canonical IDs using the existing catalogs and inspects known recipe,
drop/harvest, crate and source references; it stores locations, not definitions.
Unknown schema versions and malformed/unknown references block publication.
Where an existing owner has a fixed input path, run its unchanged loader in the
isolated candidate project. No LFE refactor is presumed necessary for this slice.

Draft files are local authoring artifacts under a Forge-specific `user://`
profile outside the checkout/content tree, with a versioned envelope containing
target, base hash and draft payload. They are not game saves or runtime inputs.
Require a matching base when resuming; report conflicts and allow export/discard,
never silently merge. Do not execute scripts or import arbitrary scenes from a
draft. Persist only data; unknown draft versions fail safely. Export here means
recovering a draft file, not a content-pack framework.

Publish is a single-file operation: reject target path escape, symlink/junction
escape, read-only target, changed base bytes or unsupported schema. Validate the
complete staged candidate and allowed-field diff, show the destination/diff, then
require the creator's explicit Publish action. Serialize predictably (UTF-8, LF,
fixed indentation and key ordering, original array order); do not rewrite on open
or no-op publish. Same base plus same commands produces identical output bytes,
validation ordering and existing runtime fingerprint regardless of UI/camera state.

Write and flush a sibling temporary file on the same volume; replace atomically
with an out-of-content recovery copy retained before success is reported. Temp
files must be removed after success/failure so the fingerprint cannot include them.
On failure, preserve original canonical bytes and the draft; never delete the
original first. Recheck the base immediately before replace. Initially require
exclusive authoring access during publish, use a bounded application lock to
prevent concurrent Forge writers, and reject observed external edits. Arbitrary
external writers cannot be made transactional by this lock; concurrent external
editing is unsupported. Fault-injection tests must prove these failure outcomes
on Windows before this workflow is accepted. No multi-file transaction manager.

## Real 3D viewport and W6.3 seam

Use native Godot `Control` UI with `SubViewportContainer`/`SubViewport`, isolated
`World3D`, `Node3D` preview root, camera, lighting and grid/axes. The standalone
scene uses the existing installed engine/plugin; no new engine, web renderer,
editor plugin framework or third-party dependency. Reuse the runtime blocky
library factory and material to render the selected solid voxel in a tiny
disposable voxel volume. Prove the installed plugin's meshing path with a
focused rendered spike inside the later implementation task before building UI
around it; a painted cube mockup cannot substitute for runtime-compatible preview.

Orbit, pan, bounded zoom and Frame Selection operate only when the viewport has
focus. Text entry/scrolling must not move the camera; exiting the viewport releases
capture. Resize must retain usable controls at 1920×1080, 1280×720 and 960×540.
Expose selected canonical ID and unit bounds. Camera/grid state is editor-only,
never canonical data. Release old preview nodes/resources on selection changes
and close; no world/player/network nodes, physics simulation or game save state.

W6.2 implements only the following seam as needed by this preview; avoid a generic
workspace bus or tools framework. W6.3 must approve any extensions before use:

| Interface | W6.2 obligation / W6.3 dependency |
| --- | --- |
| Document session | `open(relative_path)`, `apply_edit(id, field, value)`, `undo`, `redo`, `validate`, `save_draft`, `publish`; results include success/reason and draft revision. W6.3 adds bounded voxel-cell commands after ratifying its asset schema. |
| Validation result | Stable ordered diagnostics with severity, code, source path, canonical ID and field location; revision identifies the validated draft. Stale results cannot enable publish. W6.3 adds geometry/material diagnostics through this result shape. |
| Preview input | Validated revision, canonical ID and disposable runtime catalog; return preview root plus local bounds and selection identity. Refresh replaces only preview content, preserving camera. W6.3 supplies its asset preview using the same viewport lifecycle. |
| Input/selection | Viewport supplies local ray and selected identity; W6.2 selection is the whole block. W6.3 defines ray-to-cell picking, coordinate convention, paint/erase tools, gizmos and grouped commands. |
| Publication | Explicit validation/diff/base-hash gate to canonical target. W6.3 must define asset source/runtime output ownership, stable IDs, deterministic bake and atomic output strategy before extending beyond one file. |

W6.3 is blocked on accepted W6.2 session/history/viewport/publication evidence and
an owner-approved asset format design: grid dimensions and bounds, axis/origin,
voxel scale, palette/material references, empty cells, collision/mesh semantics,
stable asset references, schema/version and migration behavior, source versus
derived artifact paths, deterministic compiler and runtime consumer. The current
cube catalog cannot encode arbitrary geometry; do not add unused fields or build
an asset compiler now. Real spatial editing belongs in W6.3; W6.2 supplies a real
interactive visual preview and the editing/history boundary it will extend.

## Intended implementation ownership and exclusions

The following is the exact proposed implementation allowlist, requiring owner
specification approval and a fresh baseline/protected-file inventory first.
Generated UID sidecars may accompany only these new Godot resources when required;
inventory them explicitly at publication. A need for other paths requires scope review.

| Intended files | Owner / purpose |
| --- | --- |
| `src/forge_eng/editing/content_document.gd` | One document, allowed commands and draft revision |
| `src/forge_eng/history/edit_history.gd` | Linear undo/redo for that document |
| `src/forge_eng/validation/content_validation.gd` | Runtime-loader adapter and authoring diagnostics |
| `src/forge_eng/references/content_references.gd` | Derived known-reference locations, no registry |
| `src/forge_eng/import_export/content_publication.gd` | Draft I/O, deterministic serialization, conflict-safe single-file publish |
| `tools/forge/forge.tscn`, `tools/forge/forge.gd` | Standalone application and explicit navigation |
| `tools/forge/workspaces/home/home.gd` | Project/path/status view |
| `tools/forge/workspaces/block_surface/content_presentation.gd` | Bounded existing-block name/colour editor |
| `tools/forge/workspaces/validation/validation.gd` | Navigable diagnostics/diff/publish view |
| `tools/forge/workspaces/preview_test/preview_viewport.gd` | Real rendered viewport, camera/input and runtime preview adapter |
| `tests/forge/w6_2_focused.gd`, `tests/forge/w6_2_process.gd` | Data/failure tests and real graphical creator-input checks |
| `tools/development/verify_wave_6_part_2.ps1`, `tools/development/w6_2_verify.py`, `tools/development/run_forge.ps1` | Future isolated gate and standalone Forge launcher |
| This specification, `README.md`, `docs/development/CODEX_WORKFLOW.md` | Implementation/evidence/status updates only |

No changes to `src/lfe/`, `src/game/`, `project.godot`, existing scenes, addons,
save/network/worldgen versions, canonical schemas or checked-in content are planned.
Tests publish only into disposable copies. LFE keeps runtime validation/rendering;
Forge-ENG coordinates authoring; Forge owns creator UI; game runtime consumes
canonical published definitions on normal startup. No runtime dependency on Forge.

Exclude W6.3 voxel tools, new content/IDs, recipe editing, terrain/world editors,
complete Forge workspaces, generic schema language, plugins, AI, import pipelines,
asset baking, packaging, collaboration, simulation, save/network/engine changes,
hot reload and speculative frameworks. Protected local files and old receipts stay
untouched. The existing dirty crate is not a W6.2 input to publish without approval.

## Acceptance, verification and implementation gate

Required future entry point (proposed; **does not exist yet**):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_6_part_2.ps1
```

`-FocusedOnly` may run development diagnostics but must report uncertified. The
full gate must use the approved shutdown-fixed console runner and adjacent
graphical runner, isolated writable project/profile and short TEMP/TMP roots.
Never import the live checkout or open owner saves. No harness is built in this task.

| Acceptance example | Focused / owner-visible proof required |
| --- | --- |
| Home → select Stone → edit name/colour → 3D Preview → Validation | Real pointer/keyboard input, visible draft marker, orbit/pan/zoom/frame and colour response; controls reachable at all three sizes; screenshots and process logs |
| Two colour edits, undo, redo, undo then different name | Exact document restoration, redo cleared, no camera/navigation in history; draft survives view switch/restart and remains outside content |
| Malformed JSON, duplicate keys/IDs, unknown reference/schema, invalid colour/name | Ordered actionable diagnostics, failed edit leaves document intact, publication disabled; runtime loaders exercised, no canonical bytes changed |
| External file change, stale validation revision, escaped target, failed replace | Conflict/failure shown, original bytes and recoverable draft preserved; fault-injection coverage includes pre-replace crash and restart recovery |
| Valid publish in isolated project | Only intended fields differ, IDs/mappings/other fields conserved; repeat build bytes/hash deterministic; no-op is byte-identical; fresh runtime loads and renders changed name/colour |
| Close/reopen, repeated selection/resize/input focus | No stale preview/resources or captured input; read-only item/non-solid handling clear; owner completes normal flow without JSON edits |

Final certification requires full focused data/failure tests plus separate real
graphical Forge process input coverage, then the **complete existing W6.1 gate**
against the same candidate. W6.1 includes W5.9 with its full 660-second soak and
Waves 0–5 chain, Repair 1 drop behavior, HOST/JOIN reconnect, content mismatch,
save/recovery and v1/v2 determinism. Keep its source projection and instrumentation
rules intact; copied old PASS receipts cannot certify new Forge files. Inventory
all new Forge source/tests/launchers in the W6.2 manifest and reconcile final Git
blobs before publication. Do not shorten, skip or weaken regressions.

Retain append-only `.verification/wave6/w6_2/run-<timestamp>/` gate, source and
runner manifests, raw logs, ordered checks/failures, screenshots, input/process
reports, draft/recovery fixtures and publish before/after hashes. Record nested
regression paths and results, exit status, focused/full distinction, final
source-match result and certified commit. Automated PASS and owner acceptance
are separate. Owner tests the first workflow, navigation/focus, three layouts,
draft recovery, undo/redo, conflict/error feedback and 3D controls at the published
commit; record only supplied observations. Both are needed to close W6.2 and
consider W6.3 authorization. WAN stays deferred to Wave 17.

Main implementation risks are existing-loader diagnostics being coarse, plugin
preview meshing/resource lifecycle, byte-sensitive compatibility and Windows
replacement/conflict handling. Resolve these with focused proofs inside the
approved boundaries; if a runtime/schema or multi-file change becomes necessary,
stop that portion for owner scope approval. This plan awaits approval; no W6.2
implementation has begun.
