# Wave 5 to Wave 6 readiness handoff

Readiness handoff, updated 2026-10-16. [Wave 5 is closed for owner-authorized
LAN-first progression](WAVE_5_CLOSURE.md); its historical record is unchanged.
The owner has now authorized W6.1 implementation only. The [W6.1 specification](WAVE_6_PART_1_READINESS_UI_AND_INTEGRATION_FOUNDATION.md)
records the UI candidate, retained architecture contracts, future equipment
proposals and owner-established Forge-first W6.2–W6.18 sequence. Certification
and owner UI acceptance remain separate. Direct WAN stays deferred to Wave 17.

## Stable interfaces to preserve

| Interface | Canonical owner and contract |
| --- | --- |
| World-local character records | `LfeGameplayAuthority` / `LfePlayerCharacter`; durable UUID identifies a character in one world; live transport peers are ephemeral |
| Voxel generation and overrides | `LfeWave1TerrainGenerator` + `LfeVoxelOverrideStore`; authenticated HOST seed/stored generator version; sparse HOST edits overlay deterministic base |
| Chunk streaming/relevance | Real `VoxelTerrain` and per-actor `VoxelViewer`; HOST remote collision interest is independent of HOST camera; per-destination relevance/readiness |
| Resources/items/commands | `LfeResourceTransactions`, canonical item primitives and actor-bound scene adapter; validate current revisions/context/range before one commit; bounded idempotent retries |
| Canonical content | `content/` through existing block/item/recipe/source registries; game and Forge share one definition |
| Replication | `LfeNetworkSession` owns ENet/auth/transport; movement, voxel, resource and survival codecs own exact bounded packets; client replicas are disposable views |
| Persistence/recovery | `LfeWorldSave` v4 full graph, checksum and primary/pending/previous policy; only HOST saves; failures block graceful shutdown |
| Client lifecycle | Fence input immediately on HOST loss, remove the entire joined world, rebuild fresh protocols/replicas on explicit reconnect; no migration/offline continuation |
| Biology/world clocks | HOST advances one world/Kiln tick, then each active actor's independent survival; absent characters freeze |
| Verification | Fixed shutdown-safe Godot pair, source/runner manifests, isolated profiles, separate graphical OS processes, physical input/UI probes and append-only receipts |

Application candidate is 0.6.1-wave5-w5.9; protocol 7, save/content/worldgen
4/1/2, stored worldgen v1 supported. Source paths and current signatures must
be read before extending them. Completion status comes from the final W5.9
gate and subsequent [owner closure record](WAVE_5_CLOSURE.md), not this handoff.

## Hazards for the next production stages

| Future area | Required architectural care |
| --- | --- |
| Biomes | Persist generator/content compatibility; never reinterpret old seeds or stored version-1 worlds silently |
| Water | HOST owns flow/resource truth; bounded replication, collision/readiness and durable state must be designed before a client visual becomes gameplay |
| Caves/geology | Generation threads consume immutable/correctly locked inputs; loaded collision and saved sparse edits must agree across negative chunk boundaries |
| Ecology/flora | Stable world-local identities, finite resources and persistence; no player-count multiplication or HOST-camera-dependent simulation |
| Creatures | HOST simulation and actor validation, relevance/cleanup, durable identity, bounded snapshots; client presentation cannot become an entity authority |
| Time/weather | One authoritative world clock, explicit save semantics and per-actor shelter/biology; no wall-clock/offline award inferred from current clocks |
| Farming | Conserved input/output transformations, stable plot/entity identity, once-per-world tick and save/recovery parity |
| Forge tooling | Edit the same canonical registries; validate compatibility/hash changes; do not create parallel runtime content or speculative infrastructure |
| New UI | Normal crosshair/RMB/E, actual GUI pointer dispatch, independent reliable state/result channels and full readiness must be tested end to end |
| Replication expansion | Respect packet/queue/transfer bounds and all actor interest sets; explain a wire break before changing protocol; retain secret hygiene |

Current authority is a private cooperative HOST, not a dedicated server or
strong account system. ENet gameplay is unencrypted. Online NAT/relay/discovery,
secure transport, internet-scale testing and dedicated/headless pathways belong
to Wave 17. High-player-count performance must be measured before claims.

See the [W5.9 gate and owner form](WAVE_5_PART_9_FINAL_LOCAL_LAN_MULTIPLAYER_CERTIFICATION.md)
and [scope amendment](WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md).
