# Wave 4 - Survival & Creation

Wave 4 connects the conserved Wave 3 substrate to a small survival game:

Enter a seeded world -> gather timber -> craft planks/sticks and a Workbench -> craft wooden tools -> obtain ordinary Stone -> craft Stone tools -> harvest Dense Stone -> craft construction and a kiln -> burn charcoal -> build a covered rest/work area -> manage survival -> save -> restart -> continue the same process and resource state.

The production version is `0.4.5-wave4`. Wave 4 is otherwise owner accepted; the final hold-LMB interaction hotfix awaits its owner spot-check. Wave 5 remains outside this task. See `WAVE_4_HOLD_GATHER_INTERACTION_HOTFIX.md` for held gathering and verification, and `WAVE_4_DENSE_STONE_PRESENTATION_HOTFIX.md` for the unit-cube repair. See `WAVE_4_MANUAL_ACCEPTANCE_REPAIR_3.md` for current real-tree generation, placeability, grounded drops and version compatibility; `WAVE_4_MANUAL_ACCEPTANCE_REPAIR_2.md` retains the previous tree/crafting audit; `WAVE_4_MANUAL_ACCEPTANCE_REPAIR.md` retains the first repair and balance sources.

## Canonical content

`content/blocks/wave_1_blocks.json` is still the single block/item namespace. The five original numeric mappings and deterministic terrain rules are unchanged. The catalog now adds Oak planks, a Stone kiln, Rest mat, Storage box, Charcoal lamp and Workbench, plus Oak Heartwood, Charcoal, Trail provisions, Drinking water portions, Oak Sticks and three wooden plus three stone tools. The historical filename does not reserve a second registry: all of these are consumed through the existing catalog.

Oak Heartwood retains canonical `leyforge:oak_heartwood` for existing-save compatibility. It is now the single inventory-capable, placeable, solid, breakable block definition (voxel 11, stack 64, brown trunk presentation, self-drop one). Generated trunks, drops, inventory/hotbar and player placement all resolve this same ID. Oak Leaves is a real solid breakable voxel (12), green, with no inventory projection or harvest output. Unsupported leaves remain until individually removed in this Wave 4 foundation.

New worldgen-v2 worlds add deterministic voxel trees to the unchanged Wave 1 terrain. Ten-block spatial cells select optional jittered trees from a coordinate hash, rejecting non-grass surfaces and unsuitable slopes. Trunks vary from four to six blocks; canopy footprints vary between 3x3 and 5x5. Chunk generation considers neighbouring candidate cells and clips their contributions into each buffer before sparse overrides. Trees use the normal voxel mesh, targeting and editing path; untouched trees require no saved source records.

`content/world_objects/wave_4_sources.json` retains legacy `fallen_oak` definitions and the original v1 twenty-source layout for compatibility. New v2 worlds create only eight finite sources: four dense-stone outcrops and two each of provision and drinking-water caches. They create no timber sources. Existing v1 worlds retain twelve historical finite timber sources and their six-unit stock/depletion; their cube-tree presentation is legacy compatibility only. Supplied food/water caches remain representative stock, without a wild-food ecology system.

## Gathering and tools

Hold LMB on highlighted terrain or a finite physical source for its required duration. The authority accumulates work only while the primary action remains active and the same valid target stays targeted. Release resets immediately; retargeting, range/occlusion/unloading, changed block/source/tool/capability, death or a menu cancel without output or wear. Completion revalidates, performs one operation, clears work and discards excess time. Continued hold may start the next target from zero on a later input step. Routine gathering has zero Standard stamina cost. Terrain gathering produces physical conserved drops; source gathering delivers its exact finite stock into inventory, and fails without depletion if the complete output cannot fit.

Each breakable block has a harvest rule: class, minimum capability, seconds and an array of canonical outputs/quantities. Breaking and output production are separate seams. The resource conversion supports same-content, transformed, multiple and explicitly empty output arrays. The shipped terrain rules preserve the original one-block output for Grass, Dirt, Stone and Sand. Each Heartwood voxel yields exactly one Heartwood; leaves yield nothing. One trunk break leaves all other logs and canopy voxels untouched. Placing Heartwood consumes one inventory unit and places one voxel; re-mining it returns one unit.

