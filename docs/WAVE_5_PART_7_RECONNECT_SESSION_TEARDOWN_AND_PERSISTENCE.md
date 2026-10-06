# Wave 5 Part 7 — Reconnect, session teardown and persistence

Status: automated certification is determined by the final full gate receipt;
owner manual acceptance pending.
Application 0.5.9-wave5-w5.7; network protocol 6; save/content/current worldgen
4/1/2. Stored worldgen v1 remains supported. Wave 5 remains in progress.
W5.6 repair 1 is AUTOMATED CERTIFIED + OWNER ACCEPTED at
0.5.8-wave5-w5.6 / cced5167004e3056c150bbd16fee25252c665843.

## Session ownership and lifecycle

HOST owns world state, durable characters and saves. JOIN owns disposable
prediction, voxel/resource/survival views and presentation. HOST authority loss
ends the session. There is no host migration or offline continuation.

The transport distinguishes HOSTING -> CLOSING -> DISCONNECTED and
CONNECTED -> ENDING -> DISCONNECTED. Failed shutdown save returns CLOSING to
HOSTING. Connection/authentication failures retain a visible ended/failed view.
A small exact JSON codec in LFE owns lifecycle validation: reliable channel 11,
128-byte maximum, no claimed player identity, unknown fields/reasons rejected.
ENet has 12 channels including reserved channel 0; channels 1–10 keep their
movement, voxel, resource and survival responsibilities. Protocol 5 rejects
before world bootstrap with protocol_mismatch.

HOST sends a reliable heartbeat once a second. JOIN tracks authenticated,
validated HOST lifecycle and gameplay packets; five seconds without valid HOST
traffic ends the session with server_timeout. server_disconnected independently
ends it. A graceful session_closing fact uses host_shutdown. Stable failure
codes also distinguish connection_failed, auth_timeout, protocol/build mismatch
and world_mismatch. These localhost defaults are not WAN qualification.

## Graceful HOST shutdown and failure

F10 and window X reach one save-and-quit path. HOST enters CLOSING and rejects
admission/new gameplay traffic, stops local input and world/drop/remote
simulation, cancels held harvest/rest, resolves every authoritative staging
grid, synchronizes local and all remote body transforms, then captures the
complete graph and performs the atomic save. Main-thread synchronous commands
finish before this snapshot; no asynchronous mutation runs inside it. F5 uses
the same graph capture without closing transport or advancing world time.

Only a successful save starts session_closing. JOIN fences gameplay immediately,
begins teardown, and sends a small ack. HOST waits at most 350 ms, then closes
transport and exits regardless of missing acknowledgements. Closing transport
from its own poll callback remains deferred. The snapshot precedes the notice;
no post-save gameplay mutation is accepted during the acknowledgement interval.

A failed save sends no closing fact and closes no connection. HOST removes its
fence, returns to HOSTING and restores input. The owner sees the save/staging
reason. Staged crafting is first returned safely; a full backpack retains the
HOST grid, including while that player is absent, and blocks every save until
capacity/staging is resolved. This preserves resources without a save bump.

## JOIN teardown and reconnect

The original bug only froze movement and cleared some replica maps: the app
kept its VoxelTerrain, player, presenters and gameplay UI. The app now owns the
joined-world lifetime. ENDING immediately clears readiness/input/action intent,
disables gameplay nodes and hides all inventory, Manual and functional UI.
Deferred cleanup removes the terrain, player/viewer, avatars, drop/source/object
presenters and every movement/voxel/resource/survival protocol node and replica.
The old generator can finish existing jobs only against its old store. The
joined override store and pending transaction/context/resync waits are removed.
JOIN performs no authoritative save on any of these paths.

A full-screen session-ended view shows the reason, previous world ID, address,
port and identity prefix, with visible Reconnect and Exit buttons. Reconnect
makes one user-initiated bounded attempt. The durable local profile and bounded
connection metadata survive; no world state is retained as authority.

Each attempt creates new transport/API and protocol objects, resets peer and
sequence ownership, repeats handshake, movement bootstrap, voxel initial sync,
resource sync and survival bootstrap, and builds a fresh world. Input becomes
ready only after all four gates plus streamed spawn collision. App generation
checks guard deferred startup/teardown across awaits; transport callbacks capture
a bounded generation too. Old deferred work cannot act on a later attempt.
Failure returns to the ended screen without an automatic retry loop. The
Reconnect button rejects a changed HOST world with world_mismatch before
bootstrap. World-local character records never merge across worlds.

Clean JOIN leave sends client_leaving and affords 100 ms of transport time.
HOST finalizes the body transform, clears transient rest/harvest/input and
per-peer protocol knowledge/queues, removes body/viewer/presence, and retains
that identity's world-local resources, equipment and biology. Transport leave
provides the same finalization when the notice is lost. Disconnected biology
freezes; shared HOST world/kiln time continues. The same running HOST retains
the existing bounded completed-transaction cache: exact retries remain
idempotent and conflicting retries fail. That cache is not saved across HOST
restart. Reconnect views reflect committed HOST state once; unsent requests
are disposable and never replay automatically.

