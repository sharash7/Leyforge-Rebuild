# Wave 4 manual acceptance repair 3

Application: **0.4.3-wave4**. Starting production commit: `a203f917a0c7df5463117cbe644eb3da409509e8` (`fix: complete Wave 4 tree and crafting UX`). Repository: `D:\AI\Projects\Leyforge-Rebuild`, branch `main`. The owner request corrects the previous finite-source tree architecture. Automated certification does not grant owner manual acceptance. Wave 5 remains unstarted.

## Real voxel trees and version authority

New production worlds use worldgen version 2. Version 1 retains the exact Wave 1 base terrain: `wave_1_terrain_rules.gd` is unchanged, including hills, surface selection, dirt/stone/sand and signed-coordinate noise. Version 2 decorates that same base terrain with deterministic trees. The stored worldgen version selects generation, source initialization and restore validation. Loading or resaving v1 never upgrades it or injects v2 trees.

`LfeStarterTreeRules` owns frozen v2 decoration rules. A ten-block X/Z spatial cell has at most one candidate, derived from the seed and signed cell coordinates through the existing integer hash. One quarter of cells are skipped; the rest have deterministic 2-7-block coordinate jitter, followed by grass/slope validation. Roots sit immediately above grass; neighbouring core terrain cannot bury the lower trunk. This is temporary starter woodland density, not biome classification. The same rule continues across distant regions without a spawn-specific list or acceptance-seed coordinates.

Trunks are four, five or six Heartwood voxels. Canopies use a compact 3x3 or 5x5 footprint, three bounded height layers, a top leaf and deterministic corner omissions. Candidate spacing prevents overlapping canopy ownership. Each generation buffer considers nearby cells whose canopy may overlap it, then clips actual tree voxels to its half-open bounds. This handles signed X/Z and vertical chunk boundaries without mutable RNG, a tree cache, source-chunk ownership or generation-order dependencies. Decorations fill only base air; sparse overrides apply last.

Trees are ordinary terrain voxels, rendered by the terrain mesh and edited through the normal player path. No normal v2 tree StaticBody or `LeyforgeCreationPresenter._source()` mesh tree is created. Untouched trees are seed-derived base state, not saved individually. Mining records air relative to the versioned base; placing wood records the canonical voxel relative to base air. Both edits survive unloading and restart.

## Canonical content, mining and placement

`leyforge:oak_heartwood` moves from item-only to the single inventory-capable block definition: voxel ID 11, kind block, solid and breakable, placeable, stack limit 64, brown trunk presentation, and one self-drop. Its woodcutting rule allows manual gathering at 1 second, Wooden Axe at 1/1.5 seconds and Stone Axe at 1/3 seconds. Successful matching axe actions consume one durability; failed/no-op actions do not. Existing stacks and recipes retain the identical canonical ID and automatically gain placeability. There is no duplicate log item.

`leyforge:oak_leaves` is the new real voxel 12: solid, green, individually breakable, manual 0.25-second gathering, no inventory projection and no drop output. Leaves are opaque development art. Unsupported leaves remain until manually removed; bounded decay is deliberately deferred. Mining one log never removes a whole tree or canopy.

The rendered loop mines one generated trunk voxel, leaves its neighbour and canopy standing, creates exactly one grounded Heartwood drop, picks it up through player proximity after the existing cooldown, selects it, RMB-places exactly one voxel, then mines and recovers exactly one unit. One recovered placement is retained for streaming/save/restart proof. Placement never invokes tree generation.

## Compatibility decision

Save schema remains **3** and content compatibility remains **1**. The payload shape is unchanged. Existing canonical IDs, old numeric voxel mappings and stack schemas remain resolvable. Heartwood preserves its ID; Leaves adds a previously unused mapping. Tool instances/durability, hotbar/equipment, dropped instances, survival/timing, active kiln reservations/progress, storage, construction and voxel overrides retain their existing validation and persistence.

Stored worldgen-v1 saves retain their historical twenty-source layout, including twelve `fallen_oak` records, their identities, stock and depletion. The old fake-tree renderer is retained exclusively for that compatibility path. V2 initialization skips timber while preserving the other eight source identities/placements: four Dense Stone, two provisions and two drinking-water caches. Restore validates the appropriate layout for the stored version, preventing mixed or doubled timber systems. Historical save-schema-v1/v2 migration also retains worldgen v1 and writes save v3 only upon explicit successful save.

## Grounded drops

