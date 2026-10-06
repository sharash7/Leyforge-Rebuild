# ADR-0006 — Wave 5 session lifecycle and reconnect

Status: adopted for W5.7 implementation; certification and owner acceptance tracked
in the W5.7 guide. Application 0.5.9-wave5-w5.7, protocol 6; save v4 unchanged.

The accepted shared gameplay loop lacked an application lifetime boundary:
transport disconnect stopped movement but left JOIN's world visible. Failure
and reconnect must never let a disposable replica become authority.

HOST authority loss ends the multiplayer session. There is no host migration.
The app immediately fences JOIN input/readiness and defers complete joined-world
node/replica/UI destruction beyond transport callbacks. It presents a visible
ended view with explicit Reconnect and Exit. A reconnect creates a new API and
all protocol objects; bounded application/transport generations guard delayed
work. Current handshake plus movement/voxel/resource/survival and collision
readiness reconstruct play from HOST facts. Previous-world reconnect rejects a
changed world. Same durable identity reuses its world-local HOST character;
transient live presence and actions are finalized independently.

Reliable bounded lifecycle control uses channel 11. Graceful HOST closing
fences new mutations/admission, cancels transient held actions/rest, resolves
staging, synchronizes every live body and completes its atomic authoritative
save before closing notices/disconnect. Failed save prevents graceful shutdown
and restores HOSTING with clients connected. Successful closing waits at most
350 ms for acknowledgements. Transport disappearance or five seconds without
validated HOST traffic independently tears JOIN down. Client never saves or
becomes authority. HOST crash restart uses its last completed save.

Recovery keeps the existing checksum envelope and full graph validator. Valid
primary wins. Without valid primary, validated pending precedes previous by
transaction role, independent of enumeration/timestamps. No valid candidate
fails closed. Recovery loads without discarding corrupt diagnostics. A later
save establishes the unchanged recovered candidate as primary before beginning
a new pending write; corrupt primary is retained in two bounded diagnostic
slots. External byte changes still block writes. This hardens interruption
behavior without a durable schema change or speculative database/journal.

Consequences: reconnect visibly rebuilds and is not seamless; unsaved HOST
crash state is lost. Full staging can intentionally block saves until the owner
resolves capacity. Idempotent transaction results remain bounded and HOST-process
local. LAN/WAN security, stronger identity authorization and connectivity remain
W5.8; dedicated server/account/cloud services remain outside this work.
