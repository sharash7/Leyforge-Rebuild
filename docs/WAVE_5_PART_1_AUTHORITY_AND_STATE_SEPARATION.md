# Wave 5, Part 1 — Authority and state separation

Production version: 0.5.0-wave5-w5.1. W5.1 preserves the normal Wave 4 single-player loop while separating installation identity, world-local characters and shared world state. Automated qualification and owner manual acceptance are separate; owner acceptance remains pending. W5.2 has not begun.

## Installation identity

LfeLocalProfile creates user://profile.json once using 16 cryptographically random bytes. Its strict schema is:

~~~json
{"profile_version": 1, "player_id": "32 lowercase hexadecimal characters"}
~~~

The profile contains no world state, character progress or login credentials. Each world stores a separate character under this ID. Repeated opens and fresh processes reuse it. Existing malformed, unreadable or oversized profiles fail startup with an explicit error and retain their bytes; they never silently generate another identity. First creation writes, flushes and validates a pending file before promotion. A valid interrupted pending file recovers the same ID; a malformed pending file remains available for recovery. Preserve this file when moving an installation whose existing characters should remain associated with it.

## Runtime ownership

LfeGameplayAuthority owns the character roster, LfeWorldResourceState, LfeCreationState, the shared voxel override reference, and transient crafting contexts keyed by actor. It is reusable LFE state under src/lfe/; the Leyforge scene supplies streamed voxel targeting, collision, placement, shelter and presentation.

LfePlayerCharacter owns the world-local player ID, position/yaw/pitch and legacy selected-block compatibility field; 27 backpack slots including the nine-slot hotbar and selected hotbar index; equipment hand/body slots; health, stamina, hunger, thirst, fatigue and legacy exposure; and health/stamina recovery delay plus starvation/dehydration timing. Tools retain their instance ID and exact durability. Its resources and survival do not depend on the controller Node lifetime.

Shared world state owns seed/generation metadata and owner identity; sparse voxel overrides; physical resource drops and the origin crate; constructed object identity/cell/orientation, constructed storage slots and workstation input/fuel/output; active process recipe/progress/reservation; finite source identities, positions and remaining stock; source initialization and world simulation elapsed time. Survival is absent from shared creation state. Transient crafting staging is actor-owned but must be returned before the normal save path can proceed.

The local controller associates with its profile's character, restoring that record or admitting a new empty character at the existing bounded safe-spawn seam. Opening an existing world under another profile preserves the original owner and other characters. The roster is capped at 64; it does not clone another player's inventory. Inactive characters do not receive biology ticks. Shared workstation/world time advances separately from explicitly addressed character survival time, with no offline elapsed-time award.

## Save v4

The checksum envelope still contains save_version, payload_json and sha256. The v4 payload is:

~~~text
metadata:
  world_id, owner_player_id, display_name, seed,
  save_version=4, worldgen_version, content_version,
  created_utc, last_saved_utc
players:                         # sorted by player_id
  - player_id
    transform: position, yaw, pitch, selected_block
    resources: inventory, equipment, hotbar_selected
    survival: health, stamina, hunger, thirst, fatigue, exposure, timing
voxel_overrides
world_resources: drops, storage  # shared origin crate
creation: objects, sources, initialized, elapsed
~~~

Restore validates every character, shared container, bounded quantity, identity, transform and functional-object/voxel association before publishing state. The owner must occur in the roster. Duplicate player IDs, malformed records and tool-instance duplication across all characters, drops, the origin crate, constructed storage and station inventories are rejected. Entity/source/tool identities are checked together. Files larger than 16 MiB are rejected.

The existing pending-write, flush, readback/checksum, previous-copy rotation and promotion path is retained. Save refuses external authoritative-byte changes or disappearance since load. Missing-primary recovery loads the previous valid copy; a corrupt primary remains authoritative evidence and is not silently replaced. Dirty comparison covers the complete roster and both shared snapshots.

## Historical migration

v1 supplies the historical transform and sparse edits, with safe empty personal/shared resource and survival defaults. v2 splits its mixed resource snapshot into personal inventory/equipment/hotbar and shared drops/storage, retaining quantities and identities. v3 additionally splits survival from creation while retaining timing, constructed objects, containers, kiln reservation/progress and finite source state.

The implicit historical character and initial owner are assigned to the local profile performing migration. Opening migrates in memory without rewriting the original. An explicit save emits v4 and retains the exact historical bytes as world.json.previous. Historical worldgen v1 remains v1; this change does not regenerate its sources or terrain. Both multi-character v4 state and migrated state are verified through fresh process restarts.

## Actor command seam

