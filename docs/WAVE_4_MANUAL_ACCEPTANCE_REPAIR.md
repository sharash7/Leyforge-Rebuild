# Wave 4 manual acceptance repair — 0.4.1-wave4

Owner manual acceptance is **pending**. This release repairs the owner's reported Wave 4 issues and returns a candidate for a second playtest. Automated certification cannot grant owner acceptance. Wave 5 work has not begun.

## Authority consulted

Local reference corpus: `D:\AI\Projects\leyforge\.summer\00_Docs`. These files are reference authority, not imported runtime content.

- Foundation Document 03 v1.0, **Canonical Blocks Registry Framework and Production Families**: one block identity and its inventory projection.
- Foundation Document 04 v1.0, **Canonical Items Registry, Inventory, Equipment and Production Families**: stateful item instances, inventory truth and equipment.
- Foundation Document 05 v1.0, **Canonical Crafting Recipe Registry and Transformation System**, especially primitive crafting and representative recipe rows: validated transformations/reservations and Stick terminology.
- Foundation Document 06 v1.0, **Canonical Resource Progression, Material Ecology and Capability Pathway System**: CAP-01 primitive cutting/mining capability and alternate pathways; no forced full-game tech ladder.
- Foundation Document 17 v1.0, **UI/UX, Accessibility, Menus, HUD, World Configuration and Player Trust System**: contextual world-first information and command-driven UI.
- Foundation Document 18 v1.0, **Godot/Summer Engine Technical Implementation Plan**: loaded Nodes represent relevant records; the scene tree is not the persistent database.
- Foundation Document 20 v1.0, **Buildings, Facilities, Complexes, Utilities, Services, Construction and Settlement Project System**: functional construction/services and persistent spatial ownership; full settlement/blueprint work is later.
- FCC-01C v0.2 Final Pass, under `FCC01/01_FINAL_LOCKED_CANON_A-J`: Oak Heartwood is principal structural timber and supports tools/handles; capability-based tooling is permitted.
- FCC-13B/C v0.1, **Definitive Block/Object/Item Form and Inventory Projection Registry** and **Definitive Recipe/Process/Provider and Quantity Registry**: one identity, explicit material/form and provider/quantity rules. Neither supplies an exact three-plank wooden-pickaxe recipe for this slice.
- Set 29A v0.1, **Survival, Health and Biological System Foundation**: Standard thirst off, forgiving fatigue, no routine-gathering stamina cost, environment-owned exposure.
- Set 29B v0.1, **Health, Stamina, Exertion, Fatigue and Biological Recovery**, sections 8-9, 13, 15, 17 and 23: recovery rates/delays, activity fatigue and preset scaling.
- Set 29C v0.1, **Hunger, Thirst, Nutrition and Consumption**, sections 6, 8, 18 and 26: hunger/hydration rates, grace/debt, nourishment and profile scaling.
- Set 29D v0.1, **Temperature, Wetness, Shelter, Sleep and Environmental Exposure**: neutral comfort, bounded environmental pressure and awake rest versus sleep.
- Set 29J **v0.2**, **Biological Registries, APIs, Balance Framework, Validation and Cross-System Integration**, Standard Reference Balance Baseline and preset table.
- `27-30/29-A-J/FINAL_RECONCILIATION_NOTICE_v0_2.md` plus the final v1.1 cross-set register/integration report establish that 29J v0.2 supersedes historical pending-reconciliation wording, while specialist formulas retain authority.
- Current production architecture/build-wave/coverage documents and the owner's **Wave 4 Manual Acceptance Repair Pass**. Current owner decisions override conflicting historical controls or tool assumptions.

An ignored source manifest records exact consulted paths and SHA-256 hashes. No archived POC definitions, engine binaries or vendor files were imported or replaced.

## Canon audit and disposition

