# Wave 4 - Survival & Creation

Wave 4 connects the conserved Wave 3 substrate to a small survival game:

Enter a seeded world -> gather timber -> craft wooden tools -> obtain ordinary Stone -> craft Stone tools -> harvest Dense Stone -> craft construction and a kiln -> burn charcoal -> build a covered rest/work area -> manage survival -> save -> restart -> continue the same process and resource state.

The production version is `0.4.1-wave4`. Automated certification is separate from owner manual acceptance. The repair candidate awaits a second owner playtest; Wave 5 is not authorized. See `WAVE_4_MANUAL_ACCEPTANCE_REPAIR.md` for the canon audit, repaired interaction contract and exact balance sources.

## Canonical content

`content/blocks/wave_1_blocks.json` is still the single block/item namespace. The five original numeric mappings and deterministic terrain rules are unchanged. The catalog now adds Oak planks, a Stone kiln, Rest mat, Storage box and Charcoal lamp, plus Oak Heartwood, Charcoal, Trail provisions, Drinking water portions, Oak Sticks and three wooden plus three stone tools. The historical filename does not reserve a second registry: all of these are consumed through the existing catalog.

Oak Heartwood uses the existing historical material name from FCC-01C, rather than importing its full timber portfolio. Provisions and drinking-water portions are representative supplied stock. This wave does not claim a complete food, liquid-container, plant or resource catalogue.

`content/world_objects/wave_4_sources.json` defines twenty finite, persistent starter resource sites: twelve fallen Oak Heartwood sources, four dense-stone outcrops and two each of provisions and drinking-water caches. Each source has an exact remaining quantity, class, capability and action duration. The bounded source layout uses the stored seed and existing terrain heights; it does not replace the terrain generator or alter its voxel output. Depletion persists per world ID. Sites do not regenerate or duplicate on stream-out/restart. Supplied food/water caches deliberately avoid pretending that a generic berry is complete biome-aware wild-food ecology.

## Gathering and tools

LMB on highlighted terrain or a finite physical source starts timed gathering. Authoritative completion checks streamed/ranged state, current source targeting, the original tool instance, health and remaining material before publishing resources. Routine gathering has zero Standard stamina cost. Terrain gathering produces physical conserved drops; source gathering delivers its exact finite stock into inventory, and fails without depletion if the complete output cannot fit.

Each breakable block has a harvest rule: class, minimum capability, seconds and an array of canonical outputs/quantities. Breaking and output production are separate seams. The resource conversion supports same-content, transformed, multiple and explicitly empty output arrays. The shipped terrain rules preserve the original one-block output for Grass, Dirt, Stone and Sand.

Wooden pickaxe, axe and shovel have mining, woodcutting and digging classes, capability 1, efficiency 1.5 and durability 12. Stone tools retain durability 24 and efficiency 3, with capability 2. Ordinary Stone requires mining 1; Dense Stone requires mining 2. Bare hands can gather starter timber and soft terrain, but cannot bypass the mining progression. These representative wooden tool recipes and balance choices are owner-directed, not asserted as final quantities from the source canon.

Successful matching tool actions cost one durability; failed/no-op actions cost none. Zero durability makes the tool unable to supply its class/capability/efficiency; manually eligible resources can still use the explicit manual fallback. There is no repair, combat damage, quality, affix or equipment-protection system.

Ordinary stacks remain canonical `content` plus bounded integer `quantity`. Tools add a 128-bit `instance` and integer `durability`, always with quantity 1. Inventory/equipment/storage movement, drops, pickup and restore preserve those fields. Save validation rejects duplicate instance identities across all endpoints, including workstation inventories.

## Recipes and exact transformations

`content/recipes/wave_4_recipes.json` contains thirteen canonical recipes. The UI reads the same data as transactions; there is no separate Forge or presentation recipe table. Ingredients match exact canonical IDs, and all recipes are known by default.

| Recipe | Exact inputs | Exact outputs | Context |
| --- | --- | --- | --- |
| Saw planks | 1 Oak Heartwood | 4 Oak planks | Hand |
| Split Oak Sticks | 1 Oak plank | 4 Oak Sticks | Hand |
| Each wooden tool | 3 Oak planks + 2 Oak Sticks | 1 wooden tool instance | Hand |
| Stone pickaxe | 2 Oak planks + 2 Stone | 1 pickaxe instance | Hand |
| Stone axe | 2 Oak planks + 2 Stone | 1 axe instance | Hand |
| Stone shovel | 2 Oak planks + 2 Stone | 1 shovel instance | Hand |
| Build kiln | 6 Stone + 2 Oak planks | 1 Stone kiln | Hand |
| Weave rest mat | 2 Oak planks | 1 Rest mat | Hand |
| Build storage box | 4 Oak planks | 1 Storage box | Hand |
| Craft lamp | 1 Oak plank + 1 Charcoal | 1 Charcoal lamp | Hand |
| Charcoal burn | 2 Oak Heartwood + 1 Oak Heartwood fuel | 2 Charcoal | Kiln, 8 simulation seconds |

