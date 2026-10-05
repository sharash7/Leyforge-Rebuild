# Wave 5, Part 2 — Session and player identity

Build: 0.5.3-wave5-w5.2. W5.1 is AUTOMATED CERTIFIED + OWNER ACCEPTED
at 0.5.2-wave5-w5.1 / acf1e5db0cec264b8abe1e491f025d05a922af70.
W5.2 is AUTOMATED CERTIFIED + OWNER ACCEPTED at 0.5.3-wave5-w5.2 / 39c7fed82e125d451ae443ceb8be1ff42ea5105d. The owner reports that manual testing succeeded.

## Topology and ownership

HOST process <-> real UDP ENet <-> JOIN process. OFFLINE keeps the accepted
W5.1 single-player world/save path without a socket. HOST opens the same
normal playable world, with separate local player and server/world roles.
JOIN branches before catalog/world/bootstrap authority and creates a lightweight
session view only. It has no world save, gameplay authority, physical player or
voxel world. The host owns saves, admission and durable character records.

Reusable src/lfe/networking/network_session.gd localizes ENet construction and
SceneMultiplayer lifecycle. It polls its own API without attaching RPC or
replication to the gameplay scene tree. Leyforge game orchestration supplies
pre-admission availability and character creation callbacks, using existing
authority.add_character and bounded safe-spawn rules. Forge-ENG is unchanged.

## Session contract

Modes: OFFLINE, HOST, JOIN.
States: OFFLINE, STARTING_HOST, HOSTING, CONNECTING, AUTHENTICATING,
CONNECTED, REJECTED, CONNECTION_FAILED, DISCONNECTED.
Explicit allowed transitions fail safely; state_changed includes a stable
reason code. Connect timeout is 6 seconds; authentication timeout is 3 seconds.
Transport cleanup runs outside poll callbacks.

Default UDP port: 25652. Ports 1–65535 are validated. Addresses are bounded to
253 ASCII hostname/IP characters; ENet handles endpoint resolution. Hosts bind
normally for future LAN capability. W5.2 certifies 127.0.0.1 only.
Maximum admitted players: 8 including the local host. ENet permits eight
remote transport slots: seven admitted clients and one bounded authentication
slot to deliver server_full at capacity. Pending identities reserve admission
slots, preventing simultaneous handshake races.

Live peer_to_player and player_to_peer maps never enter the world save.
Godot peer 1 is the server transport address, with a separate durable host
player ID. No local controller is used as server identity.

## Identity and launch validation

The host uses user://identity/local_profile.json by default. JOIN defaults to
user://identity/development/wave5-client-2.json. Both use LfeLocalProfile's
existing validation, cryptographic identity creation and atomic pending-write
promotion. Restarting the join launcher retains the same Client 2 identity.

--profile-path accepts bounded identity JSON paths under user://identity/ or
absolute paths outside the project. Relative paths, traversal, source paths,
control characters and alternate-stream syntax are rejected; no invalid
override falls back to host identity. Session mode, endpoint/port and duplicate
session arguments fail visibly. Existing world-ID and seed handling is retained.
No display names or account system are added; UI shows a short player-ID prefix.

## Strict wire schema

JSON UTF-8 authentication data, maximum 4096 bytes. Exact keys; no arbitrary
Objects/Callables or Godot Variant deserialization. allow_object_decoding=false.
Protocol/save/content values must be integral 1–65535; build strings are 1–64
characters; player ID is 32 lowercase hex; content hash is 64 lowercase hex;
worldgen arrays contain 1–8 unique supported positive integral versions.
JSON numbers normalize explicitly for supported-version membership checks.

Client hello (exact seven fields):

~~~json
{
  "network_protocol_version": 1,
  "build_version": "0.5.3-wave5-w5.2",
  "player_id": "<32 lowercase hex>",
  "save_version": 4,
  "content_version": 1,
  "content_hash": "<64 lowercase hex SHA-256>",
  "worldgen_versions": [1, 2]
}
~~~

Host response (exact two fields): reason and world. Rejection uses a stable
reason and empty world. Acceptance uses reason=ok and the exact world fields:
world_id, seed, worldgen_version, save_version, content_version, content_hash,
network_protocol_version. World IDs retain the existing 1–64 ASCII
letter/digit/underscore/hyphen rule; seed is integral 0–2147483647. The client
validates this response before completing authentication.

The host requires exact protocol/build/save/content/hash compatibility and
evaluates its actual world manifest. Stored worldgen v1 is accepted by a build
supporting [1,2]; unsupported worlds reject. The manifest describes the session,
without transmitting terrain, inventory or character gameplay snapshots.

Reason codes: ok, malformed_handshake, invalid_identity, protocol_mismatch,
build_mismatch, save_schema_mismatch, content_version_mismatch,
content_hash_mismatch, worldgen_unsupported, duplicate_identity, server_full,
auth_timeout, connection_failed, server_disconnected. Oversized data maps to
malformed_handshake. A full durable roster also fails pre-admission with
server_full for a new identity.

## Canonical fingerprint

All real files recursively beneath content/, including hidden files, except
.gitkeep. Sort relative slash-separated paths. For each file hash a 16-byte
little-endian frame (uint64 UTF-8 path length, uint64 byte length), then UTF-8
path bytes and raw file bytes into SHA-256. Empty placeholder directories
contribute nothing. There is no copied content registry. Tests compare reordered
enumeration, placeholder changes and a one-byte canonical change.

## Admission and reconnect