The logical resting centre is the nearest valid loaded support top + 0.125m half-cube + 0.05m clearance. Visual bob is +/-0.02m with the existing slow rotation; the bottom therefore hovers about 0.03-0.07m above support. Mining and selected-item drops resolve support before their normal save synchronization. The probe scans at most 64 vertical cells. If support is unavailable, the existing safe position remains and a loaded-region retry settles it later; this is bounded correction, not rigid-body physics.

Normal ticks reground at most 64 relevant drops in round-robin order, including stateful drops. Removing loaded support lets a drop settle down to the next surface. Compatible ordinary stacks move across X/Z at 0.18m/sec within 2m, reground each proposed step and merge within 0.3m subject to stack capacity and a clear path. Differences/steps above 0.2m reject attraction; items do not fly diagonally between ledges. Pair checks remain capped at 256. Grounding alters positions only; quantities, persistent identities, stateful non-merging, pickup cooldown and region materialisation remain intact.

## Verification and publication

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/development/verify_wave_4.ps1`. The shutdown-fixed runner is `D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe`, version `4.8.dev.custom_build.a9c94cd21`, SHA-256 `06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A`.

The gate runs a hash-verified snapshot of canonical working bytes in an external temporary project with isolated profiles/world IDs. It does not import into the owner's open editor project or touch owner saves. Tracked vendor files are copied unchanged; the unrelated locked editor `~libvoxel` artifact is excluded from the snapshot. At final preflight it was absent and no Godot processes remained; no agent command targeted that artifact or closed the owner's editors. Tracked vendor bytes remained unchanged. A source manifest binds tested bytes and is rechecked before certification. Original Wave 0-3 gates execute from this snapshot unchanged except focused fixtures' explicit current-version expectations. Skip switches cannot certify.

Focused coverage retains the previous crafting/inventory/processing/survival and 300-step conservation checks, and adds v1 golden voxel identities, signed base preservation, no v2 decoration in v1, seed determinism/variation, local and distant woodland density, all height variants, signed chunk-order/boundary contributions, exact one-voxel mining/drop/place/recovery, durability and sparse persistence, versioned source layouts, grounded ordinary/stateful conservation, support changes and ledge separation. V1 save-v3 compatibility includes previously depleted legacy timber and all existing Wave 4 state.

Eight rendered fresh processes cover new v2 progression, exact restarts, isolation and historical migrations. Production handlers perform the walk/chop/pickup/place/remine sequence, crafting and the remaining survival loop. Streaming preserves mined tree cells, remaining logs/canopies and placed Heartwood. Distant loaded tree voxels prove vegetation beyond spawn. A real supporting terrain block is removed beneath a merged two-unit drop; the same identity settles downward with unchanged quantity. No inventory/tool/processing state injection or survival acceleration is used. Twenty-three screenshots include woodland, partially mined tree, grounded animated drop, placed Heartwood, distant woodland and support resettling.

The complete receipt `.verification/wave4/run-20261004T035420574/gate.json` passed: **855 focused checks**, **1,682 rendered checks** across A/B/C/D/M1/N1/M2/N2, all Wave 0-3 regressions, 23 screenshots and matching source hashes. Wave 0 passed bootstrap/plugin/runner validation; Wave 1 passed 50 focused + 23 rendered checks; Wave 2 passed 84 focused + 127 rendered checks; Wave 3 passed 432 focused + 159 rendered checks. Rendered candidate survival was Standard, with acceleration false and owner acceptance `PENDING_OWNER`.

Publication stages only the repair allowlist and the application-version hunk. Unrelated `.gitignore`, project editor settings and playground scene changes are preserved exactly. The transient untracked vendor copy was left to the owner's editor lifecycle. Evidence, profiles, saves, vendor/plugin changes and temporary helpers are excluded. Full worktree/staged review, source binding, whitespace and repository integrity checks precede one normal commit/push; a subsequent fetch must show HEAD equals origin/main with 0/0 ahead/behind. Preliminary failed receipts remain append-only.

## Owner fresh-world test

Launch the rendered game with this new world ID; retain the existing development world:

```powershell
& 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.exe' --path 'D:\AI\Projects\Leyforge-Rebuild' -- --world-id=wave4-owner-v2-repair3 --seed=184552221
```

The first creation stores worldgen 2; later launches of the same ID reload it. Use LMB to mine one trunk, pick up its Heartwood, select it on the hotbar and RMB-place one block, then mine it again. Check low drop hover, several distributed trees, trees farther from spawn, F5 save/restart and individual removed logs remaining absent. I/C and Workbench crafting retain Repair 2's unified framework.

Owner manual acceptance remains pending. This repair adds no ecology, biomes, seeds, regrowth, tree physics, advanced foliage, multiplayer or Wave 5 work.