Crafting prepares a detached inventory, checks ingredients and the post-consumption output capacity, and publishes only after the whole transformation validates. Unknown recipe, wrong context, missing inputs and insufficient output space leave the original inventory untouched. No partial craft or overflow deletion occurs.

## Workstations and time

Place a crafted kiln and target it with the crosshair. RMB opens its slot panel; E remains an alternate. Select a backpack or hotbar stack, then click an input or fuel slot to transfer it; right-click transfers half, and Shift-click makes a quick transfer. The process panel displays canonical requirements, missing resources and progress. Start the displayed process with Fire; withdraw completed output through the output slots. Input, fuel and output containers have 3, 1 and 3 slots. Invalid inputs/fuel, blocked start output, an active process and an invalid recipe reject without consumption.

At start, exact inputs become the active process reservation, and the exact fuel is transformed into its authorized work. The canonical active recipe and progress represent that reservation. Processing advances through the same validated simulation-time seam used by normal physics ticking, independent of render frame counts. Completion creates the exact outputs once. If output becomes blocked after start, progress is capped at completion and the reservation remains until space is available. Nothing is deleted and no second completion is awarded.

A save records the active recipe and progress. Restart resumes stored progress. The runtime awards no wall-clock offline production. This is one manually operated kiln, not an automation/industrial scheduling system.

## Building, shelter and storage

Placement continues to use the existing inventory-to-voxel transaction and validates empty editable space, range and player-body overlap. Failed placement consumes nothing. Functional construction also creates a persistent world-object identity attached to its authoritative voxel cell. Kiln, storage, rest and light state are validated against sparse voxel overrides in both directions.

Functional objects record a bounded cardinal orientation (0-3). Current cube geometry is symmetric; this establishes durable orientation data without a shape/directional-art programme.

A crafted Storage box has nine persistent slots and uses the same transfer transactions as inventory. The historical origin crate remains available for Wave 3 compatibility. Filled storage, nonempty stations and active processes cannot be broken; empty functional construction follows its declared one-object recovery drop rule. This prevents destruction from silently deleting contents or active reservations.

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

Progression is capability driven: manual timber -> wooden tools -> ordinary Stone -> Stone tools -> Dense Stone -> kiln/charcoal -> light and a persistent enclosed work/rest area. There is no new level, perk, research or tech-tree framework.

## Persistence and migration

Save schema is now `save_version = 3`; `worldgen_version = 1` and `content_version = 1` remain unchanged. The checksum envelope, pending-file validation, previous-copy recovery, external-change detection and world-ID isolation remain active.

The payload keeps all Wave 2 player/voxel state and Wave 3 resources. Its new `creation` section records survival, constructed object identities/cells/orientation, storage slots, workstation input/fuel/output/active recipe/progress, source identities/depletion/layout and accumulated simulation time. Tool instances/durability stay with their stacks in the existing resources section. Optional `survival.timing` stores recovery delays and starvation/dehydration debt. Original six-field v3 survival objects load with zero timing defaults without changing their values. Transient targeting, unfinished gathering, rest intent, cached shelter and node references are not serialized.

v1 loads with safe Wave 3 and Wave 4 defaults. v2 retains all historical resources/hotbar/equipment/drop/storage state and receives safe Wave 4 defaults. Migration happens in memory. Only a successful explicit save writes v3, retaining the old file as the previous copy. Fixtures use legitimate historical field sets, including ordinary two-field v2 stacks and no resource section in v1.

Malformed durability, duplicate identities, unknown recipe/content, illegal progress, negative/out-of-range/nonfinite survival values, inconsistent source layout, duplicate object cells and mismatched functional voxels reject safely. Current simulation state affects the dirty/save indicator.

## Controls and interface

Existing movement, look, jumping, hotbar and inventory controls remain:

- WASD move; Shift sprint; Space jump; mouse look.
- LMB starts timed terrain/source gathering; RMB interacts with a highlighted functional object or otherwise places selected inventory content.
- 1-9 / wheel select hotbar; I opens the existing inventory/equipment interface.
- RMB opens/interacts with highlighted kiln/storage/rest/crate targets. Interaction takes priority over placement; E is an alternate targeted interaction.
- C opens canonical hand recipes. F consumes the selected food/drink.
- Kiln/storage panels use source/destination slots, half-stack splitting and shift-click quick transfers; they include player inventory and hotbar.
- RMB on a covered rest mat begins rest; movement ends it.
- Q drops one selected unit; Shift-Q drops the stack. Escape closes panels/releases the mouse.
- F5 saves; F10 saves and quits. Window close retains the controlled save path.

