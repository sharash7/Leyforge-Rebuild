# W6.1 — Readiness, UI & Integration Foundation

**W6.1 CLOSED — OWNER ACCEPTED 2026-10-18.** See the
[closure record](WAVE_6_PART_1_CLOSURE.md) for the certified publication, retained
automated evidence and the owner's 9/9 UI PASS. W6.2 is
[proposed for approval](WAVE_6_PART_2_FORGE_FOUNDATION.md), not implementation.

The following implementation/repair contract is retained as history.
**W6.1 implementation candidate, owner-authorized 2026-10-16.**
Starting `main`: `7623595424dfb3ca6c98e45bfcf28afdab3e353c`.
Wave 5's historical closure is unchanged. W6.1 includes the targeted drop-follow
repair described below. Publication requires a complete final-source automated
PASS receipt; owner UI acceptance remains a separate decision.
W6.2 and later are not authorized.

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

The table records the inspected baseline. Fresh candidate UI/input and regression
results are recorded by the W6.1 gate; historical W5.9 evidence alone does not
certify this candidate. Existing tools/durability, held gathering, drops,
storage, crafting, Kiln, survival and reconnect remain implemented systems to
preserve, not replacement projects. Relevant behavioral contracts are
[W5.5](WAVE_5_PART_5_RESOURCES_INVENTORY_AND_TRANSACTIONS.md),
[W5.6 Repair 1](WAVE_5_PART_6_OWNER_ACCEPTANCE_REPAIR_1.md) and
[W5.7](WAVE_5_PART_7_RECONNECT_SESSION_TEARDOWN_AND_PERSISTENCE.md).

## Implemented UI candidate

1. Improve the existing inventory shell: viewport-anchored hotbar/panel, bounded
   scrolling/reflow when space is constrained, readable canonical name/count/tool
   durability and explicit context/equipment labels. All slots, output, close and
   Manual controls must remain reachable at 1280×720 and 1920×1080; at 960×540
   use scrolling rather than hiding interactive controls. These are mandatory
   validation sizes; results belong to the source-matched W6.1 receipt. Keep existing input bindings.
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

## Future equipment coverage — proposal only

Runtime slots remain exactly `hand` and `body`. Candidate future coverage is
head, chest, hands, legs, feet, cloak/mantle, belt/utility, left/right rings,
amulet, backpack and wings. This is not a ratified schema or a complete slot set.
Hand/offhand, layering, ammunition, trinkets and additional sockets remain future
design decisions. No legacy-slot migration mapping is ratified.

Future equipment must define stable semantic IDs, canonical compatibility,
occupancy/conflicts, stack limits, owning actor, instance/durability conservation,
and atomic transfer/drop/death/reconnect/save behavior before implementation.
Attachments consume equipment state without storing a second item. Multi-slot
occupancy must count one instance once. The hotbar remains an inventory view.
No new slots, items, arrays, packets, saves or placeholder UI are introduced here.

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
Simulation budgets/LOD require a separately authorized design; W6.17 integrates only implemented systems.

Forge-ENG (`src/forge_eng/`) will own reusable validation/import/export/baking only
when an actual authoring workflow needs it; Forge (`tools/forge/`) owns its creator UI.
Both must read/write the same canonical definitions loaded by runtime, use stable
references, report invalid references/versions before publication and produce
deterministic runtime inputs. Preview must use the same rules/version as the game
in disposable state, never owner saves. Authoring is not authority over a live HOST.
Content changes alter the existing fingerprint; no hot reload or content negotiation
is promised. W6.1's deliverable is this integration contract, not empty framework code
or a separate tooling registry. Future tooling scope must cite actual authoring pain.

## Acceptance and verification

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

The dedicated entry point is `tools/development/verify_wave_6_part_1.ps1`.
`-FocusedOnly` runs development UI/layout/input checks and never certifies.
The default additionally runs the complete unchanged W5.9 chain, its default
660-second soak and established source projection/runner rules. All W6.1 receipts
are append-only under `.verification/wave6/w6_1/run-<UTC>/`; the nested W5.9
receipt stays at its original path. Raw logs, manifests, screenshots and process
reports are retained. Any failure prevents certification and publication.
Owner UI acceptance is separate. Existing W5.9 launchers remain the owner entry
points, now displaying the candidate UI; use matching HOST/JOIN source builds.

## Owner-established Wave 6 sequence

This sequence is ratified for planning by the 2026-10-16 implementation request;
it authorizes W6.1 only. Future stages still need bounded specifications and
compatibility/acceptance decisions. Forge foundations precede world expansion.

| Stage | Dependency obligation |
| --- | --- |
| W6.1 Readiness, UI & Integration Foundation | Current runtime ownership, transactions, compatibility and presentation |
| W6.2 Forge-ENG & Unified Forge Foundation | W6.1 contracts; shared canonical definitions and actual authoring needs |
| W6.3 Voxel Asset Forge | W6.2 validation/preview; stable voxel IDs and runtime-compatible outputs |
| W6.4 Macro World Generation | W6.2–3 inputs; versioned deterministic coordinates and retained old worlds |
| W6.5 Climate & Environmental Regions | W6.4 coordinate sampling and stable regional boundaries |
| W6.6 Hydrology & Water Foundations | W6.4–5 terrain/climate; bounded HOST water truth and persistence |
| W6.7 Geology & Terrain Composition | W6.4–6 placement dependencies and edit overlays |
| W6.8 Resource Distribution | W6.7 materials; canonical references and finite extraction |
| W6.9 Caves & Underground Generation | W6.4/6/7; cross-chunk density/collision and safe readiness |
| W6.10 Biomes, Ecotones & Regional Ecology | W6.5–9 habitat inputs and deterministic transitions |
| W6.11 Time, Weather & Environmental Systems | W6.5/10; one HOST clock, save/restart and survival semantics |
| W6.12 Flora & Vegetation | W6.8/10/11; stable identity and conserved harvest/depletion |
| W6.13 Agriculture & Farming | W6.6/11/12; plot identity, input/output conservation and persisted growth |
| W6.14 Creatures & Wildlife | W6.9–12 habitats; HOST lifecycle, collision/relevance and bounded replication |
| W6.15 Husbandry & Animal Management | W6.13–14; conserved feed/output, ownership and restart behavior |
| W6.16 Structures, Landmarks & World History | Earlier terrain/ecology plus Forge; template/instance identity and durable cleared state |
| W6.17 Complete Living World Integration | Authorized prior stages; shared budgets, deterministic overlap and lifecycle consistency |
| W6.18 Hardening, Optimisation & Certification | Complete source-matched regressions, measured performance, HOST/JOIN/save/recovery and owner acceptance |

