# ADR-0008 — Wave 5 LAN-first completion and WAN deferral

Status: owner-approved scope amendment, 2026-10-15 (Australia/Perth).
Supersedes ADR-0007's external-WAN acceptance prerequisite for proceeding to
W5.9 and closing Wave 5. Its historical design facts remain valid.

The owner has decided that local/LAN authoritative shared gameplay is sufficient
as Multiplayer Proof #1 to unlock living-world development. Starlink/CGNAT can
prevent direct inbound UDP; proving a universal internet product is a separate
architecture and testing responsibility. Wave 5 closure requires no new router,
ISP, paid service, temporary overlay or relay.

Retain W5.8 ENet direct connectivity, private random invites, HMAC-SHA256
challenge-response, protocol 7, optional UPnP, diagnostics, portable kit and
historical automated receipts. Do not change an unverified direct-WAN result
to PASS. The original external-WAN owner test is deferred to Wave 17.

Wave 5 is now Multiplayer Proof #1 — Local/LAN. W5.9 performs final automated
correctness, contention, persistence, graphical interaction and stability
certification. The owner subsequently records actual two-physical-PC LAN
gameplay and topology. Same-machine non-loopback testing cannot replace it.
Prior two-computer connectivity is owner-reported with topology unconfirmed.
Wave 5 stays open until the automated and human gates both pass.

Wave 17 — Multiplayer Proof #2 retains combat, settlements, automation,
vehicles/vessels, portals/realms, advanced save/resync and dedicated/headless
pathways. Its named online-connectivity workstream assesses direct WAN,
CGNAT/Starlink, NAT traversal, relay fallback, internet discovery/presence,
expiring one-use clickable invites, click-to-join, platform/backend choices,
secure transport and internet-scale testing. None is implemented by this ADR.

Consequences: no trusted-LAN security bypass; HOST authority and client-save
prohibition remain. Unencrypted ENet gameplay, self-held UUID identity, absence
of relay/migration/dedicated server and unmeasured high-player-count performance
remain explicit limitations. W6.1 starts only after Wave 5 acceptance and closure;
the W5.9 readiness handoff authorizes no Wave 6 implementation.

See [scope amendment](../WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md).