Wooden pickaxe, axe and shovel have mining, woodcutting and digging classes, capability 1, efficiency 1.5 and durability 12. Stone tools retain durability 24 and efficiency 3, with capability 2. Ordinary Stone requires mining 1; Dense Stone requires mining 2. Bare hands can gather starter timber and soft terrain, but cannot bypass the mining progression. These representative wooden tool recipes and balance choices are owner-directed, not asserted as final quantities from the source canon.

Successful matching tool actions cost one durability; failed/no-op actions cost none. Zero durability makes the tool unable to supply its class/capability/efficiency; manually eligible resources can still use the explicit manual fallback. There is no repair, combat damage, quality, affix or equipment-protection system.

Ordinary stacks remain canonical `content` plus bounded integer `quantity`. Tools add a 128-bit `instance` and integer `durability`, always with quantity 1. Inventory/equipment/storage movement, drops, pickup and restore preserve those fields. Save validation rejects duplicate instance identities across all endpoints, including workstation inventories.

## Recipes and exact transformations

`content/recipes/wave_4_recipes.json` contains fourteen canonical recipes. Recipe data drives both grid matching and transactions; the UI contains no matching table. Ingredients use exact canonical IDs. All recipes are known by default, with a compact hint instead of a recipe-book system.

| Recipe | Exact inputs | Exact outputs | Context / form |
| --- | --- | --- | --- |
| Saw planks | 1 Oak Heartwood | 4 Oak planks | Personal 2x2, shapeless |
| Split Oak Sticks | 1 Oak plank | 4 Oak Sticks | Personal 2x2, shapeless |
| Build Workbench | 4 Oak planks | 1 Workbench | Personal 2x2, full square |
| Wooden pickaxe / axe | 3 Oak planks + 2 Oak Sticks | 1 corresponding tool instance | Workbench 3x3, shaped |
| Wooden shovel | 1 Oak plank + 2 Oak Sticks | 1 shovel instance | Workbench 3x3, shaped |
| Stone pickaxe / axe | 3 Stone + 2 Oak Sticks | 1 corresponding tool instance | Workbench 3x3, shaped |
| Stone shovel | 1 Stone + 2 Oak Sticks | 1 shovel instance | Workbench 3x3, shaped |
| Build kiln | 6 Stone + 2 Oak planks | 1 Stone kiln | Workbench 3x3, shaped |
| Weave rest mat | 2 Oak planks | 1 Rest mat | Personal 2x2, adjacent horizontal cells |
| Build storage box | 4 Oak planks | 1 Storage box | Workbench 3x3, four corners |
| Craft lamp | 1 Oak plank + 1 Charcoal | 1 Charcoal lamp | Personal 2x2, shapeless |
| Charcoal burn | 2 Oak Heartwood + 1 Oak Heartwood fuel | 2 Charcoal | Kiln, 8 simulation seconds |

Tool silhouettes use H for working-head material (plank or Stone) and S for Oak Stick. Rows are `HHH / _S_ / _S_` for pickaxes, `HH / HS / _S` for axes, and `H / S / S` for shovels. Blank cells matter; translated patterns and explicitly allowed mirrored axes match. Kiln rows are `SSS / S_S / PSP` (S = Stone, P = plank); storage rows are `P_P / ___ / P_P`. Personal recipes also work at a Workbench; Workbench recipes never work in the personal grid. Quantities are representative owner-directed tuning, not claimed as locked final recipes. Shovel and Stone tool quantities change from the first repair to fit their actual silhouettes.

Four or nine actual inventory staging slots hold moved ingredients. Taking the preview output re-matches the canonical recipe, validates the requested identity and output capacity, consumes exact quantities in detached grid/destination inventories, then publishes both together. Failure changes neither endpoint; previewing creates no material or tool instance. Shapeless matching requires every occupied cell to participate. Shaped matching rejects extra materials or wrong arrangements. The legacy recipe-ID transaction cannot bypass grid recipes.

Closing attempts to return all staged items to player inventory atomically. If everything cannot fit, the menu and all staging remain accessible, with a capacity message; no partial return, deletion or overflow occurs. Invalidated Workbench context disables crafting and attempts the same safe close. Save and save-and-quit first require successful close, so transient staging cannot be omitted from a save.

## Workstations and time

Place a crafted kiln and target it with the crosshair. RMB opens its slot panel; E remains an alternate. Select a backpack or hotbar stack, then click an input or fuel slot to transfer it; right-click transfers half, and Shift-click makes a quick transfer. The process panel displays canonical requirements, missing resources and progress. Start the displayed process with Fire; withdraw completed output through the output slots. Input, fuel and output containers have 3, 1 and 3 slots. Invalid inputs/fuel, blocked start output, an active process and an invalid recipe reject without consumption.

