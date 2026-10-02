# AGENTS.md — Leyforge Production Rules

## Purpose

This repository is the clean production implementation of Leyforge.

Keep implementation work focused on the game. Do not recreate the previous Project Brain, work-record, task-contract, evidence-governance, admission-gate, or mirrored documentation systems.

## Core rules

1. **One repo, one canonical implementation.**
   Do not create duplicate source trees, temporary project clones, shadow registries, or parallel "canonical" copies inside the repository.

2. **Build only what current gameplay or tooling needs.**
   Avoid speculative frameworks and empty abstraction layers.

3. **Breadth first for the Showcase Slice.**
   Establish a playable foundation across Leyforge's major pillars before attempting content-complete implementations.

4. **Depth is allowed when it pays off.**
   Continue deeper when the work materially improves playability, validates important architecture, creates reusable LFE/Forge capability, or benefits multiple systems.

5. **LFE is extracted from real runtime needs.**
   Code belongs under `src/lfe/` when it is reusable game-runtime infrastructure rather than Leyforge-specific gameplay presentation/content.

6. **Forge-ENG exists to support real authoring workflows.**
   Add functionality under `src/forge_eng/` only when a Forge/development tool actually needs reusable authoring, validation, import/export, or compilation infrastructure.

7. **The Forge grows from actual production pain.**
   Development/creator tools live under `tools/forge/`. Do not attempt to build the complete Forge up front.

8. **Canonical content stays canonical.**
   Avoid separate game, Forge and runtime definitions of the same block/item/recipe/etc. Tools edit or generate the same canonical content consumed by runtime systems.

9. **Persistence starts early.**
   Persistent gameplay state should gain save/load support when the feature is introduced rather than being retrofitted at the end.

10. **World generation is real from the start.**
    Use deterministic seed-driven generation rather than a handcrafted showcase map, even while world content is intentionally small.

11. **Tests protect risky foundations.**
    Add focused tests for deterministic generation, persistence, registries, resource conservation and other systems where regressions could corrupt or invalidate worlds.

12. **Multiplayer is a first-class future requirement.**
   Do not network every early feature immediately, but avoid single-player-only assumptions in authoritative state, identities, transactions, persistence and simulation. Add the first small multiplayer proof once the core world/player/persistence foundation is stable.

13. **Keep commits understandable.**
    Prefer coherent gameplay/tooling increments over giant repository-wide rewrites.

## First target

Do not implement advanced systems during bootstrap.

The first playable target is:

**Launch -> generate simple voxel terrain -> spawn player -> move/jump -> target voxel -> break voxel -> place voxel.**

Once that works reliably, add persistence before expanding the game loop.

## v0.3 showcase authority

Current planning authority:
1. `docs/SHOWCASE_MASTER_COVERAGE.md`
2. `docs/SHOWCASE_BUILD_WAVES.md`
3. `docs/ARCHITECTURE_BOUNDARIES.md`

These documents describe eventual showcase coverage; they do not authorize speculative implementation.

During bootstrap, implement Wave 0 only unless explicitly instructed otherwise.
The empty Forge workspace directories intentionally make future coverage visible. Do not scaffold implementations simply because those directories exist.
