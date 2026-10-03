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

Wave 3 - Stuff Exists is the current implemented slice: deterministic streamed voxel
terrain, first-person movement, conserved physical drops and pickup, a real player
inventory and nine-slot hotbar, inventory-backed placement, persistent storage,
equipment-state foundation, and save v2 with nondestructive Wave 2 v1 migration.

See `docs/WAVE_3_STUFF_EXISTS.md` for the connected resource loop, controls,
architecture, verification and limits. Waves 1 and 2 remain covered by their
existing regression gates and documentation. Wave 4 crafting, tools, processing
and survival remain the next planning boundary.
