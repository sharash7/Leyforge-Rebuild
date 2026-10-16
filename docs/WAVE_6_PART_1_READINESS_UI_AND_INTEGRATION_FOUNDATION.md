# W6.1 — Readiness, UI & Integration Foundation

**Proposed implementation specification, 2026-10-16. No implementation in this task.**
Reviewed at `c14406f6143b9e03bb3906cd4c7f159a36afbaea` with pre-existing local
changes preserved. [Wave 5 is closed for owner-authorized LAN-first progression](WAVE_5_CLOSURE.md),
with incomplete manual traceability and historical certification limits recorded.
The owner approves Wave 6 progression; a subsequent bounded task must authorize
implementing this proposal. Candidate choices below are not owner-approved canon.

Authority: [build waves](SHOWCASE_BUILD_WAVES.md), [master coverage](SHOWCASE_MASTER_COVERAGE.md),
[architecture boundaries](ARCHITECTURE_BOUNDARIES.md) and
[readiness handoff](WAVE_5_TO_WAVE_6_READINESS_HANDOFF.md). Historical stage
documents explain implementation history; current owners/signatures take priority
over obsolete path/version/status descriptions in those documents.

## Existing foundation and actual gaps

| Area | Existing implementation inspected | Gap / W6.1 disposition |
| --- | --- | --- |
| UI/inventory | [Inventory panel](../src/game/ui/inventory_panel.gd): one shell for personal 2×2 / Workbench 3×3 crafting, storage, Kiln, equipment and Manual; split/swap/quick transfer, selected-source highlight and tool text | Fixed pixel positions/minimum size, clipped text and transient feedback justify bounded layout/readability work; preserve commands and conservation |
| Personal state | [Player resources](../src/lfe/entities/player_resource_state.gd): 27 slots, first nine are hotbar, separate selected index; restricted equipment `hand`, `body` | No complete armour/accessory/attachment model; specify future contract, retain two-slot runtime/save layout |
| Content | [Block catalog](../src/lfe/content/block_catalog.gd) loads blocks and item-only definitions from [one canonical file](../content/blocks/wave_1_blocks.json); [recipe catalog](../src/lfe/content/recipe_catalog.gd), source definitions and crate definition already validate their domains | No need for another item registry. Equipment validation explicitly allows only `hand`/`body`; future expansion must change existing consumers coherently |
| Terrain | [Generator](../src/lfe/worldgen/wave_1_terrain_generator.gd), terrain/tree rules and sparse [overrides](../src/lfe/persistence/voxel_override_store.gd); worldgen v1/v2, v2 voxel trees | No biome/cave/water/ecology runtime. Define integration seams; preserve both existing outputs |
| Structures/entities | [Creation state](../src/lfe/entities/creation_state.gd) owns placed functional records, station/storage state and finite sources; [world resources](../src/lfe/entities/world_resource_state.gd) owns drops/crate; [characters](../src/lfe/entities/player_character.gd) own personal state | No general generated-structure/site or creature system. Define identity/lifetime rules without introducing a general entity registry |
| Saves/network | [World save](../src/lfe/persistence/world_save.gd) v4; [compatibility manifest](../src/lfe/networking/compatibility_manifest.gd) protocol 7, exact build/content hash/version checks; separate bounded voxel/resource/survival replicas | Preserve graph/recovery and wire formats; UI must consume authoritative state/results independently |
| Simulation | [Gameplay authority](../src/lfe/simulation/gameplay_authority.gd).advance_world → creation.advance; [survival adapter](../src/game/app/player_survival.gd) advances world once, then active actors | World/Kiln elapsed time exists; calendar/weather/offline catch-up/ecology and simulation LOD do not. Specify obligations, implement none here |
| Forge | `src/forge_eng/` and `tools/forge/` contain only `.gitkeep` files | Existing runtime validation works; no editor framework or workspace is justified by this readiness slice |

This is interface/code/test inspection plus retained W5.9 evidence, not a fresh
playtest of the dirty checkout. Existing tools/durability, held gathering, drops,
storage, crafting, Kiln, survival and reconnect remain implemented systems to
preserve, not replacement projects. Relevant behavioral contracts are
[W5.5](WAVE_5_PART_5_RESOURCES_INVENTORY_AND_TRANSACTIONS.md),
[W5.6 Repair 1](WAVE_5_PART_6_OWNER_ACCEPTANCE_REPAIR_1.md) and
[W5.7](WAVE_5_PART_7_RECONNECT_SESSION_TEARDOWN_AND_PERSISTENCE.md).

