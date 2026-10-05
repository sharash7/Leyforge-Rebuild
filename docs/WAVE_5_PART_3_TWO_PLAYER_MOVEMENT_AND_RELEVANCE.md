# Wave 5, Part 3 — Two-player movement and relevance

Build: **0.5.4-wave5-w5.3**, network protocol **2**. Save/content/current worldgen remain **4/1/2**; stored worldgen v1 remains supported.
W5.1 and W5.2 are AUTOMATED CERTIFIED + OWNER ACCEPTED at their recorded accepted SHAs.
W5.3 owner manual acceptance is pending. Wave 5 remains in progress; W5.4 is outside this implementation.

## Authority and transport

Clients send input, never an authoritative position, velocity, grounded flag, actor ID or gameplay state.
The host resolves each packet's transport peer through W5.2's authenticated peer-to-player binding.
The strict eight-field input contains kind, sequence, move_x, move_z, jump_pressed, sprint_requested, yaw and pitch.
Yaw is normalized to [-pi,pi), pitch is bounded to the existing 89-degree controller limit, and movement magnitude is at most one.
Sequences are positive session-local integers up to 2147483647. Duplicate/stale inputs and advances above 1024 are rejected; reconnect starts a fresh sequence.
Malformed, oversized, non-finite, foreign-field or unbound-peer packets are dropped without physical mutation.

LfeNetworkSession continues owning SceneMultiplayer, ENet construction, authentication and transport lifecycle.
Its send_packet/packet_received seam uses SceneMultiplayer.send_bytes/peer_packet after authentication.
No gameplay RPC, replication Node or transport construction exists in player code.
LfeMovementProtocol is the single canonical codec under src/lfe/networking/.
It uses bounded UTF-8 JSON, exact fields, no Object decoding, at most eight distinct player states and an 8192-byte ceiling.
Input packets are measured by focused qualification; the largest eight-player snapshot is tested below that ceiling.

| Channel | Packet family | Mode | Timing |
| --- | --- | --- | --- |
| 1 | movement_input | UNRELIABLE_ORDERED | 30 Hz |
| 2 | movement_snapshot | UNRELIABLE_ORDERED | 20 Hz |
| 3 | movement_bootstrap, presence_enter, presence_leave | RELIABLE | On change |

Normal authoritative and predicted physics remains 60 Hz. A monotonic server physics tick orders snapshots.
Each state includes player_id, position, velocity, yaw, pitch, grounded and last processed input sequence (ack).
Callbacks validate and store bounded state; physical mutation runs in physics processing.
A 250 ms valid-input hold timeout clears horizontal intent and sprint. Gravity and collision continue.
Jump presses are latched across packet delivery and consumed once, so holding the last packet does not repeat jumps.

## Shared movement and bodies

LeyforgeMovementRules under src/game/player/ owns walk/sprint speed, ground/air acceleration,
deceleration, jump velocity, gravity integration and move_and_slide.
The existing host first-person controller retains survival permission, falling damage and normal Wave 4 interactions.
The same equations drive the client predicted body and each host authoritative remote body.
The host local player moves directly inside authority; it does not send input through a localhost loop.

Each admitted remote character gets a real CharacterBody3D, collision capsule and VoxelViewer at its
authoritative position, with no camera, local input polling or HUD.
The host sees that body's blocky avatar at physics frequency.
Durable character transform updates come only from this body. Before save, all active bodies synchronize into save v4.
Disconnect finalizes the transform, removes body/avatar/viewer/live binding and retains the character and all personal data.
Reconnect reuses the record and saved position. A bounded safe fallback handles unsupported/solid/occupied positions.
New physical spawns search generated terrain and voxel overrides, active body bounds and finite source collision.

Named bit masks in LfeVoxelInteractionRules are WORLD_PHYSICAL_LAYER=1, FINITE_SOURCE_LAYER=8,
PLAYER_BODY_LAYER=16. Player masks include terrain and finite sources, exclude player bodies.
Players pass through each other; no pushing, blocking or PvP is introduced.
Avatars have blocky head, torso and limbs plus a short diagnostic identity label, without final character art.

## JOIN presentation and prediction

