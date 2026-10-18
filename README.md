# Leyforge

Leyforge is a fantasy voxel civilisation sandbox.

This repository is the single canonical production repository for the game, its Leyforge Engine (LFE) runtime code, Forge-ENG authoring infrastructure, and The Forge development tools.

## Current production goal

Build a broad, shallow, playable **Leyforge Showcase Slice** first. The slice should demonstrate the foundations of the major game pillars before individual systems are expanded deeply.

Initial sequence:

1. Clean Godot project + voxel plugin
2. Basic deterministic voxel world
3. Player movement and voxel interaction
4. Persistence
5. Gathering, inventory, tools and crafting
6. Building
7. Small living settlement
8. Basic NPC labour
9. Basic automation
10. Flux / magic
11. Combat and exploration
12. Showcase polish

Breadth is the priority, not a hard cap on depth. If a system becomes useful or fun to extend, it may be taken further when that work strengthens the foundation.

## Repository principles

- One canonical repository.
- No Project Brain or governance framework inside the game repository.
- Do not copy implementation code from archived Leyforge projects by default.
- Old Leyforge documentation remains design/reference material.
- Build features because the game needs them.
- LFE grows out of reusable runtime requirements.
- Forge-ENG and The Forge grow out of real authoring pain points.
- One canonical content definition should serve the game, LFE, tools and tests.
- Prefer real expandable foundations over throwaway prototypes.
- Keep the game playable throughout development.

See `docs/SHOWCASE_SLICE.md` for the initial production direction.

See `docs/PRODUCTION_COVERAGE_MAP.md` for the broad known game/LFE/Forge surface, including multiplayer/networking, without treating it as an implementation checklist.

## v0.3 production direction

- `docs/SHOWCASE_MASTER_COVERAGE.md` — complete known miniature-universe coverage.
- `docs/SHOWCASE_BUILD_WAVES.md` — dependency-oriented implementation order.
- `docs/ARCHITECTURE_BOUNDARIES.md` — ownership between Leyforge, LFE, Forge-ENG, The Forge and canonical content.

`SHOWCASE_MASTER_COVERAGE.md` and `SHOWCASE_BUILD_WAVES.md` supersede the older early-slice roadmap for current planning.

## Current playable build

The current runtime version remains **0.6.1-wave5-w5.9**, protocol/save/content/
worldgen **7/4/1/2**, with stored worldgen v1 supported. It includes private
authoritative HOST/JOIN multiplayer, independent characters/resources/survival,
voxel replication, crafting/storage/Kiln, reconnect and HOST-owned save/recovery.
W6.1 adds responsive inventory/Manual UI, authoritative feedback and the targeted
long-frame drop-follow repair. Its complete automated certification belongs to
`16d6ccd2da86a0f71d2929e18caa373c0206d48b`; later documentation and pre-existing
working-tree changes are not newly source-certified.

On 2026-10-16 the owner reported W5.9 two-computer LAN success and approved
Wave 6 progression. [Wave 5 is closed under LAN-first scope](docs/WAVE_5_CLOSURE.md),
with missing manual checklist details recorded; WAN remains deferred to Wave 17.
On 2026-10-18 the owner accepted W6.1 at that published commit: all 9/9 UI checks
PASS, no reported blocking defects. See [W6.1 closure](docs/WAVE_6_PART_1_CLOSURE.md)
for separate automated/owner evidence and [W5.9](docs/WAVE_5_PART_9_FINAL_LOCAL_LAN_MULTIPLAYER_CERTIFICATION.md)
for retained launch contracts. The [W6.2 Forge foundation specification](docs/WAVE_6_PART_2_FORGE_FOUNDATION.md)
awaits owner approval; no Forge implementation or W6.2 harness has begun.

The connected playable loop and controls remain in
docs/WAVE_4_SURVIVAL_AND_CREATION.md. Held gathering, Dense Stone unit cubes,
generated voxel trees, placeable Heartwood, grounded drops and unified 2x2
Inventory / 3x3 Workbench crafting remain documented in the Wave 4 hotfix and
repair records. New worlds use worldgen v2; existing v1 worlds retain their
original generation. Wave 0–4 regression gates remain active.