## W6.1 implementation deliverables proposed

1. Improve the existing inventory shell: viewport-anchored hotbar/panel, bounded
   scrolling/reflow when space is constrained, readable canonical name/count/tool
   durability and explicit context/equipment labels. All slots, output, close and
   Manual controls must remain reachable at 1280×720 and 1920×1080; at 960×540
   use scrolling rather than hiding interactive controls. These are proposed
   validation sizes, not measured current support. Keep existing input bindings.
2. Make source selection, incompatible/full destination, missing context, pending
   request and final result understandable. JOIN must not display a successful
   transfer solely because enqueue succeeded. Reuse existing result reasons and
   state updates; add no gameplay transaction or networking channel for UI feedback.
3. Retain personal/Workbench/storage/Kiln/Manual flow in one existing shell,
   normal crosshair RMB/E priority, I/C, split/swap/shift transfer and safe close.
   Preserve actor-specific crafting staging and blocked close/save on insufficient
   return capacity. HOST loss must clear selection, menus and replica references;
   reconnect must rebuild against fresh state. Gameplay input is suppressed while
   menus are open; gravity, collision and HOST simulation continue.
4. Finalize the equipment and integration contracts below in these existing
   documents, with focused tests only for actual UI changes and affected risks.
   Keep unsupported slots in the contract; do not present clickable empty future
   slots, add dummy content, or enlarge equipment arrays for appearance alone.

Deliverables exclude new gameplay, biomes, water, caves, flora/creatures/farming,
combat/stat effects, calendar/weather, simulation scheduler/LOD, general ECS,
new Forge workspaces, content registries, engine/plugin updates, save migrations
and protocol changes. Discovering a required wire/save break pauses that part
for a separately authorized design; it does not expand W6.1 automatically.

## Complete future equipment contract — candidate, not runtime schema

The rebuild has no authoritative full slot enumeration beyond `hand`/`body`.
The following is a complete candidate set for review; anatomy-specific additions
require a real later feature. Names/coverage and layering need owner ratification
before expanding content, saves or packets. W6.1 retains the existing two slots.

| Candidate semantic slots | Role / occupancy contract |
| --- | --- |
| `main_hand`, `off_hand` | Held tool/weapon/shield; a two-handed instance reserves both but is stored/counts once; later combat defines permitted combinations |
| `head`, `neck`, `shoulders`, `torso`, `back`, `wrists`, `hands`, `waist`, `legs`, `feet` | Worn/attached categories; paired limbs are one slot per category in this proposal; no armour/clothing layering or protection values yet |
| `ring_left`, `ring_right`, `trinket_1`, `trinket_2` | Explicit bounded accessory positions; no implicit effects or arbitrary unlimited accessories |
| `ammunition`, `utility` | One ammunition stack and one carried utility item; quantities obey canonical stack rules; no automatic reload/container expansion yet |

Contract for every slot: stable semantic ID, localized display label, canonical
content compatibility, occupancy/conflict rules, stack limit, owning actor,
instance/durability preservation, transfer/drop/death/reconnect/save behavior and
visible rejection reason. Body sockets/visual attachments consume equipment state;
they do not store a second item. The hotbar remains a view of inventory, not another
ownership location. A selected tool and equipped hand tool follow the existing
[harvest selection](../src/lfe/simulation/harvest_rules.gd) until an explicit later change.

Future migration proposal: map legacy `hand` to `main_hand`, `body` to `torso`;
retain all content/instance/durability exactly, initialize new slots empty, reject
unresolvable conflicts without deleting items. Never reinterpret positional arrays
or rename canonical content silently. Single-owner inventory/equipment transfers
must prepare/validate all endpoints then commit atomically; full/invalid/stale
destinations change nothing. Multi-slot occupancy requires one identity and one
conservation contribution, including reservations. Current stack restrictions do
not yet implement those semantics. Armour, visuals, two-hand handling and expanded
equipment persistence belong to later authorized equipment/combat work (Wave 7),
not living-world readiness. Proposed slots imply neither crafted items nor effects.

## Canonical voxel, structure and entity ownership

- `content/` owns definitions. The existing catalog's canonical string ID is the
  identity across voxel, stack, drop, recipe and placement; numeric voxel IDs are
  mesher mappings and must remain stable. Do not register a block again as an item.
- `src/lfe/` owns reusable runtime rules/state; `src/game/` owns Leyforge orchestration,
  presentation and adapters. Extend the actual owner when a new stage needs it.
  A future structure template is a definition referencing canonical blocks/entities;
  a placed/generated instance is world state. Template data must not become a
  duplicate block/entity registry. No structure schema/parser is needed in W6.1.
