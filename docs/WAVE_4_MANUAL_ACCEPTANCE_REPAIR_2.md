# Wave 4 manual acceptance repair 2

Application: **0.4.2-wave4**. Starting production commit: `55d03b0f10aed493922ae3cda0c2f059e7ec5f76`. This is the focused owner-requested tree and unified crafting repair. Automated certification does not grant owner manual acceptance. Wave 5 remains unstarted.

## Authority and canonical decisions

The owner repair request controls the production direction: upright voxel-style trees, personal 2x2 crafting inside Inventory, and a placed Workbench opening the same framework with a 3x3 grid. The relevant local design sources were read before implementation:

- Foundation 03, Canonical Blocks Registry Framework and Production Families v1.0: one canonical material definition with world/inventory projections.
- Foundation 05, Canonical Crafting Recipe Registry and Transformation System v1.0: shaped/shapeless transformation data and distinct hand/station contexts; Workbench is the project term.
- Foundation 17, UI/UX, Accessibility, Menus, HUD, World Configuration and Player Trust v1.0: coherent contextual commands and resource visibility.
- Locked FCC-13B, Definitive Block/Object/Item Form and Inventory Projection Registry v0.1, lines 120-150: merge the historical Oak Log block/item identities and Oak Planks/Plank identities, rather than duplicate the same physical thing.
- Historical POC Manual Testing Guide v0.1, lines 26 and 39-40 and the tool examples around line 635: 2x2/3x3 shaped/shapeless crafting and Workbench progression. Historical controls are reference evidence; current owner controls take precedence.

Sources live in `D:\AI\Projects\leyforge\.summer\00_Docs`. Exact source paths and SHA-256 hashes are retained in ignored `.verification/wave4-repair2/canon-sources.json`. No POC implementation was imported. These references establish identities, contexts and shape support; this repair does not assert that its exact quantities or tree geometry are locked final canon.

**Timber remains `leyforge:oak_heartwood`.** The existing canonical definition gains oak-log world visual metadata for the trunk and canopy colors. This preserves current inventories, recipes, kiln inputs and saved source records. It does not create separate Oak Log block/item/Heartwood definitions. Leaves are visual foliage in this bounded slice, have no inventory identity or output, and are removed with the tree.

**Workbench is one canonical placeable block/item**, `leyforge:workbench`, voxel ID 10. It uses existing inventory-backed placement and functional-object persistence. The original voxel mappings and deterministic terrain generator are unchanged.

## Trees and gathering

The twelve timber sources retain their existing deterministic identities, positions, `fallen_oak` source-kind key and six-unit stock. Only their normal presentation changes. Each loaded tree has terrain-aligned 1m log cubes and 1m canopy cubes. Its persistent identity selects one of three deterministic height/canopy variants: two, three or four trunk cubes, with a bounded leaf shape variation.

LMB targets the physical trunk and uses the previous timed gathering authority. An incomplete action awards nothing. Manual chopping takes 1 second; a Wooden Axe takes 1 / 1.5 seconds; a Stone Axe takes 1 / 3 seconds. Correct successful axe actions retain the previous one-durability cost. Gather completion gives the same six timber units once, subject to complete inventory capacity. Full depletion removes the entire trunk and canopy; no floating foliage remains.

The previous region-relevance fix controls materialisation. Unloading removes physical nodes while source/depletion records remain authoritative. Return or restart reconstructs each live source once, with the same identity-derived shape; depleted trees remain absent. This is a voxel-built finite source presentation, not a new generated-voxel forest, ecology or regrowth system.

## One inventory framework

I opens Inventory with backpack, nine-slot hotbar, equipment, a 2x2 staging grid and output. C opens that same interface and highlights its crafting section. RMB on a placed Workbench opens the same framework with a 3x3 staging grid. Kiln and storage contexts share the player inventory/hotbar/equipment framework and existing slot interaction language. The old independent recipe-list crafting screen is removed from the production path; the remaining creation panel owns only HUD/context information.

Click a source slot then a destination; right-click splits half and Shift-click performs quick transfers. The grid slots hold actual conserved resources. The output button represents the currently matched recipe and cannot store player items. Taking it re-validates the canonical match, exact consumption and destination capacity, prepares detached states and commits both endpoints atomically. Preview creates no resource or instance. Stale selection, invalid shape/context, extra inputs and blocked output leave resources unchanged.

Recipe grid metadata extends canonical recipe schema 1. Six-field legacy authoring remains readable; production grid recipes cannot use the old recipe-ID transaction to bypass staging. Matching lives in LFE, not UI. Shaped patterns permit translation, require exact blank cells and consume one unit per symbol. Mirroring is explicit for axes. Shapeless recipes require all occupied cells to participate, preserving excess stack units after exact consumption.

## Representative recipes and progression

Four planks in a full 2x2 square produce one Workbench. This is the owner's representative recipe. Personal transformations retain 1 timber -> 4 planks, 1 plank -> 4 sticks, and 1 plank + 1 Charcoal -> 1 lamp, all shapeless. A Rest mat uses two planks in adjacent horizontal cells. Making it shaped removes ambiguity with the one-plank Stick transformation.

