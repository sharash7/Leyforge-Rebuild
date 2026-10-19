# W6.3.1 — Repository alignment audit

**DOCUMENTATION RECONCILIATION AUTHORISED — FINAL OWNER REVIEW PENDING.**
The owner has accepted the reconciliation direction with specific refinements;
this revised text and the exact publication set still await final approval.
Documentation preparation/validation only: no staging, commits, pushes, branch
changes or implementation. W6.4 is **NOT AUTHORISED**. Prepared 2026-10-19
(Australia/Perth), inspecting `D:\AI\Projects\Leyforge-Rebuild`, `main` at
`447bbd310afa6278bc3bdb359e3707585372b27d`. Documentation, investigation and
planning only. [W6.3 is CLOSED — OWNER ACCEPTED](WAVE_6_PART_3_CLOSURE.md).
No W6.4 implementation, production change, migration, new content or upgrade is
authorized by this report. The approved W6.4–W6.18 sequence stays intact.

## Conclusions and method

W6.1–W6.3 establish accepted inventory presentation, canonical presentation
authoring and genuine bounded 3D voxel asset authoring. Ownership is coherent:
LFE reads/compiles/loads runtime data, Forge-ENG owns authoring transactions and
publication, and Forge owns creator interaction. No duplicate registry was found
in those inspected workflows. The standalone model test is real runtime proof,
but it is not terrain/gameplay integration or completion of the broad Forge
coverage checklist.

The original audit's largest discrepancy was scheduling: full Block Forge, Material/Texture Forge
and shared library discovery are required future capabilities, but the numbered
living-world sequence does not allocate them explicit bounded delivery work.
Equipment expansion and Entity/Blueprint/World Forge likewise need consumer-led
contracts. This is a roadmap gap, not a newly discovered W6.3 blocking defect.
The owner-directed response now establishes Block/Material/Texture and shared
interaction planning contracts in W6.3.1, with provisional Block Forge delivery
before W6.7's real consumer and earlier requirements if W6.6 water needs them.
Existing-cube W6.4 can proceed after separate approval without completed Block
Forge. Early coordinated shell/interaction review follows useful Block/Texture
and World patterns; W6.17–18 integrate/harden them. These are reconciled planning
directions with final text pending, not new stage numbers or implementation authority.

This is a static source/contract/evidence review, not fresh functional testing or
a new certification. Current files were inspected with the dirty worktree intact;
the six pre-existing tracked modifications are not adopted as this audit's work.
The W6.3 committed owned blobs were separately reconciled to historical receipts.
No fresh engine capability probe, UX playtest, performance benchmark or physical
LAN/WAN test was performed. Missing observations remain missing. This subsequent
owner-directed reconciliation revises documentation only; it neither repeats the
original runtime tests nor converts their historical results into current proof.

## Source evidence index

Evidence keys below identify concrete owners/functions; findings reference these
keys rather than treating reserved workspace directories as implemented systems.