- HOST owns voxel edits and constructed records, storage, processes, finite-source
  depletion, drops and characters. Functional voxel + object record represent one
  logical constructed object: validate correspondence and count recoverable matter
  once. Preserve existing cell/orientation/instance and occupied-container break rules.
- Streaming unload destroys presentation Nodes, not durable records. Regeneration
  overlays saved edits after the stored deterministic base. Re-entry creates one
  presentation per relevant identity, never respawns depleted/cleared contents.
- Future generated sites/entities need world-scoped stable identities derived from
  a versioned, domain-separated placement key; runtime-created instances keep the
  existing identity rules. Repeated chunk visits/neighbor generation order must not
  allocate duplicates. Persist changed/cleared state in the actual future owner;
  do not make Nodes, scene paths or transport peers durable identity.

## Determinism, compatibility and replication

Generation remains seed + stored generator version + canonical definitions +
absolute coordinates. Worker generation uses immutable configured inputs and the
existing override-store synchronization; no scene-tree access or shared mutable
RNG. Later biome/structure/resource passes must define stable ordering, overlap
priority and cross-chunk ownership, including negative coordinates, before shipping.
Test generation order, worker scheduling and chunk-boundary equivalence; decoration
must not overwrite player edits. A seed alone is insufficient compatibility identity.

Preserve save/content/worldgen `4/1/2` with stored v1, protocol 7 and historical
v1–v3 migration. W6.1 UI work needs no new persistent fields. Opening old worlds
must not rewrite them; explicit successful save retains recovery behavior and exact
characters/tool instances/station reservations/source depletion. Unknown versions,
invalid graphs and corrupt checksums fail safely. New future generator semantics
require a new stored version and deliberate old-world behavior; new durable fields
require migration/recovery fixtures before use. Never update constants alone.

HOST validates actor binding, context/range/readiness, current revisions, capacity,
canonical references and bounded idempotent intent before commit/save/publication.
JOIN holds disposable views, predicts movement and never writes authoritative
world saves. Result and state channels may arrive independently: UI waits for their
facts rather than assuming cross-channel order. New future entities require bounded
bootstrap/deltas, gaps/resync, relevance and teardown rules before gameplay uses them.
HOST remote collision/interaction interest follows every actor, not HOST camera.
Private admission remains mandatory on LAN. Exact build equality and raw canonical
content fingerprint still gate admission; a UI build needs matching HOST/JOIN builds.

## Simulation and Forge integration contracts

Use the existing world advance seam once per HOST interval. Player count must not
multiply Kiln/world time; each active character's survival remains independent and
absent characters retain current freeze behavior. Later time/weather/ecology/farming
must name clock units, update cadence/budget, relevance, durable state and restart
behavior. Partitioned elapsed-time and reload tests must account for reservations
and once-only outputs. No offline awards or catch-up are implied by elapsed time.
Full background simulation/LOD remains Wave 16 work.

Forge-ENG (`src/forge_eng/`) will own reusable validation/import/export/baking only
when an actual authoring workflow needs it; Forge (`tools/forge/`) owns its creator UI.
Both must read/write the same canonical definitions loaded by runtime, use stable
references, report invalid references/versions before publication and produce
deterministic runtime inputs. Preview must use the same rules/version as the game
in disposable state, never owner saves. Authoring is not authority over a live HOST.
Content changes alter the existing fingerprint; no hot reload or content negotiation
is promised. W6.1's deliverable is this integration contract, not empty framework code
or a separate tooling registry. Future tooling scope must cite actual authoring pain.

## Acceptance and verification for a future W6.1 implementation

| Criterion | Required evidence |
| --- | --- |
| UI usability | Actual pointer/keyboard input and screenshots at the three proposed sizes in personal, Workbench, storage and Kiln views; readable quantities/durability/context, Manual/output/close reachable |
| Transaction integrity | Existing split/merge/swap/quick-transfer and tool instance behavior; rejected/full/stale/foreign operations conserve matter; pending/result/state ordering and full-backpack staging remain safe |
| Multiplayer/lifecycle | Separate graphical HOST/JOIN OS processes, independent inventories/equipment, normal RMB/E/I/C input; disconnect while a transfer/menu is pending, complete teardown, fresh same-identity reconnect |
| Compatibility | Deterministic v1/v2 generation and edit overlays; unchanged versions/packet shapes, matching build admission and mismatched build/content rejection; fresh-process save/reload and historical recovery |
| Scope | Diff limited to authorized existing UI/callers, meaningful tests and contract docs; no registries/slots/gameplay/schemas/protocol/engine/Forge implementation added |