Tools require Workbench 3x3. H is plank for wooden heads or Stone for Stone heads; S is Oak Stick; underscore means empty:

| Tool | Pattern rows | Exact materials |
| --- | --- | --- |
| Pickaxe | HHH / _S_ / _S_ | 3 head units + 2 sticks |
| Axe | HH / HS / _S | 3 head units + 2 sticks; horizontal mirror allowed |
| Shovel | H / S / S | 1 head unit + 2 sticks |

Wooden pickaxe/axe retain their prior 3-plank + 2-stick cost. Wooden shovel changes from 3 planks to 1. Each previous Stone tool recipe used 2 planks + 2 Stone; Stone pickaxe/axe now use 3 Stone + 2 sticks, and Stone shovel uses 1 Stone + 2 sticks. The pattern and quantity data agree exactly.

The kiln moves to Workbench with rows SSS / S_S / PSP, where S is Stone and P is plank (unchanged 6 Stone + 2 planks). Storage moves to Workbench with four corner planks (unchanged 4 planks). Charcoal processing remains 2 timber + 1 timber fuel -> 2 Charcoal in 8 simulation seconds, preserving existing active-process records. There are fourteen canonical recipes; no duplicate presentation recipe table or recipe-book system was added.

Fresh progression is tree -> timber -> planks/sticks -> personal Workbench -> placed Workbench -> Wooden Pickaxe -> ordinary Stone -> Stone Pickaxe -> Dense Stone -> kiln/building. Wood tools require no Stone. Rendered verification gathers all needed timber and mines real terrain Stone without inventory/tool injection.

## Staging, breaking and save compatibility

Crafting grids are session staging, not Workbench-owned persistent inventories. Closing attempts to return all staged items atomically. If everything cannot fit, all staging remains in the visible, accessible menu and closing fails with a capacity message. No partial return, silent deletion or overflow is permitted. A lost/out-of-range/unloaded Workbench context disables crafting and attempts the same safe close; if blocked, the staging stays accessible so the player can free slots and move it back.

Saving first requires successful menu closure. F10 and controlled window-close saving do not quit after a failed save. Consequently transient staging cannot disappear across a successful save/restart. Preview outputs cannot be saved or duplicated. The Workbench stores its ordinary four-field object identity/content/cell/orientation and follows normal empty functional-object recovery, returning one Workbench on a valid break.

Save version remains 3; worldgen and content versions remain 1. Existing v3 inventories, tool instances/durability, storage, construction, survival values/timing, kiln reservations/progress, source depletion and drops remain compatible. Historical v1/v2 migration is retained. Standard survival rates, recovery rules, contextual RMB priority, drop motion/merge and previous stream relevance behavior are retained from repair 1.

## Verification and handoff

Run `powershell -NoProfile -ExecutionPolicy Bypass -File tools/development/verify_wave_4.ps1` with the approved shutdown-fixed Godot console runner. The gate uses isolated profiles/worlds and retains distinct append-only attempt directories under ignored `.verification/wave4/run-<UTC>/`. Full certification requires Wave 0, 1, 2, 3, Wave 4 focused and all eight Wave 4 rendered fresh-process phases; skip options cannot certify the build.

Focused checks include shaped/shapeless matching, 2x2/3x3 context restrictions, mirror/translation, malformed pattern quantities/context, stale preview, exact tool output, close/output capacity rollback, Workbench persistence/recovery, old v3 state and retained 300-step deterministic accounting. Rendered checks use production player/UI handlers for I/C, actual grid transfers, output taking, Workbench crafting/placement/RMB, wrong personal tool patterns and staged-item return, then continue through tool progression, kiln, construction, survival, streaming, restart, isolation and v1/v2 migration. All rendered phases use Standard production survival timing without the opt-in biology acceleration.

The complete 2026-10-04 gate `.verification/wave4/run-20261004T021257283/gate.json` passed and certified the candidate: 647 focused checks, 1,023 rendered checks across A/B/C/D/M1/N1/M2/N2, and all Wave 0-3 regressions. Approved runner fingerprint: `06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A`.

Eighteen screenshots include `15_personal_grid.png`, `16_workbench_grid.png` and `17_tree_variation.png`, alongside the previous gathering, furnace, survival, save/restart, migration and drop-motion evidence. Failed preliminary attempts are retained; only a complete successful gate receipt authorizes publication. The continuation fixture uses a free cell for its additional plank because its previous target is now occupied by the fresh-session Workbench.

Publication is one reviewed commit with only repair-owned files and the application-version hunk. Unrelated `.gitignore`, project editor settings and playground scene changes remain unstaged. Evidence, saves and vendor/plugin changes are excluded. After normal push, a fresh fetch must show HEAD equals origin/main with 0/0 ahead/behind.

Owner manual acceptance remains pending. Trees use development materials; Workbench uses the current cube construction style. No full foliage resource system, forest generation, recipe discovery, multiplayer or Wave 5 work is included.
