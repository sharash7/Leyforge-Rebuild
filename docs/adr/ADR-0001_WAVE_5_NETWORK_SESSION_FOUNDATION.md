# ADR 0001 — Wave 5 session foundation

Status: adopted for W5.2, 2026-10-05.

Leyforge already separates durable installation identity, world-local characters
and shared authority. W5.2 needs a real private co-op session while preserving
that ownership.

Use an authoritative host/server and Godot high-level SceneMultiplayer with
ENet as the first UDP transport. LfeNetworkSession owns transport construction,
polling, pre-admission compatibility and live peer/player bindings. Game code
uses project-owned start_host, start_join, disconnect_session, state/reason
and admission/leave signals. Leyforge supplies character admission and safe
spawn callbacks; the networking layer owns no gameplay or world save.
This is one concrete session seam, without a speculative transport framework.

OFFLINE opens the normal local world with no network object/socket. HOST adds
a session to the normal playable world. JOIN loads only local identity and a
session/status view; it never opens an authoritative world. The local host
player is a separate role from server/world authority. The network session has
no camera or controller dependency.

Stable 32-hex Leyforge player IDs are distinct from transient Godot peer IDs.
Peer 1 addresses the server; it is never saved as durable player identity.
SceneMultiplayer authentication carries a bounded JSON compatibility exchange
before peer admission. Admission adds or reuses the host-owned character through
W5.1 authority. Disconnect removes live bindings and retains the character.
The normal host save persists the roster without a schema bump. No host
migration is provided.

Application version is exact; protocol version is independent and begins at 1.
Save/content remain 4/1. Stored worldgen v1/v2 are supported. A deterministic
SHA-256 of canonical content paths and bytes supplements the content version.

The current player ID is self-held metadata, neither secret nor proof of
possession. Duplicate rejection prevents accidental simultaneous identity use;
a malicious party can still claim another ID after it disconnects. Secure
invite/reconnect/account proof is deferred before public/WAN acceptance.

W5.2 contains no movement, avatars, voxel/resource replication or gameplay
command routing. W5.3 adds player presence/movement using this session. Later
parts add individually validated commands, LAN/WAN qualification and stronger
security. Dedicated servers and another transport remain possible because
world authority and the local host player are separate; neither is implemented
here.