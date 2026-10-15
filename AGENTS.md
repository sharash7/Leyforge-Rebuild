# AGENTS.md — Leyforge Production Rules

This repository is the clean production implementation of Leyforge.

Focus on the game. Do not recreate Project Brain, work-record, task-contract, evidence-governance, admission-gate or mirrored documentation systems.

## Core rules

1. **One repo, one canonical implementation.**
   No duplicate source trees, project clones, shadow registries or parallel canonical copies inside this repository.

2. **Build only what current gameplay or tooling needs.**
   Avoid speculative frameworks and empty abstractions.

3. **Breadth first within the authorized Showcase stage.**
   Establish playable pillars before content completeness.

4. **Depth is allowed when it pays off.**
   Deepen work for playability, proven architecture, reusable LFE/Forge capability or cross-system benefit.

5. **LFE follows real runtime needs.**
   `src/lfe/` owns reusable runtime infrastructure; `src/game/` owns Leyforge gameplay/presentation.

6. **Forge-ENG supports actual authoring needs.**
   `src/forge_eng/` owns reusable authoring/validation/import/export/compilation infrastructure needed by an actual tool.

7. **The Forge grows from actual production pain.**
   Creator tools live under `tools/forge/`; do not build the complete Forge up front.

8. **Canonical content stays canonical.**
   Game, Forge and runtime share definitions in `content/`; tools edit/generate the same blocks/items/recipes consumed at runtime.

9. **Persistence starts early.**
   Add save/load when persistent gameplay state is introduced.

10. **World generation is real from the start.**
    Use deterministic seeded generation, including for small showcase worlds.

11. **Tests protect risky foundations.**
    Test generation determinism, persistence, registries, conservation and other world-corruption risks.

12. **Preserve authoritative multiplayer.**
    Client intent -> HOST validation/commit/save -> revisioned replication -> JOIN presentation. JOIN never writes authoritative saves. Preserve world authority, identities, conservation, readiness and teardown boundaries.

13. **Keep commits understandable.**
    Prefer coherent gameplay/tooling increments over repository-wide rewrites.

## Authority and task entry

Implementation requires an explicit owner-authorized task. Plans and empty directories do not authorize implementation or the next Wave.

The authorized stage specification defines behavior/verification. Consult relevant sections of `docs/SHOWCASE_BUILD_WAVES.md`, `docs/SHOWCASE_MASTER_COVERAGE.md` and `docs/ARCHITECTURE_BOUNDARIES.md`; do not read the whole collection by default.

Use `$leyforge-development` for implementation and `$leyforge-verification` for checks/certification. Workflow/status: `docs/development/CODEX_WORKFLOW.md`.

## Runtime and preservation

- Automation: `D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe`; adjacent graphical executable only for editor/rendered runs. Never execute 4.6.3, 4.7.1 or `.exe.disabled`, including from historical instructions.
- Gates: `powershell -NoProfile -ExecutionPolicy Bypass -File ...`. Isolate writable project/profile state outside this checkout for imports or `user://`; never mutate owner saves or shared fixtures.
- Preserve unrelated changes, UID sidecars, owner identities and append-only evidence. Stage exact owned paths/hunks, commit/push only as authorized.
- Full final stage gates remain mandatory. Distinguish automated certification from owner acceptance; focused checks cannot close a Wave.
