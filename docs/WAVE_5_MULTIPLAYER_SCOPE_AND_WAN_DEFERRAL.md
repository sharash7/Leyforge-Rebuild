# Wave 5 multiplayer scope and WAN deferral

**2026-10-16 closure update:** the owner reports W5.9 two-computer LAN success
and authorizes Wave 6 progression. [Wave 5 closure](WAVE_5_CLOSURE.md) records
overall owner acceptance, incomplete manual traceability and exact certification
limits. The dated amendment/history below remains the original 2026-10-15 record;
its pending acceptance entries are superseded by that closure decision, not by
invented per-test observations. WAN stays deferred to Wave 17.

Owner-authorized governance amendment, **2026-10-15 (Australia/Perth)**.
Authority: the owner's W5.9 direction, starting from main at
`bbe49b2e79193ae241c9a6eaaa73485abae403ae`.

## Decision

Wave 5 completes as **Multiplayer Proof #1 — Local/LAN**. A safe shared
authoritative world on local and LAN connections is sufficient to unlock
living-world development. Direct WAN, universal NAT traversal, CGNAT/Starlink
access, relay fallback, internet discovery, friends/presence and one-click
invitations move to **Wave 17 — Multiplayer Proof #2**. This changes completion
scope; it does not change any historical observation or certify an untested route.
No new router, ISP, paid service, VPN overlay or temporary relay is required
for Wave 5 closure. W5.9 is authorized now. Wave 6 implementation is not authorized.

## Acceptance history and actual observations

| Stage | Recorded status |
| --- | --- |
| W5.1–W5.7, including W5.6 Repair 1 | AUTOMATED CERTIFIED + OWNER ACCEPTED |
| W5.8 automated certification | PASS; retain original receipt and source/runner pins |
| W5.8 localhost owner test | PASS, as reported by owner |
| W5.8 two-computer connectivity | OWNER REPORTED; CAPTURE TOPOLOGY/DETAILS |
| W5.8 direct WAN owner test | DEFERRED TO WAVE 17; no WAN PASS |
| W5.8 revised local/LAN scope | Closure eligible after relevant manual LAN evidence |
| W5.9 automated certification | Requires the final complete source-matched W5.9 gate; status is receipt-derived |
| W5.9 physical two-PC LAN acceptance | LAN HUMAN ACCEPTANCE REQUIRED |

The owner confirmed Stage A localhost functionality and reported that two
computers can connect. Their network arrangement, LAN endpoint, duration and
gameplay results have not yet been recorded. Do not infer a direct LAN path.
Same-machine non-loopback sockets, VPN/overlay and simulated latency cannot
establish physical two-PC LAN or direct WAN acceptance.

The retained W5.8 automated receipt is
`.verification/wave5/w5_8/run-20261014T042123223/gate.json`.
Its original `REAL_WAN_OWNER_TEST_REQUIRED=true` remains historical evidence;
this amendment defers that human requirement to Wave 17 rather than editing
the receipt. The W5.8 implementation, portable kit and future-reference WAN
instructions remain available. Prior failed and uncertified receipts also remain.

## Revised definition of done

Wave 5 may close only after W5.9 automated certification and owner local/LAN
acceptance, with no blocking correctness defect. Required capabilities are
two-player authoritative shared world, secure private admission, movement and
relevance, authoritative voxel edits, inventory/resource conservation,
crafting/workstations, independent survival, disconnect cleanup, reconnect and
HOST-owned persistence. W5.9 also verifies three distinct durable players and
audits the eight-player bounds without implying measured eight-player performance.

W5.9 must retain complete source/runner-matched Wave 0–4 and W5.1–W5.8
regressions, focused validation, actual separate-process gameplay, graphical
normal-input checks, contention/idempotency/conservation, recovery, network
quality measurements and an honest bounded soak. Skips cannot certify. Critical
authority, duplication, persistence or teardown defects block certification.

The owner must record two separate physical PCs on the same LAN, HOST LAN
address used privately, the same private invite protocol, representative shared
gameplay, contention, reconnect, save/reload and HOST shutdown for approximately
15 minutes. No UPnP, WAN forwarding or overlay is required. Raw addresses,
invites and credentials must not be published. Automated and manual acceptance
remain separate. Direct WAN success is not a Wave 5 closure requirement.

## Retained design and residual limitations

HOST owns world truth, character records and saves; JOIN owns prediction and
presentation. No client world saves, host migration or offline continuation
after HOST loss. Protocol 7, save/content/worldgen 4/1/2 and stored worldgen v1
remain unless a separately explained breaking change becomes necessary.
Private random invites and HMAC-SHA256 challenge-response stay mandatory on
localhost and LAN. There is no trusted-LAN authentication bypass.

| Limitation | Future scope |
| --- | --- |
| Direct WAN unverified; CGNAT/Starlink may prevent inbound UDP | Wave 17 online connectivity |
| NAT traversal, relay, friend/session discovery and clickable expiring invitations absent | Wave 17 assessment and implementation |
| ENet gameplay is not transport-encrypted | Wave 17 secure transport design |
| UUID is not strong account ownership proof | Wave 17 identity/backend assessment |
| No host migration; HOST crash loses changes after last successful save | Explicit current lifecycle; future architecture assessment |
| Dedicated/headless server deferred | Wave 17 pathway |
| High-player-count performance requires measurement | Wave 17 scale testing; W5.9 reports only observed bounds |

## Dependencies before Wave 6

Complete W5.9 automated certification, obtain owner LAN acceptance, classify
remaining issues and explicitly close Wave 5 before starting W6.1 — Readiness,
UI & Integration Foundation. The readiness handoff documents stable interfaces
and hazards only. No biomes, water, caves, ecology, creatures, time/weather,
farming or new Forge implementation belongs to this authorization.

See ADR-0008 and the W5.9 certification document for the current decision and gate.