## Persistence and recovery

Graceful restart resumes the latest successful shutdown save. Abrupt HOST loss
ends every JOIN and resumes the last completed HOST save on restart. Unsaved
mutations after that checkpoint are lost. Client replicas cannot recover them.

Load checks exactly three authoritative candidates in deterministic order:
valid primary first; if primary is missing/invalid, valid pending; otherwise
valid previous. A valid primary is the commit point even when newer pending
exists. Pending represents the next write only when no valid primary survives.
All candidates pass the same checksum, schema, world/explicit seed, compatibility,
roster/owner/transform/survival, global item/object/source identity, source
layout, functional voxel parity and sparse override validation. Invalid
candidates supply diagnostic reasons; none valid fails closed and preserves
files. A world with no candidates is the only new-world path.

Recovery initially loads in memory without replacing diagnostic bytes. Before
a subsequent save overwrites pending/rotates previous, the chosen unchanged
candidate is copied, hash checked and atomically promoted to a validated primary.
A corrupt primary is retained as world.json.corrupt with one previous diagnostic
slot (two bounded diagnostics). Any preservation/promotion failure blocks save.
Normal writes still flush and fully read-validate pending, rotate primary to
previous, then promote pending. The pending file disappears only on successful
promotion. External primary/candidate changes since load still block overwrite.
No database, autosave system, client journal or cloud persistence is introduced.

## Verification

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_5_part_7.ps1
~~~

Evidence is append-only below .verification/wave5/w5_7/run-<UTC>/. Failed and
skip-regression runs remain uncertified. The gate projects only owned source
changes into an external disposable project, pins the fixed runner and source
hashes, and uses isolated APPDATA/LOCALAPPDATA and save/identity roots. It never
corrupts owner saves or deletes identities/cache manually. The graphical
fixture adds a test-only autoload to a copied project and executes the exact
owner launchers from missing cache. Production scripts/content remain identical.
Physical input and visible Reconnect button dispatch exercise owner UI routes.

Focused fixtures cover strict lifecycle packets, six interrupted-save boundaries,
corruption, full authoritative validation, diagnostics and fail-closed recovery.
Real separate ENet OS processes cover repeated same-process reconnect, clean
leave, retained full-backpack staging/save blocking, changes while absent,
HOST F10/window close, forced process kill, failed reconnect, restart, real
protocol-5 rejection, interrupted/completed held harvest, lost-result conservation,
unsent-command disposal, rest cancellation, shared kiln progress while absent and
client-save prohibition. Whole-game regression certification includes Wave 0–4,
W5.1–W5.6 and W5.6 Repair 1, retaining prior assertions and evidence. A previously completed regression may be reused only when its certified receipt,
exact runner hash and entire source manifest match the candidate; the full
regression evidence is copied into the new run. Full
certification status must come from the final receipt; implementation alone
is not a pass or owner acceptance.

## Exact owner commands

Run from D:\AI\Projects\Leyforge-Rebuild. HOST uses the usual durable owner
profile, world wave5-w57-owner-test, seed 184552221 and UDP port 25652:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\run_wave_5_part_7_host.ps1
~~~

CLIENT/JOIN uses the SAME durable Client 2 identity at
user://identity/development/wave5-client-2.json, address 127.0.0.1 and port 25652:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\run_wave_5_part_7_join.ps1
~~~

1. Verify the shared movement, voxels, drops, inventory, crafting, Workbench,
   storage, kiln, survival and Crafting Manual loop.
2. HOST F10: save succeeds, HOST exits, JOIN world disappears and ended view appears.
3. Repeat with HOST window X. JOIN must leave gameplay, including with UI open.
4. Restart HOST; click Reconnect in the existing JOIN process.
5. Confirm same character, worn tool instance/durability and personal/survival state.
6. JOIN F10/window X; HOST keeps playing and retains that character; relaunch JOIN.
7. While JOIN is absent, edit terrain and move/process resources on HOST.
8. Rejoin and verify the current HOST state appears.
9. HOST F5/save and restart: world and both characters restore from HOST save.

Abrupt HOST loss also leaves gameplay after bounded detection; real-process
force-kill proof is automated, optional for the owner's normal smoke test.

## W5.8 boundary and limits

No host migration, LAN discovery, WAN certification, UPnP/NAT traversal, relay,
dedicated-server packaging, PvP, cloud save or account backend. Durable UUID is
not cryptographic proof of possession. No claim of seamless failover, unsaved
crash survival, or completed-transaction persistence across HOST restart.
W5.8 private LAN/WAN security and connectivity work has not begun.
