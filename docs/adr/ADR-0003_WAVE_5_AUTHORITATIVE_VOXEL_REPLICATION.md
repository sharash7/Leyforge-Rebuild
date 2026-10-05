# ADR 0003 — Authoritative voxel replication

Status: adopted for W5.4, 2026-10-05.

HOST owns voxel truth and durable sparse overrides. JOIN generates deterministic base terrain locally and overlays only HOST facts in a session-only store. Existing real VoxelTerrain cells and the 16³ override-store bucket are the presentation/collision and network units.

Use transient per-bucket revisions, reliable ordered delta batches at a maximum 20 Hz, and bounded complete SHA-256 snapshots with begin/parts/completion. Replacement removes omitted old overrides and restores generated base. Logical revision gaps and failed hashes request bounded relevant resync. Loaded cell changes rebuild voxel meshes/collision; generator callbacks use the same thread-safe store.

Use authoritative remote positions for 96 m sparse interest and bounded per-peer revision knowledge. Explicit initial synchronization completes before JOIN movement is enabled. Movement/presence channels remain separate from voxel state channel 4 and action channel 5. Advance protocol to 3; retain save/content/worldgen 4/1/2 and worldgen v1 support.

Remote gathering carries held intent only, with authenticated peer-to-actor resolution, a 300 ms lease, HOST ray/range/state/tool validation and shared actor-scoped harvest rules. Local and remote completions use the canonical voxel commit and existing conserved break-to-drop transaction. JOIN waits for the authoritative result and creates no world save.

General client placement waits for visible transactional inventory in W5.5. Physical drops, inventories, equipment, finite sources, crafting, storage and kiln state wait for W5.5; survival state waits for W5.6. No LAN/WAN or dedicated server is added here.
