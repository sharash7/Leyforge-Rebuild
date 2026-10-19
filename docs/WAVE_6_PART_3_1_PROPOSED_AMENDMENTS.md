# W6.3.1 — Proposed Wave 6 roadmap amendments

**DOCUMENTATION RECONCILIATION AUTHORISED — FINAL OWNER REVIEW PENDING.**
The owner has accepted the reconciliation direction with M01–M10 refinements.
This revised text and the exact 11-document publication set still require final
owner approval. Direction acceptance authorises documentation revision/validation
only: no staging, commit, push, branch change or implementation. W6.4 is
**NOT AUTHORISED**. W6.1, W6.2 and W6.3 remain CLOSED — OWNER ACCEPTED.
Prepared 2026-10-19 (Australia/Perth), baseline
`447bbd310afa6278bc3bdb359e3707585372b27d` on `main`.
Read with the [audit/findings register](WAVE_6_PART_3_1_ALIGNMENT_AUDIT.md),
[unified Forge UX proposal](WAVE_6_PART_3_1_UNIFIED_FORGE_UX_PLAN.md) and
[W6.3 closure](WAVE_6_PART_3_CLOSURE.md).

The [owner-established sequence](WAVE_6_PART_1_READINESS_UI_AND_INTEGRATION_FOUNDATION.md#owner-established-wave-6-sequence)
remains authoritative. The table below retains every W6.4–W6.18 name and its
dependency obligation; the final column proposes attached work, without inserting
new stages, renumbering systems or granting implementation authority. This
revision records the owner's direction; its detailed text remains under review.

## Proposed amendments and decision gates

| Amendment | Problem/evidence | Proposed bounded decision and disposition |
| --- | --- | --- |
| M01 — Current closure/status | Audit F01; published certification and supplied later acceptance | Direction accepted. Preserve W6.3 closure/chronology and original receipts; W6.3.1 documentation reconciliation is authorised with FINAL OWNER REVIEW PENDING. W6.4 is NOT AUTHORISED. |
| M02 — Full Block Forge delivery | F04/F05/F09/F16; presentation/geometry accepted but full delivery unscheduled | Establish the end-to-end Block Forge planning contract here. Attach the smallest complete useful implementation before its first real runtime consumer, provisionally W6.7, earlier if W6.6 water or another separately authorised consumer needs it. Existing-cube W6.4 does not require completed Block Forge. |
| M03 — Material/32×32 texture slice | F05; colour references do not author textures/materials | Preserve 1 m authoritative blocks, independent fine geometry and 32×32 base surfaces. Define render/gameplay ownership, references, face/UV/filtering/atlas and publication interfaces below. Evaluate W6.6 water first; do not assume W6.7 is the earliest material consumer. |
| M04 — Selected Overworld content | F06; staged selections required | Separate current production IDs, disposable fixtures, owner-approved new content and deferred selections. W6.4 terrain examples may reference existing grass/dirt/stone/sand definitions after separate stage approval. Progressively select later content; POC registries/FCC material are research, not production authority. |
| M05 — Consumer-driven Forge domains | F07/F12–14; broad domain coverage exceeds actual workspaces | Direction accepted for Asset, Entity, Blueprint and World Forge. Author only genuine consumer-required workflows using LFE runtime and Forge-ENG authoring owners. No empty frameworks, shadow registries or speculative workspace bus. |
| M06 — Twelve-position equipment candidate | F08; runtime hand/body intentionally retained | Preserve the explicit 12-position candidate below, with legacy/held-equipment, occupancy, layering, durability/conservation and migration questions unresolved. Candidate planning is not a runtime schema. Expansion normally belongs to Wave 7 unless separately authorised earlier. |
| M07 — Geometry/compilation/collision budgets | F15–19; standalone proof does not establish consumer admission | Separate terrain-block, prop, entity, collision-heavy-asset and chunk-assembly/loading/rebuild budgets. Preserve deterministic fine-source compilation. Only separately authorised installed-version probes may investigate Zylann custom models, occlusion, atlas reuse, batching and greedy meshing. Decorative detail need not dictate collision detail. |
| M08 — Unified Forge interaction strategy | F11/F21; owner refines timing | Define the coordinated interaction contract now in W6.3.1. Include bounded Group A work in authorised workspace tasks; review early coordinated shell/interaction implementation after useful Block/Texture and World workflows establish patterns. Extend them to Entity/Blueprint later. W6.17–18 integrate/harden; final theme/icons/art may remain Wave 19. |
| M09 — Damage/advanced authoring deferral | F20/F22; intentional omissions | Preserve compatibility with cracks/chips/temporary fragments, larger/non-cubic geometry, pivots/attachments/rigs, advanced materials and imports/exports. Authoritative mining stays whole-block; persistent sub-block modification needs separate architecture approval. No implementation now. |
| M10 — Explicit future stage compatibility/evidence | F10/F23/F24; future stage specs absent | Every separately authorised stage names canonical inputs/owners, generator or simulation version effects, persistent state, content fingerprints, save/compatibility, HOST/JOIN replication, consumer-specific runtime proof and automated/owner evidence. W6.17 integrates implemented systems; W6.18 remains full certification. |

Every amendment inherits the corresponding findings' source evidence, technical
dependencies, importance, compatibility impact and verification requirements.
Owner acceptance of this direction is not approval of the final document text,
publication set, runtime schema or implementation task. All implementation and
publication still require separate authority. The audit's 24 original findings
and evidence remain as a labelled historical register, with a current M01–M10
reconciliation mapping; no finding is erased or relabelled as a functional failure.

## Full Block Forge delivery contract

M02 is established here as a planning contract, subject to final text review.
The eventual end-to-end workflow must cover the following connected operations;
the first implementation is the smallest complete useful vertical slice through
supported fields and a real consumer, not a collection of disconnected editors.

| Capability | Ownership/interface and completion boundary |
| --- | --- |
| Canonical identity and creation/editing | Existing canonical block catalog remains the definition owner. Safe creation/editing must retain stable numeric mappings and validate references/collisions; no second block/item registry. |
| Reusable geometry | Reference published fine-voxel geometry through an approved stable ID/version/hash contract and existing LFE compiler/loader; terrain adaptation must preserve unit-cell and gameplay contracts. |
| Material and 32×32 surfaces | Assign approved material/texture references, face orientation/UV and dependencies through the interfaces below; fine-cell density does not set texture resolution. |
| Harvest/tool/drop rules | Author supported rules consumed by current catalog/gameplay owners; validate finite outputs, tool requirements, durability and conservation. A block harvested as the same block retains one canonical definition, not an independently duplicated item. |
| Placement and supported functions | Author only supported behavior, with HOST placement/constructed-record correspondence, ownership/storage/process rules and interaction targeting explicit. No arbitrary script or duplicate world state. |
| Gameplay collision/interaction | Specify consumer-appropriate collision and normal 1 m block interactions. Decorative geometry may use simpler approved collision; do not silently replace existing unit collision with fine-cell shapes. |
| Validate, publish, bake, test | Validate exact revision/reference closure; review and guard canonical source publication; bake versioned derived output; prove actual runtime consumption, including gameplay/HOST/JOIN and persistence where affected. Standalone mesh proof alone does not close Block Forge. |

Provisional delivery attachment is **W6.7 Geology & Terrain Composition**, before
its first required block/material/texture consumer. If the W6.6 water decision or
another authorised consumer needs part of this workflow earlier, its minimum
complete useful capability and proof move to that consuming stage without
renumbering. W6.4 using current cube definitions can proceed after separate
approval without completed Block Forge. Advanced material graphs, animation,
damage, rigs and ecosystem breadth are not prerequisites for the first slice.

## Material, surface and water interfaces

M03 preserves 1 m authoritative world blocks, independent fine model geometry
and 32×32 base surface textures. These are interface obligations, not new
canonical schemas or IDs:

| Concern | Planning interface and owner |
| --- | --- |
| Render material | Canonical approved render definitions/references belong under `content/`; LFE owns their validation/resolution/runtime use, Forge-ENG authoring validation/publication and Asset Forge creator controls. Do not introduce a new material registry without demonstrated consumer need and approval. |
| Gameplay properties | Block harvest, tool, drop and supported functional truth remains with the existing canonical/gameplay owners. A visual material may reference this truth where approved; it must not duplicate or implicitly override it. Shared physical properties need an explicitly named canonical owner before schema design. |
| Texture references | Stable approved source identity and dependency hash/version resolve to exact 32×32 base surface inputs. Source, draft, export and derived atlas/bake outputs remain distinct. No filename/path scheme or new asset schema is ratified here. |
| Faces and UVs | Specify face assignment, orientation/rotation, origin/UV convention, seams and any repetition before runtime use. Unit-cube and custom-mesh adapters must consume the same approved surface meaning. |
| Filtering and atlas | Preserve readable 32×32 pixel-art intent; choose filtering/mipmap/bleed rules and atlas padding/packing deterministically for the actual consumer. Atlas indices are derived output, not canonical content identity. Prove appearance at distance and face/chunk seams. |
| Publication dependencies | Review source references and dependency closure; validate before guarded publication, keep source recoverable, invalidate/rebuild stale bakes/atlases and require matching runtime consumption. Canonical changes alter the existing content fingerprint. |
| Transparency and surface behavior | Introduce only required bounded behavior and demonstrate sorting, depth/occlusion, seams, collision/interaction and HOST/JOIN consistency where relevant. Current opaque swatch acceptance does not prove transparent surfaces. |

Texture Forge must support creating, editing and safely importing validated 32×32 source textures, alongside assigning them to block faces and voxel geometry. Reference selection alone does not complete the planned authoring capability. Delivery remains bounded by actual consumer needs, with source validation, publication, baking and runtime proof.

Before assuming material delivery starts in W6.7, W6.6 must deliberately decide
water representation and resulting rendering/material, persistence, authority,
interaction, replication and bake/authoring needs. Evaluate suitable alternatives
against that bounded stage; water is not assumed to be a normal canonical block,
a fine-voxel asset, or the archived POC design. Any archived POC/FCC examples are
research only. Select no water representation or production content in this task.

## Staged representative-content selection

| Category | Status and use |
| --- | --- |
| Existing production canonical IDs | W6.4 examples may use `leyforge:grass`, `leyforge:dirt`, `leyforge:stone`, `leyforge:sand`; they already exist. This is permitted planning input, not W6.4 implementation approval. |
| Disposable verification fixtures | Explicit test-only identities/data remain isolated outside production content and owner saves. A successful fixture does not admit canonical game content. |
| New canonical content | Geology, resources, habitat, flora, creature or structure definitions/IDs require explicit owner selection and admission before the relevant consumer; no examples invented as production authority. |
| Deferred later-stage selections | Retain unresolved selections until their consuming stages need decisions; no need to select the complete Overworld before W6.4. POC registries and FCC documents may guide research only. |

## Twelve-position equipment candidate

M06 retains exactly these candidate planning positions, not runtime slots:

1. Head
2. Chest
3. Hands
4. Legs
5. Feet
6. Cloak/mantle
7. Belt/utility
8. Left ring
9. Right ring
10. Amulet
11. Backpack
12. Wings

Unresolved: existing `hand`/`body` legacy mapping; main-hand/offhand semantics;
layering and attachment conflicts; occupancy and multi-slot relationships;
instance conservation, durability and migration; and whether these 12 positions
include or supplement held equipment. No mapping or packet/save layout is implied.
Runtime remains exactly `hand` and `body`; no placeholder slots. Expansion normally
belongs to Wave 7, unless separately authorised for an earlier genuine consumer.

## Consumer-specific geometry and performance admission

M07 requires separate measured budgets for repeated terrain blocks, standalone
voxel props, creatures/entities, complex collision-heavy assets, and chunk
assembly/loading/rebuilding. Define per-asset/per-instance and aggregate/relevance
costs where applicable; an accepted standalone asset is not automatically fit
for dense terrain placement. Establish representative fixtures before optimisation.

Preserve canonical fine-cell geometry and deterministic compilation. Rendered
greedy face merging is distinct from implemented collision-box merging. Tiny
decorative features need not have equally detailed physical collision; approve
collision simplification against actual interaction/traversal needs while retaining
one authoritative 1 m normal world block. Zylann custom-model/occlusion/atlas/
batching/greedy opportunities require separately authorised probes of the actual
installed runner/plugin, not conclusions from latest docs or a version upgrade.

## Early unified interaction contract

M08 defines shared interaction principles during W6.3.1 planning, before workspace
proliferation. The [UX contract](WAVE_6_PART_3_1_UNIFIED_FORGE_UX_PLAN.md) covers
four-domain navigation, canonical-derived search, New/Open/Recent, typed identity,
persistent document states, separate lifecycle actions, context inspectors,
discoverable tools, active/visual hierarchy, keyboard/mouse rules, responsive
panels, accessibility and safe switching/conflict/recovery.

Include bounded Group A improvements in their separately authorised workspace
tasks. Review an early coordinated shell/interaction implementation after useful
Block/Texture and World workflows reveal genuine shared patterns; Entity and
Blueprint workflows are later adopters, not prerequisites for this review.
W6.17–W6.18 integrate and harden implemented patterns; Wave 19 may handle final
high-fidelity theme, icons and art. No repeated full-shell redesign or premature
generic UI framework is authorised. Final review of this contract precedes any
separate implementation decision.

## W6.4–W6.18: preserved sequence with proposed attachments

| Approved stage | Existing dependency obligation retained | Proposed attachment / minimum entry and verification |
| --- | --- | --- |
| W6.4 Macro World Generation | W6.2–3 inputs; versioned deterministic coordinates and retained old worlds | Existing-cube macro generation may use current grass/dirt/stone/sand after separate approval, without completed Block Forge. Establish planning contracts/inputs and version policy; attach minimal World parameter validation/preview only to authorised runtime need. Verify seed/version/absolute and negative coordinates, chunk order and stored v1/v2 worlds. W6.4 remains NOT AUTHORISED now. |
| W6.5 Climate & Environmental Regions | W6.4 coordinate sampling and stable regional boundaries | Author/validate only necessary climate parameters in the World domain; immutable worker inputs and reproducible region transitions. No weather clock implied. |
| W6.6 Hydrology & Water Foundations | W6.4–5 terrain/climate; bounded HOST water truth and persistence | Deliberately decide water representation, material/transparency/surface proof, persistent versus generated state, HOST replication/interaction, restart and interest bounds. Do not assume canonical-block or archived POC water. Deliver any required Block/Material/Texture capability before this consumer, earlier than provisional W6.7. |
| W6.7 Geology & Terrain Composition | W6.4–6 placement dependencies and edit overlays | First geology consumer; provisional attachment for the smallest complete useful Block/Material/Texture implementation before required consumption, earlier if W6.6 needs it. Ratify geology references; prove stable IDs, 32×32 assignment, gameplay rules, guarded publish/bake and actual runtime use/legacy behavior. No geology names selected here. |
| W6.8 Resource Distribution | W6.7 materials; canonical references and finite extraction | Author/validate selected resource and extraction identity in existing owners; prove deterministic placement, finite extraction, tool/durability and once-only yields. A harvested block that remains a block keeps one canonical definition; no independent duplicate item or shadow resource/material registry. |
| W6.9 Caves & Underground Generation | W6.4/6/7; cross-chunk density/collision and safe readiness | Extend World preview for actual cave inputs if needed; measure collision/readiness and generation order across chunk boundaries, never overwrite edits. |
| W6.10 Biomes, Ecotones & Regional Ecology | W6.5–9 habitat inputs and deterministic transitions | Ratify small biome/habitat target set before definitions; author validation/preview of those inputs only. Verify deterministic transitions, overlap priority and reference closure. |
| W6.11 Time, Weather & Environmental Systems | W6.5/10; one HOST clock, save/restart and survival semantics | Name units, cadence/budgets, durable state and restart behavior. Reuse one world advance seam; test player-count independence, partitioned elapsed time and no implied offline awards. |
| W6.12 Flora & Vegetation | W6.8/10/11; stable identity and conserved harvest/depletion | Select flora before use; deliver the required geometry/content authoring workflow with model/block/material references, runtime placement/collision and conserved harvest/depletion. Stable versioned identities survive unload/reload; larger models/pivots only if this authorised consumer requires them. |
| W6.13 Agriculture & Farming | W6.6/11/12; plot identity, input/output conservation and persisted growth | Author only required plot/crop/recipe inputs. Verify ownership, planted/harvested conservation, clock/restart and multiplayer replication. Do not build a general ecology framework ahead of use. |
| W6.14 Creatures & Wildlife | W6.9–12 habitats; HOST lifecycle, collision/relevance and bounded replication | Minimum Entity Forge definition/model/validation workflow and runtime identity/placement contract before creature use. Verify separate HOST/JOIN, spawning/depletion, streaming lifetime, collision interest and save/reload. Rigging breadth is not automatically required. |
| W6.15 Husbandry & Animal Management | W6.13–14; conserved feed/output, ownership and restart behavior | Extend the real entity/recipe owners for husbandry only; verify feed/output identity, ownership and restart/teardown. No equipment-slot expansion implied. |
| W6.16 Structures, Landmarks & World History | Earlier terrain/ecology plus Forge; template/instance identity and durable cleared state | Minimum Blueprint Forge with approved block/entity references and deterministic placement/clearing before generated structures. Extend established shared interaction patterns; this stage does not gate early shell design/review. Test neighbor order, negative coordinates, player edits and no duplicate/respawned contents. |
| W6.17 Complete Living World Integration | Authorised prior stages; shared budgets, deterministic overlap and lifecycle consistency | Integrate living-world systems, shared budgets and implemented Forge interaction patterns across mature domains; no speculative scheduler/ECS or deferred first shell design. Verify cross-system HOST/replication/save and authoring interaction consistency. |
| W6.18 Hardening, Optimisation & Certification | Complete source-matched regressions, measured performance, HOST/JOIN/save/recovery and owner acceptance | Measure world-scale meshes/collision/compilation/reuse and UX; optimise only demonstrated limits. Run required full final-source gates and preserve failures; automated success stays separate from owner acceptance. |

Wave 17 (online connectivity) and Wave 18 (Forge ecosystem completion) remain
different from W6.17/W6.18. Keep the existing WAN deferral and later visual
production Wave 19. Broad master-coverage boxes remain open until their own real
workflows/consumers justify closure; W6.3 acceptance does not complete the ecosystem.

## Recommended implementation order, after separate authorisation

1. Complete final owner review of this revised text and exact publication set.
   The accepted M01–M10 direction is recorded; no staging/publication or runtime
   implementation follows automatically from that decision.
2. After separate W6.4 authorisation, existing-cube macro generation can use
   current grass/dirt/stone/sand without completed Block Forge. Its bounded
   specification still names inputs, old-world/version policy and required proof.
   W6.3.1 establishes Block/Material/Texture and shared interaction contracts now.
3. At W6.6 planning decide water representation/material/persistence/authority
   deliberately and check whether it needs earlier Block/Texture capability.
   Provisionally deliver the smallest complete useful Block/Material/Texture
   slice before W6.7's first geology consumer; move requirements earlier only
   for a genuine authorised consumer. Include bounded Group A UX work naturally.
4. Review early coordinated shell/interaction implementation after useful
   Block/Texture and World workflows establish patterns, without waiting for
   Entity/Blueprint or W6.16/17. Continue W6.4–W6.11 in their exact approved
   order; attachments follow actual consumers, not a new numbered stage.
5. Execute W6.12–W6.15 with necessary selected flora/Entity workflows and existing tool
   semantics. Introduce specialised Item/Tool/Equipment authoring only for a
   demonstrated need; expanded slots normally remain Wave 7.
6. Supply the bounded Blueprint workflow before W6.16 structures, extending
   established shell/interaction patterns to it and Entity Forge as they mature.
   W6.17 integrates implemented living-world and Forge interactions; it is not
   the first coordinated interaction-design checkpoint.
7. W6.18 measures remaining limits, performs justified optimisation and completes
   full certification/owner review. Keep larger ecosystem/rigging/destruction
   work separately approved; final high-fidelity theme/icons/art can remain Wave 19.

The list is a dependency proposal. It neither schedules a new implementation
stage between existing numbers nor permits running ahead into W6.4 today.

## Owner decisions still required

| Decision | Required before | If unresolved |
| --- | --- | --- |
| Final text approval of M02 delivery contract and exact bounded implementation scope | Separate consumer/implementation authorisation; provisionally W6.7, earlier if W6.6 needs it | Direction is accepted; no implementation scope inferred. Existing-cube W6.4 need not wait for finished Block Forge. |
| Select new geology/resources/habitat/flora/creature/structure targets progressively | Their relevant content-consuming stages | Existing W6.4 grass/dirt/stone/sand examples are permitted planning inputs; new IDs remain unapproved. |
| Decide W6.6 water representation, material/surface/transparency and persistence/authority interfaces | W6.6 bounded specification and any earlier material delivery | Do not assume a normal canonical block or inherited POC design; retain current opaque workflow. |
| Approve concrete material schemas/references, UV/face/filtering/atlas choices and runtime proof | New surface/material implementation and its first consumer | Planning interfaces do not ratify new fields, registries or content. |
| Approve asset binding, consumer-specific collision budgets and any packaging/cache/compiled-version changes | Each relevant real geometry consumer | Standalone acceptance remains valid; tiny decoration does not mandate fine physical collision. |
| Approve Group A task scope and early coordinated shell/interaction implementation after Block/Texture and World patterns | Those separately authorised implementation tasks | Early design is documented now; Entity/Blueprint are later adopters. No UI rebuild authorised. |
| Resolve the twelve-position candidate's held/legacy, occupancy/layering, attachment, durability/conservation and migration questions | First expanded-slot change, normally Wave 7 | No runtime schema or placeholder slots; runtime remains exactly hand/body. |
| Approve any new generator/save/content/protocol semantics with old-world policy | Corresponding stage implementation/publication | Preserve existing versions/compatibility; do not bump constants alone |
| Approve final document text and exact 11-path publication set separately | Any staging/commit/push of this deliverable | Current authority expressly prohibits staging, commits, pushes and branch changes; stop after preparation/validation. |

No original failed receipt, owner problem report or acceptance-pending historical
field is rewritten. Documentation validation does not certify runtime changes.
Stop after documentation preparation/validation for final owner review.
W6.3.1 direction acceptance is not publication or implementation approval;
W6.4 remains NOT AUTHORISED.