At start, exact inputs become the active process reservation, and the exact fuel is transformed into its authorized work. The canonical active recipe and progress represent that reservation. Processing advances through the same validated simulation-time seam used by normal physics ticking, independent of render frame counts. Completion creates the exact outputs once. If output becomes blocked after start, progress is capped at completion and the reservation remains until space is available. Nothing is deleted and no second completion is awarded.

A save records the active recipe and progress. Restart resumes stored progress. The runtime awards no wall-clock offline production. This is one manually operated kiln, not an automation/industrial scheduling system.

## Building, shelter and storage

Placement continues to use the existing inventory-to-voxel transaction and validates empty editable space, range and player-body overlap. Failed placement consumes nothing. Functional construction also creates a persistent world-object identity attached to its authoritative voxel cell. Workbench, kiln, storage, rest and light state are validated against sparse voxel overrides in both directions.

Functional objects record a bounded cardinal orientation (0-3). Current cube geometry is symmetric; this establishes durable orientation data without a shape/directional-art programme.

A crafted Storage box has nine persistent slots and uses the same transfer transactions as inventory. The historical origin crate remains available for Wave 3 compatibility. Workbench stores only its normal persistent object identity/cell/orientation, with no persistent crafting inventory; its empty recovery returns one Workbench. Filled storage, nonempty stations and active processes cannot be broken; empty functional construction follows its declared one-object recovery drop rule. This prevents destruction from silently deleting contents or active reservations.

The lamp creates a real local warm light. A rest mat permits rest when nearby and sufficiently enclosed. Shelter requires overhead solid cover within four cells and solid cover on at least three cardinal sides within three cells. The query uses bounded authoritative voxel samples and is cached for half a second. It does not scan the world, simulate structural integrity or implement weather/climate.

## Survival and capability progression

The authoritative survival state retains six finite bounded values in 0-100: health, stamina, hunger reserve, thirst reserve, fatigue and legacy exposure. Standard defaults follow final Set 29B/C references, with the existing reserve convention (100 means fed/hydrated).

- Standard hunger reserve declines by 4 per simulation hour; thirst is disabled and its HUD is hidden. Existing saved thirst values are retained.
- Routine gathering/walking has no stamina cost. Sprint retains the representative 12/sec cost. Standard regeneration is 16/sec after 1.25 seconds following spending or 2.25 seconds following depletion.
- Routine activity generates no fatigue. Sprint accumulates 0.18/min; covered awake rest removes 0.05/min. Full sleep pressure and physiological modifier bands remain later work.
- Benign outdoor conditions produce no exposure growth. Existing exposure can recover in shelter at the representative legacy rate of 2/min; this is not a full thermal/weather model.
- Natural health recovery is 0.1/sec after 20 simulation seconds without new damage, while adequately nourished in the current benign environment. Cover is not a mandatory healing tax.
- Provisions restore up to 30 hunger reserve, without an instant health bonus. Drinking portions restore up to 35 thirst only when hydration is enabled. No-op consumption removes nothing.
- Starvation uses persistent debt: first 6 hours at zero reserve cause no direct damage; subsequent loss is 0.5 health/hour until 24 debt hours, then 1/hour. Enabled dehydration has 2-hour grace, then 1/hour through 8 hours and 2/hour later. Peaceful/Relaxed disable starvation damage.
- Falling and zero-health safe recovery remain; inventory, tool identities, drops and world state are retained.

The same parameter model exposes Peaceful, Relaxed and Harsh recovery/rate hooks for focused verification. It is not a complete world-settings/profile UI. Production uses Standard; verification's opt-in 3600x biology multiplier is guarded by explicit test flags, logged, never serialized and never applied to the rendered manual candidate or workstation time.

Progression is capability driven: manual timber -> personal planks/sticks/Workbench -> Workbench wooden tools -> ordinary Stone -> Stone tools -> Dense Stone -> kiln/charcoal -> light and a persistent enclosed work/rest area. There is no new level, perk, research or tech-tree framework.

## Persistence and migration