Reuse [Wave 3 tests](../tests/wave_3/wave_3_test_runner.gd),
[Wave 4 tests](../tests/wave_4/wave_4_test_runner.gd),
[W5.5 focused tests](../tests/networking/w5_5_focused.gd), Repair 1 rendered input
and W5.7/W5.9 lifecycle/regression coverage. Add focused cases for changed behavior,
not a second transaction implementation. Development checks do not certify completion.

Before implementation, the authorized task must name its W6.1 final gate and evidence
destination. There is no W6.1 gate today. Proposed final gate: a stage-specific UI
entry point wrapping new focused/rendered checks plus the complete existing
[W5.9 gate](../tools/development/verify_wave_5_part_9.ps1) and its full nested
regressions on final source, approved runner and isolated profiles. Adding that
entry point needs explicit future harness scope; do not edit W5.9 to make old
receipts cover new work. Preserve failed attempts, source/runner manifests and
raw reports. Record owner UI acceptance separately, including tested build and
two-PC LAN results; do not carry forward unreported checklist rows as PASS.

## Proposed dependency obligations for W6.2–W6.18

Only the W6.1 title and broad Wave 6 domains are established in current repository
plans. The numbering below is a candidate sequencing proposal, not recovered stage
authority or permission to implement. Each stage needs its own bounded specification,
save/network/content decisions and actual acceptance; revise ordering after review.

| Candidate stage / focus | Prerequisites and contract to carry forward |
| --- | --- |
| W6.2 Biome/climate definitions | W6.1 ownership/version contract; canonical references and deterministic coordinate sampling |
| W6.3 Biome terrain integration | W6.2; explicit new-world generator version, retained v1/v2 behavior and boundary tests |
| W6.4 Geology/resources | W6.3; conserved extraction, canonical materials and deterministic regional placement |
| W6.5 Caves/underground | W6.3–4; cross-chunk density/collision, edit overlays and safe spawn/readiness |
| W6.6 Inland water foundation | Terrain/geology placement; bounded HOST liquid truth, storage/flow budget and persistence design before effects |
| W6.7 World clock/calendar foundation | Existing once-per-world tick; units/save/restart semantics, no implied offline progression |
| W6.8 Weather/environment | W6.2/7; authoritative samples and explicit interaction with shelter/independent survival |
| W6.9 Flora/fungi | W6.2–4/8; stable instances or voxel identity, deterministic eligibility and conserved harvest/depletion |
| W6.10 Structures/sites | Terrain/caves/flora placement policy; one template/instance contract, overlap priority and durable changed/cleared state |
| W6.11 Creature foundation | Habitat/terrain readiness; HOST identity/state, bounded replication and durable lifecycle |
| W6.12 Movement/behavior | W6.11; loaded collision/navigation ownership, relevance and cleanup independent of HOST camera |
| W6.13 Ecology/populations | W6.9/11–12; finite budgets, no duplicate spawn/output, save/reload and tick partition checks |
| W6.14 Farming | W6.6–9; plot identity, seed/input conservation, persisted growth and one authoritative clock |
| W6.15 Husbandry | W6.11–14; ownership/feed/shelter/output conservation and restart behavior; breeding only if separately scoped |
| W6.16 Biome/Worldgen/Structure Forge slice | Proven W6.2–10 authoring need; existing canonical inputs, validation and deterministic preview |
| W6.17 Creature/Ecology/Agriculture Forge slice | Proven W6.9–15 authoring need; shared authoring primitives only where reused, runtime round-trip |
| W6.18 Connected living-world verification | Authorized earlier slices; complete current regression chain, HOST/JOIN/save/recovery/performance evidence and owner acceptance |

Dependencies are not mandates for a complete simulation framework. Wave 17 online
connectivity and Wave 18 ecosystem completion remain distinct from W6.17/W6.18.

## Decisions before implementation

- Ratify the bounded UI deliverables and final gate/harness scope in the next task.
- Confirm or revise candidate future equipment slots/migration/layering before any
  expanded equipment implementation; this does not block preserving `hand`/`body` UI.
- Ratify or replace the proposed W6.2–W6.18 sequence; no absent stage spec is assumed.
- Reconcile the six pre-existing tracked changes and UID sidecars before selecting
  a runtime certification source. Do not silently include, reset or certify them.
- Obtain missing owner manual detail if checklist-complete physical acceptance is
  required; keep the [closure record's limitations](WAVE_5_CLOSURE.md) visible.