These living-world systems and Forge workspaces remain unimplemented by W6.1.
Wave 17 online connectivity and Wave 18 ecosystem completion are distinct from
W6.17/W6.18. No detailed future implementation plans are created here.

## Remaining decisions (updated 2026-10-18)

- Owner UI acceptance completed at the published commit; see [closure](WAVE_6_PART_1_CLOSURE.md).
- Future equipment ratification before changing the two-slot runtime model.
- Owner approval of the [bounded W6.2 specification](WAVE_6_PART_2_FORGE_FOUNDATION.md) before implementation.
- Retain the Wave 5 closure record's missing manual traceability and WAN deferral.

## Candidate changes and owner UI check

The existing shell now anchors the hotbar and bounds the inventory to the viewport.
It stacks context sections at constrained logical widths, scrolls retained controls,
wraps slot names with separate quantities/durability and labels both equipment
positions. Inventory UI renders above the survival HUD to prevent overlapping
labels. The Manual uses bounded scrolling in the same shell. Bindings are unchanged.
A persistent feedback label distinguishes pending, accepted and rejected commands;
JOIN acceptance comes only from the existing authoritative result channel. No
request enqueue is counted as a moved quantity. Independent state/results, rejected
capacity/context and staged close behavior retain the existing transaction owner.

Run development checks or the mandatory final gate from the repository:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_6_part_1.ps1 -FocusedOnly
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_6_part_1.ps1
```

For owner UI acceptance use matching candidate source on HOST/JOIN. Existing
launchers preserve identity/save selection; record the tested commit and world:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_9_host.ps1'
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_9_join.ps1'
```

Use the current private invite in the masked JOIN prompt. Check I/C, normal RMB/E
Workbench/storage/Kiln interaction, source selection, split/swap/quick transfer,
Manual, output and close at 1920×1080, 1280×720 and 960×540. Check accepted and
rejected/full transfers, staged close refusal, pending feedback, HOST loss and
same-identity reconnect. Record readability/scrolling observations and the overall
acceptance decision separately from the automated receipt. No owner acceptance
is claimed here.

## Targeted certification repair — 2026-10-17

The prior failed complete attempt remains at
`.verification/wave6/w6_1/run-20261016T110659565588100/gate.json`.
The nested Repair 1 trace recorded a 0.06300044 m HOST target correction and a
0.05028093 m visual step across a 131 ms rendered gap. Its remaining lag and
production exponential follow imply a 0.13333371 s engine delta. The existing
strict <0.04 m check correctly exposed a presentation weakness.

Controlled graphical probes reproduced the weakness in both the unchanged
previously certified source (`fe4411c6ca9cf2598d1564ff3ce5cd0461f8c29e`)
and the unchanged W6.1 candidate. All nine stalled trials per source exceeded
0.04 m with actual 131/200/400 ms main-thread stalls; normal trials remained
approximately 0.01142 m. These probes use the production presenter and actual
engine deltas, with post-draw timing and positions. No UI is needed to reproduce
the defect. This establishes the mechanism independently of W6.1 UI; it does not
identify the scheduler/render workload responsible for the original hitch or
claim equal frame-time performance across UI versions.

The minimal repair retains exponential follow at 12/sec and limits each JOIN
small-correction visual step to 0.039 m, leaving room for the existing <0.001 m
convergence snap under the strict 0.04 m frame-step bound. HOST record positions,
10 Hz publication, >0.75 m snap behavior, identities, transactions, pickup and
merge/despawn cleanup are unchanged. Neither the existing Repair 1 instrumentation
nor its assertions/thresholds are changed.

The new rendered `tests/networking/w6_1_drop_frames.gd` probe is included in the
W6.1 gate. It blocks the actual main thread, records engine delta plus post-draw
wall-clock timing/positions and checks strict step/lag/convergence bounds across
three normal trials and three each at 131/200/400 ms. Three independent repaired
runs passed all 36 trials; maximum measured step was 0.039000001 m. Raw baseline,
candidate, failed and repaired evidence is retained under
`.verification/wave6/w6_1/run-20261017T033008-drop-repair/`.

Earlier failed attempts remain retained, including the corrected Manual nested
scroll defect, an intermittent W5.3 packet-rejection case and Windows long-path
cache cleanup with a long temporary root. Use a short disposable TEMP/TMP root
such as `D:\lf61` for the complete gate. Targeted diagnostics do not replace
complete certification. The final gate must run all required Waves 0–5 against
this final source, with no skipped or shortened regressions. Its append-only
`gate.json`, manifests, raw logs and nested receipts determine certification;
publication is permitted only after that source-matched complete PASS.

Owner UI acceptance and expanded equipment design remain separate decisions.
W6.2 is not authorized by this repair or by any automated PASS.