Save schema remains `save_version = 3` and `content_version = 1`. Newly created worlds store `worldgen_version = 2`; existing worlds retain stored version 1 even after resaving. Terrain generation and source-layout validation bind to that stored version. Content compatibility remains 1 because existing IDs and numeric mappings remain resolvable, Heartwood keeps its ID, and Leaves adds a new unused numeric mapping without a save-shape change. The checksum envelope, pending-file validation, previous-copy recovery, external-change detection and world-ID isolation remain active.

The payload keeps all Wave 2 player/voxel state and Wave 3 resources. Its new `creation` section records survival, constructed object identities/cells/orientation, storage slots, workstation input/fuel/output/active recipe/progress, source identities/depletion/layout and accumulated simulation time. Tool instances/durability stay with their stacks in the existing resources section. Optional `survival.timing` stores recovery delays and starvation/dehydration debt. Original six-field v3 survival objects load with zero timing defaults without changing their values. Transient targeting, unfinished gathering, rest intent, cached shelter and node references are not serialized. Crafting staging is returned before saving; Workbench does not add persistent container fields. Existing v3 worlds retain timber IDs, depletion, tool instances/durability, active kiln reservations and all previous state without a version migration.

v1 loads with safe Wave 3 and Wave 4 defaults. v2 retains all historical resources/hotbar/equipment/drop/storage state and receives safe Wave 4 defaults. Migration happens in memory. Only a successful explicit save writes v3, retaining the old file as the previous copy. Fixtures use legitimate historical field sets, including ordinary two-field v2 stacks and no resource section in v1.

Malformed durability, duplicate identities, unknown recipe/content, illegal progress, negative/out-of-range/nonfinite survival values, inconsistent source layout, duplicate object cells and mismatched functional voxels reject safely. Current simulation state affects the dirty/save indicator.

## Controls and interface

Existing movement, look, jumping, hotbar and inventory controls remain:

- WASD move; Shift sprint; Space jump; mouse look.
- Hold LMB — gather/mine; release cancels and resets timed terrain/source gathering; RMB interacts with a highlighted functional object or otherwise places selected inventory content.
- 1-9 / wheel select hotbar; I opens the unified backpack/hotbar/equipment interface with a 2x2 personal crafting grid.
- RMB opens/interacts with highlighted Workbench/kiln/storage/rest/crate targets. Interaction takes priority over placement; E is an alternate targeted interaction.
- C opens the same Inventory interface with its crafting section highlighted. F consumes the selected food/drink.
- Workbench RMB opens that same shell with a 3x3 grid. Crafting and kiln/storage panels use source/destination slots, half-stack splitting and shift-click quick transfers; they include player inventory and hotbar.
- RMB on a covered rest mat begins rest; movement ends it.
- Q drops one selected unit; Shift-Q drops the stack. Escape closes panels/releases the mouse.
- F5 saves; F10 saves and quits. Window close retains the controlled save path.

The HUD shows health, stamina, food and fatigue, with hydration only in enabled profiles. A single crosshair label shows the targeted name/action; source names are not placed across the horizon. Inventory tool labels show current/max durability. This is functional development UI, with placeholder materials and no final art pass.

## Ownership and Forge

Reusable instances, harvesting evaluation, recipes/transformations, survival values, persistent construction state and workstation timing live under `src/lfe/`. The existing world/player authority and the new presenters/panels under `src/game/` own Leyforge orchestration and presentation. Canonical definitions stay under `content/`; fixtures/drivers stay under `tests/`.

No Forge or Forge-ENG implementation was added. Fourteen recipes and a representative source/tool catalog did not establish authoring friction that warranted a new tool. Runtime schema/reference validation already checks the actual canonical definitions. Reserved workspaces remain untouched.

## Verification and evidence