| Key | Source and inspected contract |
| --- | --- |
| S01 | [Architecture boundaries](ARCHITECTURE_BOUNDARIES.md), [AGENTS](../AGENTS.md): one implementation, actual consumer first, canonical ownership, HOST authority |
| S02 | [W6.1 specification](WAVE_6_PART_1_READINESS_UI_AND_INTEGRATION_FOUNDATION.md): future equipment, integration contracts and owner-established W6.1–W6.18 sequence |
| S03 | [W6.1 closure](WAVE_6_PART_1_CLOSURE.md), [W6.2 closure](WAVE_6_PART_2_CLOSURE.md), [W6.3 closure](WAVE_6_PART_3_CLOSURE.md): distinct owner decisions and historical certification |
| S04 | [W6.3 design](WAVE_6_PART_3_VOXEL_ASSET_FORGE_DESIGN.md): approved D1–D8, four domains, full Block Forge, 1 m blocks, 32×32 pixels, future damage |
| S05 | [Catalog document](../src/forge_eng/editing/content_document.gd), `TARGET`, `open`, `apply_edit`: one catalog path; existing solid block name/colour only |
| S06 | [Catalog](../src/lfe/content/block_catalog.gd), `load_from_path`, `_valid_inventory_definition`, `equipment_accepts`; [canonical data](../content/blocks/wave_1_blocks.json): shared block/item IDs, numeric mapping, harvest/tool fields, two accepted slots |
| S07 | [Voxel source](../src/lfe/content/voxel_asset.gd), `check`, `resolve`, `read_source`: schema 1, fixed 16³/16-per-metre, 32 swatches, strict paths, colour-only block references |
| S08 | [Compiler](../src/lfe/voxel/voxel_asset_compiler.gd), `compile`, `collision_boxes`: exposed faces, integer corners, deterministic axis box merging, versioned hash-bound bundle |
| S09 | [Loader](../src/lfe/voxel/voxel_asset_loader.gd), `load_bundle`, `shape_check`, `mesh`, `body`: bounded bundle, exact recompilation comparison, native mesh and boxes |
| S10 | [Library factory](../src/lfe/voxel/blocky_library_factory.gd), `create`; [game setup](../src/game/app/wave_1_playground.gd): runtime VoxelMesherBlocky with cube/empty models; no authored mesh adapter |
| S11 | [Voxel document](../src/forge_eng/editing/voxel_asset_document.gd), [publisher](../src/forge_eng/import_export/voxel_asset_publication.gd), [validation](../src/forge_eng/validation/voxel_asset_validation.gd): independent drafts, replay, conflict/recovery, explicit source publish, separate bake, >256-box advisory |
| S12 | [Shell](../tools/forge/forge.gd), [voxel workspace](../tools/forge/workspaces/voxel_asset/voxel_asset.gd), [Home](../tools/forge/workspaces/home/home.gd), [preview](../tools/forge/workspaces/preview_test/preview_viewport.gd): explicit tabs, manual ID open, scroll/collapse inspector, shared camera with mode-specific bindings |
| S13 | [Compatibility manifest](../src/lfe/networking/compatibility_manifest.gd), `fingerprint`, [save](../src/lfe/persistence/world_save.gd), [player resources](../src/lfe/entities/player_resource_state.gd): exact raw content identity, protocol 7, save/content/worldgen 4/1/2, equipment hand/body |
| S14 | [Terrain generator](../src/lfe/worldgen/wave_1_terrain_generator.gd), [override store](../src/lfe/persistence/voxel_override_store.gd), [creation state](../src/lfe/entities/creation_state.gd), [gameplay authority](../src/lfe/simulation/gameplay_authority.gd): existing versioned generation, overlays, functional records and HOST advance seam |
| S15 | [Master coverage](SHOWCASE_MASTER_COVERAGE.md), sections 23–24, [build waves](SHOWCASE_BUILD_WAVES.md), [coverage map](PRODUCTION_COVERAGE_MAP.md), [older slice](SHOWCASE_SLICE.md#s3--first-forge-capability): broad future scope; older Block/Item proposal is reference, not current authority |
| S16 | `.verification/wave6/w6_3/run-20261018T143834-425718000/`: `gate.json`, `focused.json`, `checks.json`, runtime reports, publication/precommit review and manifests; historical source association verified in closure |
| S17 | [Runtime scene adapter](../src/game/app/voxel_asset_runtime.gd), [runtime tests](../tests/forge/w6_3_runtime.gd): separate standalone LFE consumer, no gameplay placement |
| S18 | Supplied owner request, quoted and chronologically qualified in [closure](WAVE_6_PART_3_CLOSURE.md): functional acceptance and deferred coordinated UX redesign preference |
| S19 | Owner-directed reconciliation request supplied 2026-10-19: M01–M10 direction accepted with refinements, documentation-only authority, final text/publication review pending; recorded in the [reconciled amendments](WAVE_6_PART_3_1_PROPOSED_AMENDMENTS.md) |

## Findings register

**Historical 24-row register retained verbatim**, including classifications,
source evidence, status and original recommendations. Its timing/decision
recommendations describe the first audit, not the current owner-directed plan.
The dated reconciliation mapping immediately below supersedes those recommendations
where refined; it adds no new finding and does not rewrite historical evidence.

A = immediate prerequisite correction; B = schedule within Wave 6;
C = justified later-wave deferral; D = already covered/no action.
Class A is a prerequisite to the named future decision/consumer, not evidence of
an unaccepted functional defect or authority to change code now. Importance is
relative to that consumer. Each row records current status, missing capability,
dependencies, recommended stage, compatibility impact and required verification.

| Finding / class / importance | Source; current status and missing capability | Technical dependencies and recommended stage | Compatibility impact and verification requirements |
| --- | --- | --- | --- |
| F01 — A / high: status alignment | S03/S16/S18; published certification and later acceptance exist, tracked pointers still say candidate/audit not authorized. Missing current closure/navigation. | Record closure and this review now; preserve historical wording as history. Documentation correction only. | No runtime impact. Verify receipt hashes, 26 committed owned blobs, links, whitespace and protected files; do not rerun certification. |
| F02 — D / high: ownership | S01/S05/S07–12; LFE/Forge-ENG/creator separation and shared definitions implemented. Four domains are conceptual; only actual workflows have code. No missing generic framework is inferred. | Retain boundaries during every authorized stage. | No action now. Future reviews reject duplicated source, registries and authoring imports in runtime. |
| F03 — D / high: bounded Voxel Asset Forge | S04/S07–09/S11/S16–18; 3D tools, grouped commands, palette, drafts/recovery, publish, bake and standalone consumer implemented/accepted. Larger models, transforms and textures intentionally absent. | Retain accepted bounds; future consumers justify separate extensions. | No new schema now. Preserve historical tests; later extensions require bounds/replay/determinism/runtime proof. |
| F04 — A / critical before new terrain inputs: Block Forge contract/scheduling | S02/S04–06/S10/S15; presentation editor exists; full block definition authoring and geometry/material binding are missing. Existing runtime gameplay fields are not missing runtime systems. | Owner approves bounded contract and delivery attachment before W6.4 scope is finalized; F05/F06/F09/F10/F16. Actual authoring slice B within Wave 6, before its first consumer. | Contract only has no impact; implementation may change content schema/fingerprint and numeric mapping policy. Require ID stability, catalog consumer, harvest/drop/placement/conservation and old-world proof. |
| F05 — B / high: material and 32×32 texture workflow | S04/S05/S07–10; opaque swatches and block colour lookup exist; no texture painter, UV/per-face bindings or authored material workflow. | Preserve 32×32 base surface standard; decide reference/UV/filtering/atlas and material contracts before textured blocks; attach to F04 before relevant W6.7/10/12 content. | New fields/assets change content identity; no automatic save migration. Verify exact 32×32 validation, seams, orientation, pixel filtering, repeatable bake and runtime appearance. |
| F06 — A / critical at W6.4 planning: representative Overworld targets | S02/S06/S14/S15; real grass/dirt/stone/sand/oak and tool/functional examples exist. No approved representative selection spanning planned geology/resources/flora/creatures/structures was found in reviewed docs. | Owner selects a bounded target matrix with existing IDs or explicitly pending new definitions, owners and first consumer; before W6.4 design; progressively refine before W6.7/8/10/12/14/16. | Planning adds no IDs. Later admission requires validated references, fingerprints and old-world policy; no invented canonical names or content files. |
| F07 — B / medium: Item/Tool/Equipment Forge | S02/S06/S15; runtime items, tools, durability and hand equipment exist; creator editing of those fields/model attachments does not. | Use same catalog; F04 before specialised tool examples, F08 before slot expansion, attachments/pivots before held visuals. Attach only the subset needed by Wave 6 production; richer combat/gear in Wave 7. | Future field/instance changes require conservation, tool identity/durability, save/reconnect and HOST/JOIN tests. No parallel item registry. |
| F08 — C / high before gear expansion: expanded slots | S02/S06/S13; runtime is exactly hand/body; candidate coverage is head, chest, hands, legs, feet, cloak/mantle, belt/utility, rings, amulet, backpack, wings. Hand/offhand/layering are undecided. | Separate owner-ratified semantic/occupancy/attachment and legacy migration contract; normally Wave 7 before new gear, earlier only for a real approved consumer. Not a W6.4 prerequisite. | Potential save/wire/UI break. Test legacy two-slot loads, atomic multi-slot moves, one-instance counting, death/drop/reconnect, compatibility rejection. Never enlarge arrays for appearance. |
| F09 — A / high before first authored consumer: reference identities | S06/S07/S13; block/item IDs share catalog; asset IDs are separate source identities, numeric voxel IDs are runtime mappings, swatch keys are local. No consumer pin fields exist yet. | Approve ID/version/hash reference semantics and resolution in the existing consumer before F04/F12/F13/F14. Derived discovery may index files; it cannot allocate authoritative identities. | New consumer fields may alter schema/content hash; no remapping old voxels. Verify missing/stale/case/path collisions and one canonical definition across all callers. |
| F10 — D / critical: multiplayer and persistence baseline | S01/S02/S13/S14/S16; HOST commit/save/replica boundaries, strict compatibility and old-world support established. No live authoring or micro-voxel world state added. | Preserve in W6.4–18. New durable/wire fields need their own approved change contract. | Current task changes none. For later consumers require separate graphical HOST/JOIN, mismatch rejection, bootstrap/resync/teardown and save/recovery tests. WAN remains Wave 17. |
| F11 — B / medium: searchable library and small usability changes | S12/S18; manual namespaced ID entry/open and catalog list exist; proper voxel search, metadata browsing and Recent do not. | Next approved Asset workspace work can add bounded file-derived search/open and context hints; reuse actual document/publication owners. See UX plan group A. | UI/derived cache only if kept outside content; no identity rewrite. Verify search/type separation, dirty-switch/recovery, keyboard/focus and all three sizes. |
| F12 — B / high before W6.14: Entity Forge subset | S02/S07/S14/S15; players/creation records exist, general creature authoring/lifecycle does not. Voxel model alone is not an entity. | First need model pivot/scale/collision, stable definitions/instances, habitat, HOST lifecycle and bounded replication; author only creature subset for W6.14, husbandry additions W6.15. | Durable entities may need approved schema/protocol evolution. Verify repeat visits/unload/reload, no duplicate identity, HOST-only persistence and independent process replication. Rig/character depth can wait. |
| F13 — B / high before W6.16: Blueprint Forge subset | S02/S14/S15; placed functional records exist; authored structure templates, placement validation and generated-site identities are missing. | Stable block/entity references, transforms/overlap policy, chunk ownership, persistent cleared/depleted instances; bounded template authoring before W6.16 consumes it. | Template ≠ runtime registry. Test negative/cross-chunk placement order, player-edit priority, reserved/container matter counted once and no respawn on re-entry. |
| F14 — B / critical for living world: World Forge subset | S02/S14/S15; deterministic v1/v2 runtime exists; authoring macro/climate/biome/world settings is absent. | W6.4 first names immutable inputs/versioning; add minimal parameter validation/preview with each actual generator consumer, expand W6.5–10. No complete World editor required first. | Changed semantics need stored generator version/old-world decision; no constant-only bump. Test chunk/order/worker equivalence, edits overlay and fresh-process old/new worlds. |
| F15 — D / high: reusable geometry/compiler foundation | S07–09/S17; compiler has no terrain dependency; loader has no Forge imports. Reuse is proven by creator preview/standalone runtime. General reusable asset placement is not implemented. | Reuse these owners for future block/entity/blueprint adapters. | No changes now. Later consumers must preserve scale/origin, version/hash checks and malformed-bundle rejection. |
| F16 — B / high before terrain-model use: Zylann adapter | S08–10; game uses blocky cube library; fine assets load native ArrayMesh/StaticBody3D separately. No custom-model terrain adapter. | Probe installed fixed runner/plugin only when separately authorized; approve unit-cell geometry, culling, surfaces/UV, collision and pinned references. Attach to Block Forge before first detailed terrain block. | No plugin/engine upgrade inferred. Test installed API, neighbor/chunk seams, orientation, hit/placement semantics, HOST collision and old numeric IDs. |
| F17 — B / medium: rendered-face greedy meshing | S08/S16 and research R1/R2 below; current compiler culls internal faces but emits one quad per exposed fine-cell face; collision already merges. | Benchmark first, compare deterministic native compiler merge vs bounded VoxelMesherCubes adapter; attach to W6.18 or earlier only when first consumer budgets fail. | Compiler/artifact change invalidates bakes; source can stay schema 1 if semantics unchanged. Verify exact surface coverage, normals/winding/colour, future UV seams, determinism and compiler versioning. |
| F18 — A / high before repeated world placement: collision admission budgets | S08/S09/S11/S16; exact merged boxes and >256 advisory exist; no world-scale per-asset/chunk/player-interest hard budgets. | Define measured budgets with F16/first repeated entity placement; distinguish blocking world admission from valid standalone assets. Do not treat 256 advisory as a certified limit. | No budget change now. Later validation policy needs owner approval; benchmark worst layouts, many instances, rebuild cost and remote-actor collision interest. Preserve holes and gameplay collision contract. |
| F19 — B / high before mass runtime use: compilation/cache/packaging | S09/S11; bake exists but load_bundle recompiles for exact comparison; profile output is not shipped dependency closure. | Profile repeated loads; design validated cache keyed by exact source/dependencies/compiler/options and packaging only for first real consumer. Reuse existing loader. | Do not weaken stale/corrupt checks. New compiled format/version or packaged assets need approval; test tamper/stale/compiler mismatch, clean import, fresh process and source retention. |
| F20 — C / medium: damage/chipping visuals | S04/S06/S14; authoritative whole-block gathering exists; cracks/chips/fragments and per-cell damage do not. | Later mining/visual work can derive bounded transient visuals from authoritative state, keeping one 1 m world block. Persistent sculpting requires separate architecture decision. | Visual-only design must not change drops/collision/save/network truth. Verify rejection/cancel/reconnect resets, once-only reward and bounded debris. Persisted sub-block state is separate unapproved scope. |
| F21 — B / high: coordinated unified UX | S12/S18; functional shell, input isolation and constrained layouts exist, but owner reports density/discovery/visual-hierarchy problems. | Plan now; implement group A within approved workspaces, schedule group B once Asset + consumer-specific workflows establish common patterns; preferably review readiness by W6.16/17. | UI changes should preserve document/history/draft semantics; verify task completion, focus, accessible labels, state/action clarity, dirty switching and three sizes. Owner approves major pass separately. |
| F22 — C / medium: advanced authoring | S04/S15; resize, independent density UI, transforms, rigging, material graphs, broad import/migration, packaging ecosystem absent by design. | Defer to demonstrated consumers; ecosystem completion Wave 18 and visual production Wave 19, with earlier narrow exceptions explicitly approved. | Potential source/bake evolution; require bounded schemas, migration/recovery fixtures and real runtime consumers. No speculative framework. |
| F23 — B / critical: W6.4–18 integration contracts | S02/S14; numbered dependencies exist, detailed stage specs/acceptance for future systems do not. | Preserve exact sequence; proposed attachments and minimum entry/exit evidence in amendments. Finalize only the next authorized bounded stage. | New generators/entities/clocks need deliberate version/save/wire policy. W6.17 integrates actual systems; W6.18 full certification cannot be replaced by local probes. |
| F24 — D / high: source/validate/test/publish/bake separation | S05/S07–11/S16/S17; guarded source publication, external drafts/bakes, separate runtime testing implemented. Texture/material/block/entity publication breadth remains future consumer work in F04/05/12–14. | Retain explicit operations and consumer-specific gates. | Source additions change raw content hash even unused. Verify no-op bytes/version, base/dependency conflicts, interrupted recovery and clean runtime load for each later workflow. |

## Owner-directed reconciliation of the historical findings

Direction accepted 2026-10-19; final text/publication approval remains pending.
The following mapping accounts for all ten amendments without deleting or
renumbering F01–F24. S19 supplies the new owner direction; S01–S18 remain the
original evidence. The [amendment contract](WAVE_6_PART_3_1_PROPOSED_AMENDMENTS.md)
and [shared UX contract](WAVE_6_PART_3_1_UNIFIED_FORGE_UX_PLAN.md) carry the details.

| Amendment | Historical findings affected | Current reconciliation / recommendation precedence |
| --- | --- | --- |
| M01 | F01/F03/F10 | W6.1–3 remain CLOSED — OWNER ACCEPTED; W6.3.1 documentation reconciliation authorised, final owner review pending; W6.4 NOT AUTHORISED. Original acceptance chronology/receipts unchanged. |
| M02 | F04/F09/F16/F24 | Establish full end-to-end Block Forge planning now, safe supported creation/editing through real runtime proof; smallest complete useful implementation before first consumer, provisionally W6.7 and earlier if W6.6 needs it. Existing-cube W6.4 does not await completed Block Forge. Harvested blocks that remain blocks retain one definition. |
| M03 | F05/F14/F16 | Define render/gameplay material ownership, 32×32 surface references, orientation/UV/filtering/atlas and publication dependencies. W6.6 explicitly decides water representation/material/persistence and required transparent-surface proof; no normal-block/POC design assumption. |
| M04 | F06/F12–14/F23 | Staged selection separates existing production IDs, disposable fixtures, owner-approved new content and later pending selections. W6.4 may reference current grass/dirt/stone/sand after separate approval. POC/FCC research does not establish current authority. |
| M05 | F02/F07/F12–15 | Asset/Entity/Blueprint/World domains retained; genuine consumer-led workflows reuse LFE/Forge-ENG owners, without empty frameworks or shadow registries. |
| M06 | F08 | Explicit 12-position candidate with separate left/right rings retained; held-equipment inclusion, legacy mapping, main/offhand, layering/attachments, occupancy, durability/conservation and migration remain unresolved. Runtime stays hand/body, expansion normally Wave 7. |
| M07 | F15–19 | Separate terrain-block, prop, entity, collision-heavy and chunk assembly/load/rebuild budgets. Preserve deterministic fine geometry, distinguish rendered greedy merging from existing box merging; decorative detail need not imply detailed physical collision. Installed-version probes require separate authority. |
| M08 | F11/F21 | Coordinated interaction contract is defined now; Group A candidates remain bounded task inclusions. Early coordinated shell/interaction review follows useful Block/Texture and World patterns, without waiting for Entity/Blueprint or W6.16/17. Extend patterns later; W6.17–18 integrate/harden, Wave 19 may polish art. |
| M09 | F20/F22 | Compatibility for cracks/chips/fragments, larger/non-cubic models, pivots/attachments/rigs, advanced materials and import/export retained. Whole-block mining remains authoritative; persistent sub-block changes need separate architecture approval. |
| M10 | F10/F23/F24 | Each separately authorised stage declares canonical owners, generator/simulation version effects, persistent state, fingerprints, saves/compatibility, HOST/JOIN replication, consumer-specific proof and automated/owner evidence. W6.17 integration and W6.18 full certification unchanged. |

## Full Block Forge coverage and dependency boundary

“Full” means coherent canonical block authoring across existing gameplay/runtime
consumers, not completion of every conceivable material or destruction feature.
The exact slice still needs owner approval. Existing runtime capability must not
be counted as a missing system merely because its Forge editor is absent.

| Requirement | Runtime/current authoring coverage | Missing workflow and dependency |
| --- | --- | --- |
| Canonical block identity/numeric mapping | Catalog validates existing shared IDs and contiguous mappings; presentation editor locks IDs | Safe create/edit policy, reserved IDs, identity lifecycle and compatibility review; no second registry |
| Name/colour | Existing solid block edits publish to same catalog | Covered W6.2; retain as part of future Block Forge |
| Geometry/asset binding | Fine model source/bake/standalone runtime covered | Pinned model reference, unit-cell adapter, bounds, face culling, orientation and fallback; F09/F16 |
| 32×32 surfaces/textures | Standard retained in approved design; current factory renders colours | Surface pixel editor/import validation, face/UV assignment, filtering/atlas rules and runtime material consumer; F05 |
| Material definitions | Literal colour and solid-block colour references only | Approved distinction between render material and gameplay material; author only necessary shared properties; no duplicate block/material truth |
| Hardness/gathering/tool rules | Catalog harvest class, capability, seconds, outputs and tool efficiency/durability exist | Validated creator fields and consumer semantics; do not invent an additional hardness scalar that conflicts with harvest seconds |
| Drops/inventory/recipes | Shared IDs, stacks, drop/harvest outputs, recipes and instances exist | Reference-aware editing, deletion safeguards and conservation validation using current owners |
| Placement/functional behavior | Existing 1 m placement, stations/storage/light/rest and HOST rules | Author supported behaviors only, validate definition/constructed-record correspondence; no arbitrary scripts or duplicate state |
| Collision | World blocks use unit AABB; fine assets use exact occupied boxes separately | Explicit choice for detailed block collision, interaction target, budgets and host interest; never silently replace unit collision |
| Mining visual states | Whole-block authoritative extraction exists | Transient crack/chip presentation later; persistent sub-block destruction separately ratified |
| Validation/publication/bake/runtime | Strong patterns exist for two bounded document types | Extend the existing canonical consumers for approved fields; dependency-aware review, clean-runtime and gameplay proof before declaring full coverage |

The [full delivery contract](WAVE_6_PART_3_1_PROPOSED_AMENDMENTS.md#full-block-forge-delivery-contract)
is established during this W6.3.1 planning review. It connects safe supported
canonical creation/editing, stable mapping, reusable geometry, material/32×32
assignment, harvesting/tools/drops, placement/functions and collision/interaction
to validation, guarded source publication, baking and actual runtime testing.
A harvested block that remains a block retains one canonical definition, rather
than an independently duplicated item. The first implementation must be a
complete useful vertical slice, without every advanced material/animation/damage
or ecosystem feature.

Provisional attachment is before W6.7's first geology consumer, earlier if the
W6.6 water decision or another separately authorised consumer requires it. W6.4
macro generation can use existing cubes after separate approval without finished
Block Forge. Its bounded input/version/compatibility specification still matters.
No new runtime consumer, water representation or material schema is chosen now.

## Representative Overworld content: evidence and unresolved selection

The production catalog currently has 13 block entries including air and 10 item
entries. Existing terrain candidates include grass, dirt, stone, sand,
`leyforge:oak_heartwood` and `leyforge:oak_leaves`; tools/functional objects also
exist. The original examples did not select the future Overworld target set.
The owner now permits current grass/dirt/stone/sand as initial W6.4 terrain
examples after separate stage approval. Production `content/` has four non-placeholder JSON files
(blocks, recipes, crate and finite sources); no production W6.3 model examples.

Use the [staged selection contract](WAVE_6_PART_3_1_PROPOSED_AMENDMENTS.md#staged-representative-content-selection):
existing production IDs are distinct from disposable verification fixtures, new
canonical content requiring approval, and deferred later-stage selections. Select
geology/resources/habitat/flora/creatures/structures before their actual consumers;
unselected targets remain **OWNER SELECTION REQUIRED** without invented names/IDs.
Record each target's first stage, owner, references, authoring need and proof.
POC registries and FCC documents may inform research/content guidance but do not
automatically become current production authority. No complete Overworld selection
is needed for W6.4 and successful fixtures do not admit new production content.

## Geometry, meshing and collision recommendations

Current source dimensions `[16,16,16]` and density `16` describe hard-edged
0.0625 m fine cells within a 1 m volume. World voxel identity/authority stays
one 1 m block. Surface texture pixels stay 32×32 and are independent of model
resolution. Larger geometry does not imply larger texture pixels or a new world
voxel resolution. Keep canonical cells editable; compilation is a derived view.

S16 records a checkerboard with 2,048 disjoint boxes, 324.561 ms compile and
22.678 ms native body construction, and dense 4,096 cells at 352.818 ms compile
with one merged collision box. These historical machine-specific measurements
are neither fresh benchmarks nor a gameplay admission budget. Separate future
budgets for repeated terrain blocks, standalone props, creatures/entities,
complex collision-heavy assets and chunk assembly/loading/rebuilding. Tiny
decorative geometry need not imply equally detailed physical collision; choose
an approved consumer-appropriate representation while normal interactions retain
one authoritative 1 m world block. Preserve canonical fine geometry/compilation.
Preview refresh
and load-time recompilation merit profiling before large-world reuse; no claim
of a measured current interactive hitch is made by this static audit.

Rendered greedy face merging and occupied-volume box merging are separate:
the latter already exists. A future face merge should compare orientation,
plane, resolved colour/material and any UV/lighting seam data. It must retain
exact occupied surfaces, hard edges and winding. Same geometry from distinct
swatches may render alike today; preserve source keys and dependencies for future
editing/material semantics. Do not merge across future texture/material boundaries
simply because current RGB values match.

Primary documentation checked 2026-10-19 (research, not installed API proof):

- R1: [VoxelMesherCubes](https://voxel-tools.readthedocs.io/en/latest/api/VoxelMesherCubes/)
  documents colour-channel meshing and merging adjacent same-colour faces. It is
  a candidate for a bounded fine-asset bake comparison, not a direct replacement
  for the game's type-channel block catalog.
- R2: [Blocky terrain](https://voxel-tools.readthedocs.io/en/latest/blocky_terrain/)
  documents model batching/occlusion culling without greedy meshing, and texture
  atlas/material reuse. A greedy fine asset does not make terrain chunks greedy.
- R3: [VoxelBlockyModelMesh](https://voxel-tools.readthedocs.io/en/latest/api/VoxelBlockyModelMesh/)
  documents indexed triangle custom meshes, unit-cell bounds, limited surfaces
  and boundary-face culling constraints. This supports investigating a model
  adapter; it does not establish support in the bundled DLL.
- R4: [Godot collision shapes](https://docs.godotengine.org/en/stable/tutorials/physics/collision_shapes_3d.html)
  discusses primitive/convex/concave tradeoffs and broad-phase limitations with
  many shapes. Choose from measurements and gameplay requirements, not shape
  count alone; a surface collider is not automatically equivalent to occupied
  solid boxes.

The local project contains `addons/zylann.voxel/voxel.gdextension` and Windows
DLLs and already uses VoxelMesherBlocky. Its extension minimum compatibility
value is not a plugin release identity. No claim about newer installed custom
model/greedy APIs is made without an approved isolated probe. No engine/plugin
upgrade or dependency change is proposed as an audit fix.

Recommended optimisation order: establish representative fixtures and acceptance
budgets; profile compile/validate/load/reuse; avoid duplicate compilation through
a validated cache if measurements justify it; compare face merging/native plugin
output; then tune collision admission/representation for actual consumers. Measure
CPU time, vertices/triangles, bundle size, load time, draw calls, shape count,
physics/rebuild time and many-instance behavior. Preserve deterministic bytes or
version the compiler/artifact deliberately; never bypass current stale-bake checks.

## Source-to-runtime workflow and compatibility

| Step | Current evidence | Future obligation |
| --- | --- | --- |
| Source | One strict canonical voxel file; separate block/item catalog | Add reference fields only in the owner consumer, with approved schema/identity decisions |
| Draft/save | Independent profile namespaces, replayable commands/cursor, recovery copies outside content | Safe cross-document switching, discoverable draft state; preserve failure bytes |
| Validate | Current revision/base/dependencies; ordered source errors and box advisory | Consumer-specific reference/texture/gameplay/budget checks, actionable inspector location |
| Preview/test | Shared native viewport plus standalone LFE process | Terrain/entity/gameplay adapters require real consumer proof; standalone success is insufficient |
| Publish | Explicit single guarded source commit; no-op version preserved | Keep conflict/recovery and before/after review per canonical owner; no implicit bake/live reload |
| Bake/export | Derived deterministic hash/version-bound mesh outside content/profile-safe export | Packaged dependency closure/cache invalidation for real consumers; keep source recoverable |
| Runtime | Source-aware LFE validation/compilation/loading; blocky terrain uses own catalog factory | Resolve pinned references once through existing owners, budget reuse and verify clean startup |

Every raw canonical addition changes the compatibility fingerprint, even an unused
model. A visual source change can therefore affect saved-world/content admission;
it cannot be called compatibility-neutral just because save version stays 4.
Owner approval must define whether to retain content, reject, or explicitly migrate
existing worlds for future changes. No hot reload, peer content negotiation or
automatic migration is implied. JOIN sends intent; HOST validates/commits/saves;
revisioned views remain disposable. Authoring never writes a live world.

## Disposition and review

Historical initial-audit static validation receipt (retained unchanged):
`.verification/wave6/w6_3_1/review-20261019/documentation-validation.json`.
The one-off `validate_docs.py` in that ignored review directory checks the exact
11-document change set, local links/anchors, tables/fences/whitespace, unchanged
15 approved W6.4–18 rows, empty unchanged index and HEAD, and byte preservation
of 567 other existing non-ignored files, including all 54 initial dirty/untracked
paths. It also checks all 495 pre-existing W6.3 evidence files against the initial
inventory. `before.json` retains that inventory; `historical-review.json` records
the separate 26-owned-blob reconciliation and receipt hashes. These four local
review artifacts are not production files or a new repository governance system.
That receipt describes the earlier text, not fresh validation of this revision.
Current reconciliation inventory, before-text copies, diff and validation receipt
are separate ignored artifacts under
`.verification/wave6/w6_3_1/reconciliation-20261019T073435/`.

Completed: accepted W6.1–3 foundations and the documentation closure/alignment
investigation. Missing: full block/material/texture/consumer workflows and an
explicit delivery placement for them, searchable library, expanded authoring
domains and detailed future stage specs. Intentional deferrals include advanced
models/rigs/materials, full equipment expansion, destruction, ecosystem packaging
and visual polish. Corrections now are status/documentation and proposed planning
dependencies, not functional rewrites.

See the [UX plan](WAVE_6_PART_3_1_UNIFIED_FORGE_UX_PLAN.md) for early shared design,
bounded Group A and early coordinated implementation review, and the
[amendments](WAVE_6_PART_3_1_PROPOSED_AMENDMENTS.md) for reconciled stage attachments,
implementation order and unresolved decisions. The owner accepts this direction;
final text and the exact 11-document publication set still require separate review.
Stop after documentation preparation/validation. No staging, commit, push, branch
change or implementation is authorised; W6.4 remains NOT AUTHORISED. HEAD remains
the accepted implementation SHA above.