| Area | Source expectation | Repair / current implementation | Representative limit or later work |
| --- | --- | --- | --- |
| Starter resources | Material provenance and discoverable capability paths | Existing finite Oak/stone sources retained, with native-scale presentation | Finite starter layout and supplied provisions are representative; full seeded ecology is Wave 6 |
| Gathering | Class/capability authorization and conserved output | LMB crosshair targeting for both terrain and physical sources; range, relevance, occlusion and completion checks | No combat/strenuous labour framework |
| Tools | Primitive mining/cutting and persistent item state | Wooden tools capability 1; Stone tools 2; ordinary Stone 1 and Dense Stone 2 | Exact wooden forms/rates are current owner-directed slice choices |
| Recipes | Canonical identities, quantities/providers, atomic transformations | Same canonical catalog, now thirteen recipes; no UI recipe shadow table | Simple representative recipes, not all generic primitive/tool assembly rules |
| Processing | Explicit fuel/input reservation; outputs once | Existing kiln runtime retained; slot UI sends transfers/start requests | One manual charcoal process; no offline work/automation |
| Construction | Canonical block inventory projections and functional state | Existing planks/rest/storage/kiln/light and voxel agreement retained | Cubes with cardinal state; complex shapes, blueprints and structural engineering deferred |
| Storage | Persistent inventories and validated transfers | Existing crate/constructed storage retained; slot movement remains authoritative | No logistics networks |
| Shelter | Environment/building provides shelter; biology consumes it | Existing bounded cover query retained; covered rest useful | Full climate/thermal/sleep simulation deferred |
| Health | Delayed eligible recovery, food primarily nourishment | 20-second delay and 0.1 health/sec in benign nourished conditions; removed instant provisions heal | Falling/safe recovery retained; no injury/medicine system |
| Survival | Standard thirst off and forgiving routine activity | Canon rates/defaults below; existing values preserved | Profile UI, sleep pressure, fatigue modifier bands and full Harsh severity are later |
| Materialisation | Persistent records independent of loaded Nodes | Sources, drops, functional objects/lights and origin crate dematerialise/rematerialise using voxel relevance | Minimal local boundary; no simulation LOD or entity database |
| Drops | Owner requests gentle animation and conserved clustering | Bob/rotation visual only; bounded attraction and state-aware merge | Placeholder cube/item art; no final art/physics pass |
| Persistence | Exact durable state and nondestructive lifecycle | Save v3/worldgen 1/content 1 retained; old v3 accepts optional timing defaults | No live/shared save fixtures altered |

No other major system was rewritten. The additional food-health bonus and mandatory sheltered healing mismatches were explicitly repaired as part of the biological audit.

## Owner-directed recipes and capability levels

Canon explicitly uses **Stick** and **Handle/Grip** terminology. Its generic primitive cutting/mining examples include Stick, a compatible hard edge and Cordage. Those are not explicit all-wood recipes; importing that entire assembly chain would reopen Wave 4 and undermine the owner's required wood-only bootstrap.

This repair adds the minimum **Oak Stick** intermediate, using the existing Oak Heartwood/Plank direction:

| Recipe | Input | Output | Authority |
| --- | --- | --- | --- |
| Saw planks | 1 Oak Heartwood | 4 Oak planks | Existing representative Wave 4 recipe |
| Split Oak Sticks | 1 Oak plank | 4 Oak Sticks | Owner-directed representative quantity; Stick terminology from Foundation 05 |
| Wooden Pickaxe / Axe / Shovel | 3 Oak planks + 2 Oak Sticks each | 1 distinct tool instance | Explicit owner-requested wooden forms; quantities are representative, not asserted as final document canon |
| Each Stone tool | 2 Oak planks + 2 Stone | 1 distinct tool instance | Existing representative recipe retained |

Wooden tools have capability 1, efficiency 1.5, durability 12. Stone tools have capability 2, efficiency 3, durability 24. Capability integers express the two-step runtime proof; they are not asserted as universal canon tier numbers. Manual timber/soft terrain -> Wooden Pickaxe -> ordinary Stone -> Stone Pickaxe -> Dense Stone -> kiln/charcoal/building is achieved from an empty inventory without granted Stone. Existing Stone tools gain the repaired capability through their canonical definition; their identities/durability remain intact.

## Interaction and presentation

LMB starts physical gathering on the highlighted terrain or source. RMB first handles highlighted kiln/storage/rest/crate interaction, then falls back to inventory-backed placement. An interactable just outside usable range consumes the attempt with a move-closer message rather than placing an unwanted block. E remains an alternate targeted interaction. Source actions do not require E.

Sources use short horizontal timber segments, small low stone clusters and sensible cache dimensions. Their persistent identity, stock, layout and coordinates are unchanged. Labels are contextual: one targeted name/action appears near the crosshair; no persistent source-name horizon labels remain.

The kiln panel presents Input, Fuel, Output, canonical requirements, progress and idle/running/blocked reason, followed by backpack and hotbar slots. Click source then destination for full-stack movement; right-click destination splits half; shift-click quick transfers. Output is withdrawal-only. Fire kiln sends an authoritative start request. There is no deposit/take debug-button workflow and no processing code in the UI.

Drops hover/bob/rotate using instance-derived phase without changing saved position. Compatible ordinary drops attract within 2m, at 0.18m/sec, through clear voxel space, and merge within 0.3m up to stack maximum. A spatial bucket pass limits pair checks to 256/tick. Those radius/speed/threshold values are owner-directed representative tuning, not claimed canon numerics. Distinct durable instances never merge. Actual movement/merge updates durable position/quantity; visual motion produces no logical save churn.

## Survival defaults and exact changes

The existing Wave 4 `hunger` and `thirst` fields represent reserve: 100 means fully fed/hydrated. Set 29 describes severity in the opposite direction. Rates below apply the same canon with that documented mapping; existing save values are not inverted or rewritten.