The HUD shows health, stamina, food and fatigue, with hydration only in enabled profiles. A single crosshair label shows the targeted name/action; source names are not placed across the horizon. Inventory tool labels show current/max durability. This is functional development UI, with placeholder materials and no final art pass.

## Ownership and Forge

Reusable instances, harvesting evaluation, recipes/transformations, survival values, persistent construction state and workstation timing live under `src/lfe/`. The existing world/player authority and the new presenters/panels under `src/game/` own Leyforge orchestration and presentation. Canonical definitions stay under `content/`; fixtures/drivers stay under `tests/`.

No Forge or Forge-ENG implementation was added. Thirteen recipes and a representative source/tool catalog did not establish authoring friction that warranted a new tool. Runtime schema/reference validation already checks the actual canonical definitions. Reserved workspaces remain untouched.

## Verification and evidence

Run from the production repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_4.ps1
```

The approved runner is `D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe` (`4.8.dev.custom_build.a9c94cd21`). Production compatibility target remains Godot 4.7.2-stable; exact stable-executable qualification is separate. No intentional 4.8-only API is used.

The gate uses isolated profiles and disposable worlds outside the repository. It stores distinct attempt receipts under ignored `.verification/wave4/run-<UTC timestamp>/`. Focused tests cover tool classes/capability/wear, exact instance movement, multiple/empty harvest outputs, atomic craft capacity, processing fuel/reservations/blocked completion/time partitioning, survival, malformed state, recovery, historical migration and 300 deterministic transformation-accounting steps with seed 928143.

Eight rendered processes prove A: the full new survival loop with active processing at save; B: exact restoration and continued tool/process/craft/build work; C: a second exact restart; D: independent state for another world ID with the same seed; M1/N1 and M2/N2: legitimate historical v1/v2 migration and current-format fresh-process reload. Streaming checks explicitly confirm source terrain becomes uneditable, then rebuilds the same construction and preserves all resource/object state. Reports account for materials in inventories, drops, constructed voxels, station containers and active reservations, including explicit fuel and consumable transformations.

The rendered driver uses production commands and UI handlers. It does not inject inventories, tools, survival or processing snapshots to manufacture the loop. Camera/player positioning and controlled environmental damage are identified test setup; fixed simulation durations use the production timing seam. Normal play advances that same seam through physics time. Fifteen screenshots accompany machine-readable reports, including natural source scale, slot-based processing/completion and drop motion before/after. Prior Wave 0-3 gates run before a full certification receipt is green. Skip switches produce a partial verification receipt, never full certification.

Historical regression assertions now compare against the current save version and expanded catalog while retaining the original deterministic terrain, resource conservation, transaction and restart checks. Their standalone item fixture extends production content instead of replacing it. Wave 3's rendered driver waits for actual harvest completion.

## Intentional limits and next boundary

This wave includes a finite starter resource slice, supplied provision/water caches, one manually fuelled process, cube construction, bounded cover detection, local simulation and representative tools/recipes. Resource respawn, full survival profile/settings UI, sleep pressure/physiological modifiers, full flora/biomes, cooking/farming/liquid containers, offline production, repair, doors/shapes, structure strength, temperature/wetness/weather, diseases/injuries, combat, NPCs, settlements, automation and final UI/Forge are later work.

The single-world JSON/sparse state approach remains bounded development infrastructure rather than a large-world entity database. Tool durability cannot be repaired. All persistent sources remain world scoped. These are intentional Wave 4 limits, not silent substitutions for its implemented foundation.

Wave 5 host/join, RPCs, replication, prediction and server implementation have not been introduced. Harvest, durability, craft, process, place, consume, damage and storage commands remain separable from presentation for that future authority layer.

## Physical presentation lifetime and drops

The voxel runtime's `is_area_editable` region query gates source, drop, functional-light/object and origin-crate materialisation. Unloading removes Nodes; persistent records survive. Returning rebuilds exactly one relevant presentation per live identity. There is no far simulation or new entity database.

Sources use terrain-aligned short timber segments, small stone clusters and sensible cache dimensions. Crosshair collision queries resolve the nearest visible source and reject terrain occlusion. Source stock/positions/identities are unchanged for existing saves.

Drops visually hover, bob and rotate with instance-derived phase without modifying logical positions. Compatible ordinary stacks attract through clear local voxel space within 2m at 0.18m/sec, merge within 0.3m up to stack maximum, and persist actual resulting positions. Stateful instances never merge. A spatial bucket pass limits pair checks to 256 per tick. Rendered conservation tests advance this authority seam explicitly; normal physics advances it continuously.
