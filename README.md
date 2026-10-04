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

The current build is 0.5.1-wave5-w5.1: W5.1 Authority & State Separation
preserves the normal Wave 4 survival/creation loop while adding a stable local
profile, independent world-local character records, shared world owners and
actor-aware commands. Identity lives at user://identity/local_profile.json;
the owner launcher imports global classes before starting the graphical game.
Historical generic profile data remains intact. Save v4 retains nondestructive
v1/v2/v3 migration and
the existing safe promotion and previous-copy recovery path.

See docs/WAVE_5_PART_1_AUTHORITY_AND_STATE_SEPARATION.md for identity,
ownership, save shape, command boundaries, verification and the exact owner
manual launch command. W5.1 owner manual acceptance is pending. It introduces
no networking; W5.2 has not begun.

The connected playable loop and controls remain in
docs/WAVE_4_SURVIVAL_AND_CREATION.md. Held gathering, Dense Stone unit cubes,
generated voxel trees, placeable Heartwood, grounded drops and unified 2x2
Inventory / 3x3 Workbench crafting remain documented in the Wave 4 hotfix and
repair records. New worlds use worldgen v2; existing v1 worlds retain their
original generation. Wave 0–4 regression gates remain active.