| Channel | Previous Wave 4 | Repair Standard | Authority |
| --- | --- | --- | --- |
| Hunger reserve loss | 0.04/sec | 4/simulation hour (4/3600 per sec; ~25 h full-to-empty) | 29C + 29J |
| Thirst | On, 0.06/sec | Disabled; stored value retained and HUD hidden | 29A/C/J |
| Routine gathering cost | 4 stamina/action | 0 | 29A/B |
| Sprint cost | 12 stamina/sec | 12/sec retained | Representative movement tuning; not asserted as a final canon number |
| Stamina regeneration | 8/sec, immediate | 16/sec; delay 1.25 sec after spend, 2.25 after depletion | 29B/J |
| Routine fatigue | +0.025/sec | 0 from routine activity | 29B |
| Sprint fatigue | Same universal rate | +0.18/min | 29B strenuous activity reference |
| Covered awake rest | -3 fatigue/sec | -0.05/min | 29B awake-rest reference; no simulated full sleep |
| Benign outdoor exposure | +0.04/sec | No growth | 29A/D environment/neutral-comfort direction |
| Legacy exposure recovery | -2/sec sheltered | -2/min sheltered | Representative retained legacy-field recovery; not a full thermal formula |
| Health recovery | +0.5/sec during covered rest, no damage delay | +0.1/sec after 20 sec without new damage, adequately nourished in the benign environment | 29B/J; shelter is not an extra requirement |
| Provisions | +30 hunger and instant +5 health | +30 hunger only | Amount remains representative; nourishment boundary from 29C |
| Water portion | +35 thirst | Same quantity when hydration enabled; no-op under Standard | Quantity representative; enablement from 29C |
| Starvation damage | 0.5 health/sec immediately at empty reserve | 6 h grace; 0.5 health/h through 24 debt h, then 1/h | 29C/J |
| Enabled dehydration damage | Same immediate loss | 2 h grace; 1 health/h through 8 debt h, then 2/h | 29C/J enabled reference |

Debt persists and decays while nourished/hydrated according to the reference rates; small food portions do not reset a debt timer. Peaceful/Relaxed hooks disable starvation health damage and hydration, and use their documented slower hunger and faster recovery parameters. Harsh hooks enable hydration (1.10x its reference rate), 1.35x hunger, 1.5x activity fatigue and its documented recovery delays/rates. Full Harsh penalty/grace customization, profile selection/settings and full biological modifiers are deliberately not claimed complete.

The explicit verification path requires `--wave4-focused` or `--wave4-playtest` **and** `--wave4-test-survival` before setting a multiplier. Focused verification opts into 3600x **biology time** and logs the multiplier/profile. Normal gameplay and all rendered manual-candidate processes use Standard at 1x. Acceleration is never saved and never multiplies workstation time.

## Compatibility and verification

Save schema remains v3, worldgen v1 and content v1. Optional `survival.timing` stores health/stamina delays plus starvation/dehydration debt; legacy six-field v3 survival loads with zero timing defaults while retaining every existing value. v1/v2 migration, previous-copy recovery, checksums, item-instance validation, workstation reservations and same-seed isolation remain covered.

The repair gate runs Wave 0-3 regressions plus extended Wave 4 focused/rendered tests. Fresh-world proof uses production LMB/RMB routes, canonical hand-crafting buttons and actual furnace slot input handlers. It records camera/player positioning and controlled damage as test setup; no inventory/process/survival state injection manufactures the rendered progression.

Eight rendered processes cover the new loop, two restarts, another world ID and v1/v2 migration/reload. Explicit streaming checks remove the physical Nodes, preserve all records, return the player/viewer, and verify exactly one relevant presentation per live identity. Drop animation is checked separately from durable movement/merge; merged quantity and final positions survive stream/save/restart.

Ignored attempt directories retain logs, focused and eight rendered JSON reports, fifteen screenshots, diff snapshots and certification/publication receipts. Skip switches cannot produce full certification. Runtime errors fail the gate even if a driver prints a passing marker.

## Second owner playtest

Use the ordinary production launch with the approved fixed runner and no verification flags. Production version is `0.4.1-wave4`. Start a new world ID for the fresh wooden-tool progression, then also load an existing Wave 4 world to check continuity.

Check native source scale; LMB timber/Stone/Dense Stone targeting; RMB kiln/storage/rest and placement priority; slot transfers/progress; drop bob/rotation/convergence; leaving and returning to regions; Standard survival pacing; save and restart. The automated candidate intentionally cannot substitute for this owner judgment.

**Wave 4 repair PASS — awaiting owner manual acceptance** is the permitted outcome only after full automated repair certification and publication. Wave 5 planning/execution remains pending the owner's personal acceptance.
