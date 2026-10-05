# Wave 5, Part 4 â€” Authoritative voxel world

Build: **0.5.5-wave5-w5.4**, network protocol **3**. Save/content/current worldgen remain **4/1/2**; stored worldgen v1 is supported. W5.1â€“W5.3 are AUTOMATED CERTIFIED + OWNER ACCEPTED at their recorded versions/SHAs. W5.4 is **AUTOMATED CERTIFIED + OWNER ACCEPTED** at SHA **275615fb9a7032d56f868fe7853fb7e82470c937**. Owner testing confirmed shared edits, client harvesting and the edited-block collision/jitter fix. Physical drops and inventory remained W5.5 work; survival remained W5.6 work. Wave 5 remains in progress.

## Authority and sparse terrain

HOST owns the only authoritative voxel world and save. JOIN generates the deterministic base from the authenticated seed/worldgen and overlays a session-only LfeVoxelOverrideStore. The generator and loaded VoxelTool use that same store. JOIN never opens LfeWorldSave or LfeGameplayAuthority and never writes world.json or chunk files. Exit discards the replica; reconnect starts a fresh synchronization.

Every local mining, placement and remote voxel-harvest completion reaches LeyforgeWave1Playground._commit_voxel. It validates the canonical block, cell and loaded terrain, records through LfeWorldSave.record_voxel_edit, updates HOST's real VoxelTerrain, and queues replication. Existing break/placement transactions handle conserved outputs, inventory consumption and functional object add/remove synchronously around that commit. Replication flushes later, so clients receive facts after the authoritative transaction. Development voxel edits also use this seam. Normal blocks and trees remain voxel cells; there are no fake replicated block Nodes.

## Buckets, revisions and packets

LfeVoxelOverrideStore's **16Ã—16Ã—16** buckets are the network partition. Shared helpers own floor division (including negative coordinates), bucket origins/AABBs, sorted snapshots and atomic replacement. Persisted initial buckets have transient revision **0**. Every commit advances its bucket revision; revisions are never saved. Empty touched buckets remain known for base restoration.

Reliable ordered delta batches flush at a maximum **20 Hz**; HOST mutation is immediate. Each batch has bucket, from_revision, to_revision and up to **8** distinct final canonical cell states. Same-cell edits collapse within a flush while the complete revision interval still advances. Large bursts use bounded replacement snapshots. A gap never publishes a partial delta; JOIN requests resync.

| Channel | Family | Mode |
| --- | --- | --- |
| 1 | movement input | unreliable ordered, 30 Hz |
| 2 | movement snapshots | unreliable ordered, 20 Hz |
| 3 | movement bootstrap/presence | reliable ordered |
| 4 | voxel sync, snapshots and delta batches | reliable ordered |
| 5 | harvest intent/results, resync and sync acknowledgments | reliable ordered |

ENet allocates six channels, including reserved channel 0. LfeNetworkSession remains the sole transport owner; no gameplay RPC or replication Nodes are introduced. Protocol-2 W5.3 clients reject with protocol_mismatch before build comparison.

## Complete bounded snapshots

A snapshot describes the **complete sparse contents of one bucket** at a declared revision. Its SHA-256 hashes normalized arrays containing bucket coordinates, integer revision and lexicographically sorted canonical entries. Dictionary insertion order has no effect.

Transfer uses begin, indexed parts and completion. Limits are **4096 entries**, **8 entries per part**, **512 parts**, **1200 UTF-8 bytes per packet**, **4 simultaneous receiver transfers**, a **5-second transfer timeout**, **4096 cached bucket revisions**, and **65536 session override entries**. Per-peer sync pumping sends at most **8 packets per physics frame**. A whole synchronization has a bounded 60-second deadline. Limits fail closed; this is a bounded first multiplayer proof.

Identical duplicate parts are idempotent. Conflicting duplicates, missing indices, wrong bucket entries, malformed fields, oversized packets or a bad hash never publish state. Bounded round-robin resync retries request clean authoritative snapshots at 4 Hz; HOST limits them to 5 Hz and current authoritative interest. JSON is the only decoder; Object decoding is disabled.

The replacement validates before taking the store's generator lock and replaces the bucket atomically. Omitted old overrides disappear. JOIN restores their loaded cells to generated base. Deltas whose resulting block equals generated base also remove the sparse entry. Loaded edits call VoxelTool.set_voxel so mesh and collision rebuild; edits racing chunk generation remain queued until that region is editable. Unloaded edits are available to future generator callbacks.

## Interest and initial readiness

HOST uses each authenticated remote body's authoritative position, independently of the HOST camera. Bucket AABBs intersect a **96 m** sphere, covering the **80 m** viewer with prefetch margin. Only touched sparse buckets in that interest are supplied. An empty fresh region uses a zero-snapshot transaction; generated base cells are never transmitted.

Per-peer knowledge records supplied revisions. Irrelevant peers receive no edit broadcast. Approaching a new or stale bucket causes a complete current snapshot, including empty replacements for reverted buckets. Cached HOST knowledge is pruned outside interest at its bound. Reliable transfers and current revision comparisons protect returning peers.

JOIN progresses through Connected, Synchronizing world and World synchronized. Explicit sync begin/count, snapshots, completion and acknowledgment determine logical readiness. The server revisits buckets edited during transfer and extends the declared count for newly touched relevant buckets before completing the barrier. Movement waits for the initial sparse transaction, loaded cell application and streamed spawn collision, including settle frames. Authentication or movement bootstrap alone cannot enable it. Later resync keeps the server running and uses the same bounded recovery path. An incomplete transfer, pending resync or unapplied cell within 8 m suppresses only JOIN movement/action controls; gravity and look continue. Far transfers do not interrupt movement. A stalled nearby wait closes the session after 10 seconds. Receiver cache overflow also closes cleanly before publication.