LeyforgeWave1Playground.command(actor, operation, args) and reusable LfeGameplayAuthority.execute(actor, operation, args) return LfeCommandResult with success, stable reason_code and operation-specific data. Unknown actors fail with invalid_actor before mutation. The local scene submits its stable profile identity directly; UI slot movement resolves actor-owned endpoint names again at commit.

Actor-addressed operations cover selection, pickup/drop, transfer/swap, crafting/context release, process start, consumption, damage/recovery and survival advancement. Voxel/source gathering, placement and rest use the live scene adapter, retaining actual streamed-world validation. The live controller's voxel operations require its materialized local actor; inactive character records do not imply remote controllers. Range and context checks use that actor's transform. Foreign personal endpoints cannot be named through another actor's command. Stale expected stacks fail with stale_state; unavailable contexts, capacity and resource failures return structured reasons. A valid incomplete harvest reports success with completed=false; a completed operation reports completed=true.

Held LMB remains mandatory: release, retarget, tool instance/capability change, range, occlusion, unloading, death, menu or stale voxel/source cancels accumulated work. Completion revalidates the same actor/target/tool and commits one output and one wear, then clears work; excess time cannot duplicate completion.

## Conservation

authority.total(content) includes every character's inventory/equipment, all actor staging grids, shared drops/crate, constructed storage, station inventories, active input reservations and recoverable placed material. Functional objects count once despite having a corresponding voxel. Preview outputs are absent from totals. Canonical recipe transformations and consumed fuel remain explicit ledger transformations.

Test-only views in tests/support/ adapt retained historical fixtures to separated production owners; they contain no second gameplay transaction implementation. Earlier-wave assertions remain active. W5.1 adds cross-player inventory/equipment independence, foreign/unknown actor rejection, shared movement, durable-instance anti-duplication in every container family, independent crafting, deterministic 300-step conservation, record bounds and tick isolation.

## Verification and evidence

Run the complete isolated gate:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_5_part_1.ps1
~~~

It snapshots source bytes into an external disposable project, isolates profile/world storage, uses the approved fixed Godot console runner, and writes append-only evidence below .verification/wave5/w5_1/run-<UTC>/. A certified receipt requires focused tests, a genuine separate-process restart, ten rendered processes, all Wave 0–4 gates, and unchanged source hashes. Skip options explicitly produce an uncertified receipt. Normal rendered candidates use Standard production survival timing.

Rendered coverage retains the full Wave 4 connected loop, physical drops, held gathering cancellation, both crafting grid sizes, storage and tool durability, construction/rest, kiln process persistence/completion, world isolation and v1/v2 migration. It adds a copied rich v3 migration and v4 restart. Screenshots, individual phase JSON/logs, regression receipts and source_manifest.json are retained with gate.json; failed earlier runs are preserved.

## Qualified run

The complete gate passed on 2026-10-04, with evidence at
.verification/wave5/w5_1/run-20261004T120718132/. Its receipt records
passed=true, certified=true, regressions=true and snapshot_matches_source=true.

| Gate | Focused checks | Rendered checks |
| --- | ---: | ---: |
| Wave 0 | 1 qualification gate: import + startup, 2 required readiness markers | — |
| Wave 1 | 50 | 23 |
| Wave 2 | 84 | 127 |
| Wave 3 | 432 | 159 |
| Wave 4 | 979 | 1,726 |
| W5.1 | 507 + 7 in a separate restart process | 1,884 across 10 processes |

The W5.1 evidence contains 27 nonempty screenshots (the two drop-motion frames
share prefix 12), complete source hashes, focused/restart reports, ten phase
reports/logs and all earlier-wave regression receipts. The retained Wave 4
regression uses its skip-regression option because the enclosing W5.1 gate
already runs Wave 0–3; its own receipt is intentionally uncertified in
isolation. The enclosing complete W5.1 receipt is certified. These automated
results do not claim owner manual acceptance.

## Owner manual launch and limits

From PowerShell, launch the approved graphical runner with a fresh owner test world:

~~~powershell
& 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.exe' --path 'D:\AI\Projects\Leyforge-Rebuild' -- --world-id=wave5-w51-owner-test --seed=184552221
~~~

The usual Wave 4 controls and progression apply. Hold LMB to gather, use the existing Inventory/Workbench and kiln UI, save, close and rerun the same command to check continuation. This uses the normal installation profile and persistent local world, not accelerated verification flags.

There is no ENet, RPC, host/join UI, LAN, WAN, remote player controller or dedicated server. This establishes durable owners and actor commands only. It adds no network authentication, transport/session protocol, account system or new gameplay subsystem. Owner manual acceptance is pending and W5.2 remains outside this implementation.
