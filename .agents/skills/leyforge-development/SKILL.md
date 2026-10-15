---
name: leyforge-development
description: Implement or repair an owner-authorized Leyforge component or stage; locate relevant code and contracts while preserving existing architecture and task scope.
---

# Leyforge development

Use root [AGENTS.md](../../../AGENTS.md) for production, runtime and preservation rules.

1. Confirm the requested repository, branch, starting SHA and index/worktree state. Resolve an authority mismatch before editing. State the authorized behavior and exclusions; a roadmap entry is not authorization.
2. Read the task's stage specification, then search the affected implementation and callers with scoped `rg` queries. Read relevant ranges and existing tests before designing a change. Reuse paths already established in this chat while rechecking mutable Git state.
3. Route only where needed:
   - Ownership or file placement: [architecture boundaries](../../../docs/ARCHITECTURE_BOUNDARIES.md).
   - Content changes: existing registries under `src/lfe/content/` and their canonical inputs under `content/`; inspect consumers rather than inventing parallel definitions.
   - Generation, persistence or network interfaces: the applicable stage/ADR and [readiness handoff](../../../docs/WAVE_5_TO_WAVE_6_READINESS_HANDOFF.md), especially stored generator versions and HOST/JOIN ownership.
4. Implement the smallest coherent change in the existing owner. Add abstractions only for demonstrated reuse. Inspect current signatures and actual runtime/plugin capabilities before adopting external examples; suggestions in research notes are not approved dependencies.
5. Select checks with `$leyforge-verification`. Finish with behavior changed, checks/results and evidence paths, remaining limitations and publication status. Keep detailed logs in evidence files.
