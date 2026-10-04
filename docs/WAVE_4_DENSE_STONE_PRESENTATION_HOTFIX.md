# Wave 4 final Dense Stone presentation hotfix

Application: **0.4.4-wave4**. Starting commit: `2e619452bab804780648fffc4f4e24c2c4c11d62`. Production repository: `D:\AI\Projects\Leyforge-Rebuild`, branch `main`. The owner reports Wave 4 accepted except for this final presentation defect. This task does not begin Wave 5.

## Presentation repair

`LeyforgeCreationPresenter._source()` now constructs Dense Stone from exactly one visible `BoxMesh` of `Vector3.ONE`. It is centred at `(0, 0.5, 0)` relative to the existing source body, whose stored X/Z centre and floored Y remain unchanged. The lower corner therefore sits on the terrain surface at integer voxel coordinates, and the upper corner is exactly one metre away in each axis. The previous two differently sized meshes and oversized combined bounds are removed. The original source colour is retained.

The existing common collision construction now receives `Vector3.ONE` and the same centre, creating exactly one unit `BoxShape3D`. Highlight centre/size metadata use those identical values; the normal crosshair highlight matches the cube. There are no additional sub-meshes, scale multipliers or overlapping pieces.

## Source and compatibility semantics

`dense_stone` remains the same finite representative outcrop source, producing six ordinary `leyforge:stone` units on depletion, requiring mining capability 2 and retaining its existing 1.5-second base work duration. Its catalog, source identities, layout, positions, remaining stock, depletion, tool durability, conservation and save/restore code are unchanged. No Dense Stone item/block identity or geological deposit generation is added.

Only the application version increments from 0.4.3 to 0.4.4-wave4. Save version remains 3, content compatibility remains 1, and worldgen remains 2 for new worlds / stored 1 for existing v1 worlds. No world migration is required. Both v1 and v2 source layouts use the corrected presentation.

## Verification and publication

The focused fixture constructs actual production presenters for all four Dense Stone sources in both worldgen layouts. It asserts one mesh and one collision only, exact unit geometry, common centre, unscaled dimensions, matching highlight metadata, terrain/grid alignment, unchanged source identity and unchanged authoritative state. All previous source/depletion, crafting, conservation, trees, drops, survival and persistence tests remain active.

The rendered loop retains its capability-gated Dense Stone harvesting and durability checks. A dedicated close view targets an undepleted outcrop through the real crosshair, verifies actual mesh/collision dimensions and actual visible highlight bounds, and captures `23_dense_stone_unit_cube.png`. The presentation inspection leaves resources and source state unchanged. The remaining loop, streaming, fresh-process restarts, world isolation and historical migrations still run.

The full gate uses the approved shutdown-fixed Godot console runner with an isolated external project/profile/worlds, hash-bound to the working source. Rendered timing remains Standard without survival acceleration or state injection. Evidence is retained locally under ignored `.verification/wave4/run-<UTC>/` and excluded from publication.

Full receipt: `.verification/wave4/run-20261004T095522999/gate.json`. **907 focused checks** and **1,688 rendered checks** passed across all eight fresh processes, with 24 screenshots and matching source hashes. Wave 0 bootstrap/plugin/runner validation passed; Wave 1 passed 50 focused + 23 rendered; Wave 2 passed 84 focused + 127 rendered; Wave 3 passed 432 focused + 159 rendered. Existing checks were retained. The approved runner fingerprint is `06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A`. Owner spot-check remains pending.

Publication uses an explicit eight-path allowlist, stages only the application-version hunk in `project.godot`, preserves the unrelated `.gitignore`, project editor settings and playground scene changes exactly, and excludes evidence/saves/vendor changes. After diff/whitespace/integrity review and one normal commit/push, fetch verifies local `main` equals `origin/main` with 0/0 ahead/behind.

## Owner spot-check

Use a separate fresh world ID so all four finite outcrops are available without changing the existing development save:

```powershell
& 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.exe' --path 'D:\AI\Projects\Leyforge-Rebuild' -- --world-id=wave4-dense-stone-spotcheck --seed=184552221
```

From spawn, look near X/Z `(4,10)`, `(7,10)`, `(10,10)` or `(13,10)`; outcrops sit directly above local terrain. Each should appear as one normal grey voxel cube, with a crosshair outline matching its faces. The label remains “Dense stone outcrop”. Bare hands / Wooden Pickaxe cannot meet its mining-2 requirement; use the normal Stone Pickaxe progression if checking depletion. Existing non-depleted sources in saved worlds also receive the new presentation.

The hotfix is ready for the owner's visual spot-check once certified. Wave 5 has not begun.
