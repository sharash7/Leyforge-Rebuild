# ADR-0007 — Private session admission and direct connectivity

Completion-scope amendment (2026-10-15):
[ADR-0008](ADR-0008_WAVE_5_LAN_FIRST_COMPLETION_AND_WAN_DEFERRAL.md) supersedes
the external-WAN owner acceptance prerequisite. W5.9 may proceed under revised
LAN-first Wave 5 scope. Direct WAN owner acceptance is deferred to Wave 17.
The design and original acceptance requirements below remain historical facts;
this amendment does not assert a WAN PASS or rewrite any evidence.

Status: W5.8 implementation; automated certification is determined by its full
receipt. Real external human WAN acceptance remains pending.

Retain SceneMultiplayer/ENet direct authoritative co-op over UDP. A cryptographically
random 128-bit process/session invite grants admission permission. Durable UUID
continues to identify a world-local character and is not a password or personal
ownership proof. Fresh 128-bit client/server nonces plus a separate random session
instance bind a deterministic length-framed HMAC-SHA256 transcript. The secret
never crosses the wire; fixed proof comparison uses Godot Crypto. Compatibility
is checked first, then proof, then duplicate/capacity/character admission. Withhold
world manifest until proof succeeds. Bound pending attempts and timeouts.

Invite remains ephemeral and in memory; HOST restart rotates it, Client restart
asks again. Same-process reconnect may retain it. Do not store it in saves,
profiles, logs or evidence. Preserve existing gameplay/save authority and W5.7
teardown; no host migration. Offline play remains socket/invite/UPnP free.

Wildcard HOST binding and portable private JOIN workflow support direct LAN/WAN.
Optional explicit UPnP performs UDP leased mapping in background work with renewal
and graceful cleanup. Manual forwarding remains supported. Failed mapping or
unknown external route never blocks local HOST play. Private/shared gateway
addresses warn of possible CGNAT/double NAT; some networks cannot host directly.
No relay/account/backend, public browser, NAT punching or platform invites.

HMAC is admission authentication, not encrypted gameplay transport. Do not claim
general confidentiality, anti-cheat or DDoS protection. Real WAN requires a human
Client on a physically separate internet connection connecting directly without
an overlay and exercising the shared loop/reconnect/shutdown. Localhost and
simulated latency cannot replace that acceptance. Broader W5.9 is separate.