Safe retained remote transforms may be airborne above a landing surface within 4 m; reconnect restores the exact transform before normal gravity resumes. Embedded, unsupported or occupied positions still use safe fallback. Fresh-character spawn searches retain immediate floor support.

W5.3 interpolation remains approximately 100 ms. Voxel traffic uses separate channels. Reconciliation preserves newer local look changes, including changes that have not yet been sent, so an older movement acknowledgment cannot erase aiming input.

## Held remote voxel harvesting

JOIN holds LMB against real voxel targets. It sends only kind=voxel_harvest_state, action_sequence, active, target_cell and expected_block. No actor, resulting voxel, resource quantity, capability, progress or position is accepted. HOST resolves peer_id â†’ player_id using the authenticated binding.

HOST and local voxel gathering share actor-addressed transient work, canonical harvest rules and one completion/output transformation. A remote attempt is renewed at **10 Hz** with a **300 ms** hold lease. Release, target/block/tool change, range/occlusion, not-ready/dead state, disconnect or lost renewal cancels work. Partial work is discarded. A quick tap cannot break a block. Action sequences are bounded and stale/replayed packets cannot commit twice; remote action rate is bounded to 30/s with a burst of 8.

HOST reconstructs the eye from authoritative feet + **1.62 m**, yaw and pitch, without a camera. It validates the actual voxel ray, finite-source occlusion, the shared **6 m** interaction range, loaded terrain, expected canonical block, breakability, structure removal, actor survival and the correct actor's HOST-owned tool/capability/durability. Grass/Dirt/Sand and canonically capability-0 tree cells can be harvested with bare hands. Default Client 2 cannot mine Stone.

Completion revalidates the same cell and tool and performs the existing Wave 4 break_to_drop transaction. Exactly one contender succeeds; the other becomes stale. Normal HOST drops and tool wear remain authoritative, with no arbitrary direct award to Client inventory. JOIN does not predict removal: only the authoritative delta/snapshot changes its voxel. Bounded feedback gives accepted, cancelled, stale_state, out_of_range, blocked, tool_required, completed or not_ready and progress.

## Owner commands and acceptance

Run in two ordinary PowerShell windows. Both exact launchers use the existing serialized import-first mechanism and approved shutdown-fixed console/editor pair. No cache deletion is required.

HOST:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_4_host.ps1'
~~~

Defaults: world wave5-w54-owner-test, seed 184552221, port 25652, canonical owner identity.

CLIENT / JOIN:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_4_join.ps1'
~~~

Defaults: 127.0.0.1:25652, **user://identity/development/wave5-client-2.json**, the exact stable identity used in W5.2/W5.3.

1. Confirm synchronization completes, both players move and see each other.
2. HOST breaks nearby Dirt/Grass. JOIN sees removal and walks through it without repeated edited-block correction/jitter.
3. HOST gathers a legitimate placeable block and places it. JOIN sees it and its rebuilt collision blocks movement.
4. JOIN holds LMB on Dirt/Grass: quick tap does not complete; release cancels; a full hold removes the cell for both players.
5. Default Client 2 targets Stone: tool_required feedback, no fake break.
6. Harvest a real Oak Heartwood cell and check both voxel worlds agree.
7. Close only JOIN, make another HOST edit, rerun the exact JOIN launcher. The same identity/character receives all current relevant edits.
8. Save/quit HOST and restart both exact launchers. Saved overrides and collision synchronize again.

Expected now: movement/presence, HOST break/place/tree edits, persisted sparse edits, valid capability-0 client voxel harvest, and collision parity after authoritative edits.

Still deferred: client placement from inventory; physical drops/pickup; inventory/hotbar/equipment/tool UI; finite sources including Dense Stone and caches; crafting/Workbench/storage/kiln; Rest Mat/Lamp function state; health/stamina/food/water/fatigue/exposure and survival HUD. Those are W5.5/W5.6. A harvested drop may exist visibly on HOST while JOIN sees only the changed voxel.

## Automated qualification

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\verify_wave_5_part_4.ps1'
~~~

Append-only evidence: .verification/wave5/w5_4/run-<UTC>/. Failed and uncertified runs remain retained. The gate uses an external disposable project and isolated process userdata. It records source hashes, focused schemas/hashes/fragmentation/corruption/base restore, rendered ENet HOST/JOIN/third-player logs, initial/live/action/collision/reconciliation/relevance/resync traces, reconnect, save/reload, exact graphical launcher proof from a fresh class cache and the complete W5.3â†’W5.2â†’W5.1â†’Wave 0â€“4 regression chain. SkipRegression is explicitly uncertified. The jitter proof identifies an untouched generated capability-0 step outside the edited fixture, withholds voxel delivery to reproduce the stale collider, restores authoritative state and verifies real predicted feet enter that formerly solid cell. Cell-local physics probes avoid mistaking an adjacent natural block for the tested collider.

Certification refers to the publishable source projection, excluding unrelated pre-existing editor hunks and generated UID files. Those local bytes are preserved independently; only the W5.4 version hunk in project.godot belongs to publication. Unchanged files use canonical HEAD blob bytes, including Git LF normalization; raw working-copy bytes are pinned separately without rewriting them. Final source hashes must match the published tree.

This stage certifies loopback only. No LAN/WAN, UPnP, relay, matchmaking, dedicated server, host migration or PvP is introduced. W5.5 has not begun.