Run from the production repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_4.ps1
```

The approved runner is `D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe` (`4.8.dev.custom_build.a9c94cd21`). Production compatibility target remains Godot 4.7.2-stable; exact stable-executable qualification is separate. No intentional 4.8-only API is used.

The gate copies hash-verified canonical working files into an isolated external temporary project and uses isolated profiles and disposable worlds. This avoids imports or native-library copy operations touching the owner's open editor project. Untracked vendor artifacts are excluded; tracked vendor files are copied unchanged. Source hashes are checked again before certification. It stores distinct attempt receipts under ignored `.verification/wave4/run-<UTC timestamp>/`. Focused tests cover tool classes/capability/wear, exact instance movement, multiple/empty harvest outputs, atomic craft capacity, processing fuel/reservations/blocked completion/time partitioning, survival, malformed state, recovery, historical migration and 300 deterministic transformation-accounting steps with seed 928143.

Eight rendered processes prove A: the full new survival loop with active processing at save; B: exact restoration and continued tool/process/craft/build work; C: a second exact restart; D: independent state for another world ID with the same seed; M1/N1 and M2/N2: legitimate historical v1/v2 migration and current-format fresh-process reload. Streaming checks explicitly confirm source terrain becomes uneditable, then rebuilds the same construction and preserves all resource/object state. Reports account for materials in inventories, drops, constructed voxels, station containers and active reservations, including explicit fuel and consumable transformations.

The rendered driver uses production commands and UI handlers. It does not inject inventories, tools, survival or processing snapshots to manufacture the loop. Camera/player positioning and controlled environmental damage are identified test setup; fixed simulation durations use the production timing seam. Normal play advances that same seam through physics time. Twenty-six screenshots accompany machine-readable reports, including generated voxel woodland near spawn and in a distant region, a partially mined tree with a grounded drop, one placed Heartwood voxel, support-removal resettling, a close highlighted Dense Stone unit cube, held voxel/source release and menu cancellation, full personal 2x2 crafting, 3x3 Workbench crafting, processing/completion and drop motion before/after. Prior Wave 0-3 gates run before a full certification receipt is green. Skip switches produce a partial verification receipt, never full certification.

Historical regression assertions now compare against the current save version and expanded catalog while retaining the original deterministic terrain, resource conservation, transaction and restart checks. Their standalone item fixture extends production content instead of replacing it. Wave 3's rendered driver holds the actual primary input and checks its refreshed target after actual harvest completion. Additional focused tests use a streamed production world to prove quick taps, partial release, full completion, target/tool changes, continuous hold and menu cancellation for voxels and finite sources, plus death, range, occlusion, chunk unloading and stale block/source/capability rejection.

## Intentional limits and next boundary

This wave includes real generated starter trees plus finite dense-stone and supply sources, supplied provision/water caches, one manually fuelled process, cube construction, bounded cover detection, local simulation and representative tools/recipes. Resource respawn, full survival profile/settings UI, sleep pressure/physiological modifiers, full flora/biomes, cooking/farming/liquid containers, offline production, repair, doors/shapes, structure strength, temperature/wetness/weather, diseases/injuries, combat, NPCs, settlements, automation and final UI/Forge are later work.

The single-world JSON/sparse state approach remains bounded development infrastructure rather than a large-world entity database. Tool durability cannot be repaired. All persistent sources remain world scoped. These are intentional Wave 4 limits, not silent substitutions for its implemented foundation.

Wave 5 host/join, RPCs, replication, prediction and server implementation have not been introduced. Harvest, durability, craft, process, place, consume, damage and storage commands remain separable from presentation for that future authority layer.

## Physical presentation lifetime and drops

The voxel runtime's `is_area_editable` region query gates source, drop, functional-light/object and origin-crate materialisation. Unloading removes Nodes; persistent records survive. Returning rebuilds exactly one relevant presentation per live identity. There is no far simulation or new entity database.

Generated v2 trees render through the normal voxel terrain mesh and need no tree StaticBody/source presenter. Legacy v1 timber sources retain their upright cube presentation and original stock/positions/identities. Dense Stone finite sources now use exactly one grid-aligned 1m cube, one matching unit collision box and matching highlight bounds. Provision/water caches retain their dimensions. Crosshair source queries still reject terrain occlusion.

Drop logical centres settle at support top + 0.125m half-height + 0.05m clearance. The visual bob is +/-0.02m with slow rotation, leaving cube-bottom clearance about 0.03-0.07m. Spawn grounding uses a bounded loaded-voxel query; missing support is retried as terrain becomes available. A round-robin correction also resettles existing and stateful drops after support changes. Quantity, identity, cooldown and persistence rules are preserved.

Compatible ordinary stacks attract horizontally through clear local voxel space within 2m at 0.18m/sec, merge within 0.3m up to stack maximum, and persist the grounded resulting positions. Movement is regrounded; a height difference or step above 0.2m prevents attraction, avoiding flight between ledges. Stateful instances never merge. A spatial bucket pass limits pair checks to 256 per tick. Rendered conservation tests advance this authority seam explicitly; normal physics advances it continuously.
