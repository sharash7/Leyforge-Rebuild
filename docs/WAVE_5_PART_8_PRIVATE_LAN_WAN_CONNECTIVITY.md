# W5.8 — Private LAN/WAN connectivity

Application **0.6.0-wave5-w5.8**, network protocol **7**. Save/content/current
worldgen remain **4/1/2**, with stored worldgen v1 supported. W5.7 is AUTOMATED
CERTIFIED + OWNER ACCEPTED at 0.5.9-wave5-w5.7 / 54eb181423e02e584f45c76a79bd08edd6cdfe35.
Wave 5 remains in progress. Owner amendment dated 2026-10-15:
**W5.9 may proceed under revised LAN-first Wave 5 scope. Direct WAN owner
acceptance is deferred to Wave 17.** See
[scope amendment](WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md) and ADR-0008.

Automated certification is determined by the final complete W5.8 gate receipt.
W5.8 AUTOMATED CERTIFIED — PASS. W5.8 LOCALHOST OWNER TEST — PASS.
Two-computer connectivity is OWNER REPORTED; CAPTURE TOPOLOGY/DETAILS.
Direct WAN owner testing is DEFERRED TO WAVE 17. Revised local/LAN scope is
closure eligible after relevant manual LAN evidence. The original receipt's
**REAL_WAN_OWNER_TEST_REQUIRED = true** is retained unchanged as historical evidence.
Localhost, same-PC interfaces, simulated delay, same-router traffic and VPN/overlay
connections do not establish direct WAN certification.

## Direct connectivity and ownership

Godot SceneMultiplayer + ENetMultiplayerPeer retains UDP **25652** by default.
HOST binds `*` (all interfaces); optional BindAddress deliberately narrows it.
JOIN accepts bounded IPv4, IPv6 and hostname endpoints. Transport/DNS resolution
can still fail. Port range 1–65535 is enforced. IPv6 support is retained; no real
global IPv6 reachability claim is made until externally tested.

All existing HOST command validation, movement prediction/correction, per-peer
interest, voxel/resource/survival authority, save v4 and W5.7 teardown remain.
OFFLINE has no session, socket, invite or UPnP initialization. HOST alone saves;
HOST loss ends JOIN's world. No migration, relay, accounts, public browser,
NAT punching, dedicated server or cloud backend is introduced.

## Private authentication

`LfePrivateSessionAuth` is the single crypto/schema/transcript owner. Every
normal HOST initializes separate 16-byte cryptographically random invite and
session-instance ID using Godot Crypto. Invite text is eight groups of four
uppercase hex characters (128 bits). HOST F8 displays it and Copy Invite copies
the endpoint/UDP port/invite for private sharing. The panel starts hidden so
routine automated gameplay screenshots do not capture credentials.

Client hello contains an exact compatibility manifest and fresh 16-byte client
nonce. HOST validates protocol/build/save/content/hash/worldgen support first,
then sends only a fresh 16-byte server nonce and ephemeral session instance.
Client sends a fixed 32-byte HMAC-SHA256 proof. Godot Crypto generates HMAC and
compares decoded 32-byte proofs with its constant-time comparison. Only after
success does HOST evaluate duplicate identity, eight-player capacity/character
availability, send the authenticated world manifest, and complete SceneMultiplayer
authentication. UUID identifies a world-local character; invite grants session
admission permission, without proving personal ownership of that UUID.

The transcript has fixed field order with uint32 little-endian UTF-8 length
frames: domain, auth version, protocol, build, content hash, player ID, save,
content version, supported worldgen list, client nonce, server nonce, instance.
Integral JSON values normalize to decimal integers. Dictionary order cannot
change the proof. Every proof consumes its challenge, including failed proofs.
A replay fails against fresh server nonce/session state. One pending challenge
per peer, at most eight pending challenges, the ENet transport's bounded eight
remote slots and six-second auth deadline bound work. Pending state clears on
proof/rejection/timeout/disconnect/shutdown. Malformed private proof, wrong,
missing or stale invite share `private_session_denied`. Compatibility errors
remain explicit. No UUID-only fallback exists. Actual historical protocol-6
clients receive `protocol_mismatch` before admission.

World ID, seed, roster, voxel, resource and survival data are withheld until
invite proof succeeds. The secret never appears in auth/gameplay packets, save,
profile, console or verification evidence. Invite is ephemeral; a HOST restart
creates a new secret/instance. JOIN keeps it in current process memory for
same-process reconnect. A client restart prompts again. Enter a new invite in
the masked ended-screen input after HOST restart. Rotation within a running
HOST is not implemented; restarting HOST rotates it.