After authentication, reliable bootstrap supplies the client's own authoritative state and relevant players.
JOIN builds the normal visual environment, canonical catalog, VoxelTerrain and deterministic generator using
the authenticated host seed and stored worldgen version. It opens no LfeWorldSave, LfeGameplayAuthority,
inventory or survival owner. Its viewer follows the predicted first-person body.

The body responds to local movement input immediately using the shared rules.
Snapshots reconcile position and velocity; acknowledged orientation is applied without rewinding newer local look input.
Error above 0.08 metres receives 35% correction per snapshot; error at or above 3 metres snaps decisively.
At rest, tiny residual error is removed. Packet tick and processed input sequence reject stale state.
This is client prediction plus authoritative reconciliation, without rollback or unacknowledged-input replay.

Remote presentation retains at most eight samples, interpolates approximately 100 ms behind the server's 60 Hz tick,
and stops at the latest sample rather than extrapolating indefinitely.
Server disconnect disables local prediction, removes avatars and shows Disconnected/server_disconnected.
I/C/E/F/Q/F5 and block interaction actions cannot mutate fake client gameplay; F10/window close leaves without saving.

## Presence and voxel interest

Player presence enters at **96 m**, leaves above **128 m**, and uses authoritative positions.
Each destination peer has its own relevance set; self is always included.
Bootstrap and reliable enter packets include initial state. Reliable leave removes presentation.
A per-destination presence epoch accompanies snapshots, preventing delayed unreliable data from reviving removed avatars.
Snapshots contain only self plus relevant players, bounded to the session's eight-player limit.
The host uses the same hysteresis for avatar visibility, independently of remote simulation and streaming.

Each server remote viewer requests collision terrain with an 80 m view distance; the host's local viewer also uses 80 m.
Remote interest remains active when its avatar leaves visual relevance.
The client viewer requests its own generated base terrain and prediction collisions.
W5.3 intentionally does not synchronize voxel overrides or finite source depletion/collision changes.
The host's actual collision result wins reconciliation. Voxel-delta prediction parity begins in W5.4.
Use a fresh movement-safe area for manual testing and avoid editing it while assessing parity.

## Owner commands

Run in two ordinary PowerShell windows. The launchers reuse W5.2's import-first mechanism and shared project mutex.
They do not delete saves, caches or identities. The fixed console runner imports classes; its adjacent graphical runner opens the game.

HOST:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_3_host.ps1'
~~~

Defaults: world wave5-w53-owner-test, seed 184552221, port 25652, canonical owner profile.

CLIENT / JOIN:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_3_join.ps1'
~~~

Defaults: 127.0.0.1:25652 and user://identity/development/wave5-client-2.json.
This is the same durable Client 2 identity used by W5.2.

Both players can walk, sprint, jump and look. Each sees the other when relevant.
Open host Inventory while Client 2 moves; simulation and packets continue.
Move Client 2, close its window, then rerun JOIN: the same character returns at its last authoritative position.
F5/F10/normal host close includes all connected remote transforms in the host save.
Owner acceptance is separate from automated qualification.

## Verification

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\verify_wave_5_part_3.ps1'
~~~

The gate retains append-only .verification/wave5/w5_3/run-<UTC>/ receipts, failed runs, source hashes,
focused codec/authority results, separate rendered host/client/third-process logs,
movement/reconciliation/relevance traces, reconnect/save/reload evidence and exact graphical launcher receipts.
It certifies only when W5.3, W5.2 and the complete Wave 0–4/W5.1 regressions pass and final source matches the snapshot.
SkipRegression explicitly produces an uncertified receipt.

The remote-streaming probe moves the host's actual viewer to a safe generated position over 128 m from the remote body,
then continues real client-input-driven remote walking without teleporting the remote body.
It checks loaded collision terrain, authoritative movement, viewer existence, reliable leave with snapshots suppressed,
no thrashing in the hysteresis gap and reliable re-entry. A distinct third identity verifies independent bodies/input and
per-destination relevance. Drift injection changes only the predicted client body, and the host must stay unchanged.

## Limits

No voxel-edit, item/resource, crafting or survival replication; no gameplay RPC.
No LAN certification, WAN, UPnP, relay, dedicated server, host migration or PvP.
No regional servers, sharding, cross-server transfer or distributed authority.
W5.4 authoritative voxel replication has not begun.