Compatibility validation precedes admission. Pending and live mappings reject
duplicate identity without kicking the first peer. Once both ends complete
SceneMultiplayer authentication, the host binds the peer to an existing
character, or creates W5.1 defaults at the current safe-spawn seam.
New records have default/empty personal resources, equipment, survival and
hotbar selection. Ownership and shared state remain unchanged.
There is no remote CharacterBody or avatar.

Disconnect clears live peer state and retains the durable character. Reconnect
uses the same profile ID and same in-memory record; a normal host save/reload
retains that record. Opening a socket does not autosave. The host's ordinary
save/quit policy remains authoritative. Clients store identity only.

IDs are self-reported private-development identity metadata, not credentials.
Duplicate binding prevents accidental state duplication and does not prove
ownership against malicious impersonation. Stronger private-session
proof/invites and WAN security remain later requirements. A connected peer gains
no gameplay mutation bypass; later commands still need host validation.

## Owner commands

Run these in two ordinary PowerShell windows. Both scripts refresh/register
Godot classes before launching the normal graphical runner. A project-specific
named mutex serializes imports and launch startup. The scripts use only the
approved shutdown-fixed runner and never delete profile/save data.

HOST:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_2_host.ps1'
~~~

Defaults: world wave5-w52-owner-test, seed 184552221, port 25652, canonical
owner profile. WorldId, Seed, Port, ProfilePath and RuntimeLogPath are optional.

CLIENT / JOIN:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_2_join.ps1'
~~~

Defaults: 127.0.0.1:25652 and the stable dedicated Client 2 profile.
Address, Port, ProfilePath and RuntimeLogPath are optional.

Host shows its normal playable world and Hosting / port / player count.
Client shows Connecting, Authenticating, Connected and the host world/seed,
stored worldgen/save contract and short local identity. It has no movement.
Close Client: host remains running, count falls to 1. Rerun the same command:
the same identity joins again and count returns to 2. Launching that command
again while Client is connected rejects the third window with duplicate_identity.
Close the host: client transitions to Disconnected / server_disconnected.
Host F5/F10 and ordinary window close retain normal authoritative save behavior.

## Verification

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\verify_wave_5_part_2.ps1'
~~~

The gate snapshots source/test/content/plugin bytes externally, isolates every
process profile, imports classes, runs focused validation and real separate-OS-
process ENet probes against the production host/join scene. It checks state
sequence, peer/player distinction, first defaults/safe spawn, duplicate and
compatibility rejection without mutation, live-peer health, disconnect,
same-record reconnect, third identity, eight-player capacity, auth timeout,
no-host failure, port conflict, server disconnect, normal host save and fresh
process roster reload. JOIN's world directory and authority/controller absence
are explicit negative assertions.

The exact owner host/join launchers also run graphically against a fresh cache,
with normal window close/save and a separate client restart. The complete
W5.1 gate reruns Wave 0, 1, 2, 3, 4 and W5.1 qualification with original checks.
Static source checks prohibit RPC/replication nodes and ENet outside the session
class. Final hashes and source inventory must match the snapshot.
SkipRegression produces an uncertified receipt.

Append-only evidence: .verification/wave5/w5_2/run-<UTC>/, including gate.json,
source_manifest.json, focused.json, host/client/reconnect logs and JSON,
incompatibility_results.json, owner-launch receipts/logs and nested regression
evidence/screenshots. Failed runs are preserved.

## Intentional limits and W5.3 boundary

No remote movement, remote avatar, voxel replication, inventory/resource
replication, gameplay RPC/transaction routing, LAN certification, WAN, UPnP,
relay, dedicated server or host migration. This describes the accepted W5.2 build; current W5.3 movement is documented separately.
Save/content/current worldgen remain 4/1/2; stored worldgen v1 remains supported.
See adr/ADR-0001_WAVE_5_NETWORK_SESSION_FOUNDATION.md.

## Qualification

AUTOMATED CERTIFIED + OWNER ACCEPTED on 2026-10-05. Accepted build: 0.5.3-wave5-w5.2. Accepted SHA: 39c7fed82e125d451ae443ceb8be1ff42ea5105d.
Complete final-source receipt:
.verification/wave5/w5_2/run-20261005T040503522/gate.json.
It records passed=true, certified=true, snapshot_matches_source=true,
enet_two_process=true, reconnect=true, auth_timeout=true,
server_disconnect=true, host_save_reload=true, client_save_negative=true,
owner_launch=true and no_gameplay_replication=true.

Focused validation: 83 assertions. Exact graphical launchers: 26 assertions.
The real multi-process matrix independently passed duplicate identity, protocol,
build, save, content version/hash, worldgen support, malformed/oversized identity
exchange, authentication timeout, port conflict, no-host failure, distinct third
identity, all eight admitted slots, server-full rejection, reconnect and host
save/reload. The original connected client remained healthy through rejection.

Enclosing W5.1 regression receipt:
regression_w51/run-20261005T040711375/gate.json within that W5.2 evidence.
It records 564 focused/restart assertions, 3,357 rendered assertions across
12 processes, 88 owner-launch assertions and Wave 0–4 PASS. The nested Wave 4
receipt uses SkipRegression because its enclosing gate already runs Wave 0–3;
the enclosing W5.1 and W5.2 receipts are both certified.

Earlier failed attempts and the intermediate uncertified network-only run remain
retained. The final successful wrapper reads the enclosing W5.1 receipt rather
than a nested regression receipt. This describes the accepted W5.2 build; current W5.3 movement is documented separately.