HMAC proves invite possession. **ENet gameplay transport is not encrypted**;
there is no general confidentiality or protection against an on-path attacker,
anti-cheat, account ownership proof or DDoS guarantee.

## Connectivity diagnostics and UPnP

F8 shows session/count, bind/UDP port, bounded local LAN candidates, known WAN
candidate, UPnP/direct-route status and invite. Local/private candidates are
not presented as verified public endpoints. No third-party IP lookup is used.

`-EnableUpnp` is explicit opt-in. Discovery, UDP-only mapping, renewal and
cleanup run on a worker thread, with main-thread status publication. Discovery
requests a 2000 ms bound; gateways/control calls may have their own timeouts.
A 3600-second lease is requested and renewed at 1800 seconds. Graceful shutdown
requests deletion only after an owned mapping; shutdown waits for its worker.
Crashes depend on the gateway honoring lease expiry. Lease refusal/mapping
failure is reported; no silent permanent-lease fallback is made. Failure keeps
HOST running and directs the owner to manual forwarding. A successful map is
only a routing candidate, never proof of WAN reachability.

A gateway-reported private, shared-carrier 100.64/10, loopback, unspecified,
link-local or local IPv6 address warns that direct inbound hosting **may** be
blocked by CGNAT/double NAT. This is a candidate classification, not definite
ISP topology detection. Unknown address remains unknown. Some networks cannot
host directly; report the environment blocker rather than claiming WAN PASS.

`check_wave_5_part_8_network.ps1` reads active profiles, local addresses, UDP
listeners and firewall state and gives manual guidance. It never elevates or
mutates Windows Firewall/router rules. For IPv4 manual routing, forward the
configured external **UDP** port to HOST private address/same UDP port; permit
HOST/game inbound traffic on the active firewall profile. No TCP game forward.

## Portable friend kit

`build_wave_5_part_8_remote_join_kit.ps1` selects committed project/source/content/
scene/plugin files, required JOIN launch scripts, and the two existing playtest
driver scripts preloaded by the canonical application plus their save-view helper. It copies the approved
fixed runtime pair and extracts its MIT/dependency license notices. No runtime
binary is committed to Git. Source commit, app/protocol and actual SHA-256 file
hashes are in `kit_manifest.json`. Generated kits live under ignored `builds/`.
Owner saves, identities, invites, logs, Git, cache and verification evidence are
excluded. The friend creates their own canonical local identity. Owner-local
JOIN retains the dedicated Client 2 identity convention.

Runtime selection supports bundled `runtime/`, explicit `-GodotRoot`, and the
existing owner's fixed runtime directory. Both executable hashes are checked
before execution. Invite is prompted masked and passed to the game through its process
environment; the launcher restores its process environment immediately, clears
temporaries, and the game consumes/unsets it. No machine environment is changed.
No secret belongs in command history. A verification-only snapshot option
supports precommit disposable kit testing and marks that kit uncertified;
regenerate from committed certified source before sending to a friend.

## Timeouts, quality and verification

Connect is bounded at 12 seconds, authentication 6 seconds, authenticated HOST
silence 10 seconds, heartbeat/ping about 1 Hz. Ping/pong uses bounded sequences
and a rate bound, never gameplay clocks/authority. Exact connect/handshake/world
ready times and a bounded RTT sample window are diagnostic only. Initial values
must be judged against simulated delay/jitter/loss and the actual human WAN test.
Movement 30/20 Hz and ~100 ms interpolation retain their accepted values.

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_5_part_8.ps1
~~~

Append-only evidence: `.verification/wave5/w5_8/run-<UTC>/`. Failed runs and
`-SkipRegression` diagnostics remain uncertified. The gate pins source/runner
bytes and isolates projects/profiles externally; it projects only the application
version over committed project configuration and preserves editor/UID changes.
Test-only fixture credentials and delay/loss instrumentation are explicit and
never part of normal HOST initialization. No owner saves/imports are touched.

Required complete certification covers focused auth/UPnP, real ENet auth and
negatives, actual accepted protocol-6 rejection, secret scans, non-loopback
socket binding, 50/100/200 ms simulated RTT with jitter/unreliable loss, gameplay
convergence/voxel/resource/reconnect, portable kit validation, and complete
Wave 0–4 / W5.1–W5.7 regression receipts. A simulated result never certifies WAN.
See the [real network guide](WAVE_5_PART_8_REAL_NETWORK_TEST_GUIDE.md) for owner
and friend commands and the mandatory 10–15 minute external test.

W5.9 owns broader torture/contention/soak/failure-injection and final Wave 5
release certification. W5.8 does not start or complete that work.
