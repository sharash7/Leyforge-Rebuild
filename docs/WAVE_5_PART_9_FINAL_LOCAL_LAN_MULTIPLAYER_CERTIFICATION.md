# W5.9 — Final local/LAN multiplayer certification

**Status update, 2026-10-16:** automated certification is retained at
`fe4411c6ca9cf2598d1564ff3ce5cd0461f8c29e`; the owner reports W5.9 two-computer
LAN success and approves Wave 6 progression. [Wave 5 is closed for that LAN-first
scope](WAVE_5_CLOSURE.md), with missing manual checklist details and post-certification
source-match limitations explicit. The original gate/form requirements below and
historical receipts are retained; no individual manual result is inferred.

Candidate: **0.6.1-wave5-w5.9**, network protocol **7**, save/content/worldgen
**4/1/2**, with stored worldgen v1 supported. Owner authorization: 2026-10-15.
W5.9 hardens and certifies the implemented Wave 4/5 loop; it adds no progression
or Wave 6 gameplay. Automated certification is determined by a complete final
source-matched receipt. At certification time, owner acceptance was **LAN HUMAN ACCEPTANCE REQUIRED**.
Wave 5 is not closed by an automated pass alone.

## Scope and retained history

Under the [scope amendment](WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md) and
[ADR-0008](adr/ADR-0008_WAVE_5_LAN_FIRST_COMPLETION_AND_WAN_DEFERRAL.md), Wave 5
is Multiplayer Proof #1 — Local/LAN. W5.1–W5.7 including W5.6 Repair 1 are
automated-certified and owner-accepted. W5.8 automated certification and localhost
owner test passed; two-computer connectivity is owner-reported with topology to
capture. Direct WAN owner acceptance is deferred to Wave 17, never marked PASS.
Historical W5.8 successful/failed receipts, direct implementation, portable kit
and future-reference WAN instructions are retained.

HOST owns world truth, characters, voxel/resources/survival, ticking and saves.
JOIN owns prediction/presentation and sends validated intent. No client world
save, host migration, duplicate identity/transaction/item, survival forgery,
unauthenticated bootstrap or player-count multiplication is permitted.
Private invite/HMAC admission stays active on localhost and LAN. No automatic
UPnP or machine-wide network changes are used for W5.9 certification.

## Automated matrix and evidence ownership

The final gate reruns the complete W5.8 → W5.7 → W5.6 Repair 1 → W5.6 → W5.5
→ W5.4 → W5.3 → W5.2 → W5.1 → Waves 0–4 chain on the candidate source projection.
It verifies the entire W5.8 source inventory and runner identity before retaining
the complete copied regression evidence. No historical receipt is assumed valid
merely because its stage once passed. Nested skip-regression receipts are only
valid in their complete enclosing gate; a W5.9 skip never certifies.

| Requirement | Actual fixture/gate responsibility |
| --- | --- |
| Deterministic v1/v2 terrain, bounds, malformed shapes/keys, nonfinite values, exact build rejection | `w5_9_focused.gd`; existing worldgen/save/protocol focused regressions |
| Three durable identities, one world, independent bodies/inventories/survival and peer mapping | W5.9 actual HOST/client/third; W5.3/5.5/5.6 real-process regressions |
| Movement: idle/walk/sprint/jump/fall, opposing input, direction changes, drift convergence and distant relevance | W5.9 motion/soak plus W5.3–W5.8 measured movement/relevance/survival probes |
| Same-block mining, same-target placement, repeated chunk-boundary edits/collision, saved edited initial sync | W5.9 normal held-input race, prepared real ENet placement race, 80 boundary commits plus six inventory-backed placement/held-mining cycles across cells 15/16, and restart; W5.4 source-matched sync/collision/regeneration tests |
| Remote gameplay beyond HOST camera | W5.9 HOST camera beyond 128 m while Client mines/places at the boundary and gathers a finite water cache from its own streamed body position; independent survival and third player continue |
| Drop single winner, clustering/merge/despawn and smoothing | W5.5 simultaneous pickup/conservation; Repair 1 rendered drop trace |
| Transfers/equipping/tools/hotbar/consume/crafting and idempotency | W5.5 protocol/transaction/legitimate progression, exact retry/conflicting ID/lost result/stale state/order; W5.6 atomic consume; W5.7 reconnect committed/unsent requests |
| Shared storage/Workbench/Kiln, finite-source competition, output capacity, separate staging and tool wear | W5.9 shared endpoint/context cases plus W5.5/Repair 1 resource, progression, contention and graphical fixtures |
| Independent Health/Stamina/Hunger/Thirst/Fatigue/Exposure/debt, sprint denial, fall/death 50/50 recovery and exact tool identity | W5.6/Repair 1, W5.7 stale epoch and saved graph; W5.9 independent owner views |
| Delay/jitter/unreliable loss/reliable ordering/stale packets | W5.8 50/100/200 ms nominal simulated RTT, ±6 ms one-way jitter, every twentieth eligible unreliable send dropped; W5.4–W5.7 corrupt/gap/stale/recovery tests |
| Disconnect while idle/moving/harvesting/editing/inventory/Workbench/storage/Kiln/Manual/rest/pending command; third keeps playing | W5.9 eleven same-process cycles against one HOST; W5.7 held/committed/staging/cleanup/biology tests |
| HOST F10/window X/force kill/transport loss/liveness timeout | W5.7 actual process/WM_CLOSE/physical F10; W5.8 delayed restart/new invite/silence |
| Failed save, full-backpack staging, corrupt primary/pending/previous recovery | W5.9 isolated pending-path directory I/O failure; W5.7 focused interruption/whole-graph validation and real shutdown refusal |
| Exact graph/file save/reload, world isolation, client-save prohibition | W5.9 fresh HOST/rejoin; W5.1, W5.7 complete saved-graph/isolation/recovery fixtures |
| Secure private admission, compatibility, duplicate identity, capacity, stale/replay/wrong/missing invites and restart rotation | W5.8 actual challenge-response negative matrix; W5.2 eight admitted slots/server-full; all original assertions retained |
| Bounded malformed traffic on real authenticated channels; healthy peer survives | W5.9 real ENet channels 1/3/4/5/6/7/8/9/10/11; W5.8 separate auth negatives and focused protocol tests |
| Normal crosshair RMB/E, actual inventory slots, Workbench/storage/Kiln/Rest Mat and Manual→Stone Kiln→Charcoal | Complete Repair 1 normal graphical launcher/input suite on candidate source |
| Five-player smoke and longer actual-process stability | W5.9 HOST + four remotes smoke, then HOST + two remotes continuous default 660-second soak; only measured player counts are reported |
| Portable current-version JOIN and clean cache | W5.9 kit file hashes, bundled fixed runtime/plugin, clean import, normal graphical JOIN creating its own identity |

Fixtures that create adversarial resources, set transforms or inject failure
are explicitly test-only and run in isolated projects/profiles. These do not
replace the connected legitimate progression and normal physical input proofs
in the full regression chain. The application has no new owner cheats/test flags.
The W5.9 fixture filters captured desktop mouse motion so several windows
sharing one cursor cannot rotate explicitly prepared aim. Visible GUI input
still dispatches normally; the retained Repair-1 normal-input suite is unchanged.

## Verification and repair policy

From `D:\AI\Projects\Leyforge-Rebuild`:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_5_part_9.ps1
~~~

The approved console runner is
`D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe`
(SHA-256 `06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A`).
Only its pinned adjacent graphical executable is used for rendered runs. No
4.6.3/4.7.1/quarantined runner or plugin substitution is allowed.

Each run creates `.verification/wave5/w5_9/run-<UTC>/gate.json`, source and raw
working manifests, checks/focused reports, process logs, graphical screenshots,
metric traces, persistence hashes, complete regression receipts and failure
classification. External projects and profiles are retained for diagnosis.
Failed receipts are append-only. `-SkipRegression` or a soak shorter than 600
seconds is diagnostic/uncertified. A final receipt must have `passed=true`,
`certified=true`, `snapshot_matches_source=true`, secret scan PASS and the full
regression chain. Final source changes invalidate prior certification.

Repair any in-scope authority/duplication/persistence/teardown defect; reproduce
the failure, retain its receipt, and rerun failed-case plus complete regression
after repair. A critical unresolved failure or out-of-scope repair blocks W5.9.
Publication is allowed only after the full automated gate, exact owned-path/hunk
staging, whitespace/integrity checks and final source review. Preserve unrelated
editor bytes, UID sidecars, owner identities/saves and original W5.8 evidence.

## Metrics and limits of measurement

Use the gate's actual `network_quality`, `soak_metrics.json` and
`host-metrics.json` / `client-metrics.json` / `third-metrics.json` values.
They record elapsed time, frame intervals, engine process/physics time, static
engine memory, sampled Windows working set, node/orphan counts, terrain statistics,
interest counts, application transport packet/byte counters, queue sizes and
command activity. Lifecycle control sends and gameplay sends are separate
counters; bounded receive counters include control. Rates derive
from counter deltas/time. Static allocation is not total process working set.
Fixture serialization and several rendered processes affect frame timings.
Report hardware/runner context and observed growth; one development machine
cannot establish production FPS or eight-player performance guarantees.

W5.8 quality results include measured ping/connection/handshake readiness,
reconciliation error, voxel propagation, resource transaction and disconnect
latency. Normal-input functional context opening and survival convergence are
bounded by the actual rendered regression checks. Simulated conditions prove
resilience only; no WAN or physical-machine LAN result is inferred.

## Exact owner launch commands

HOST (world `wave5-w59-owner-test`, seed 184552221, UDP 25652, canonical owner
`user://identity/local_profile.json`):

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_9_host.ps1'
~~~

Local JOIN (same durable Client 2 `user://identity/development/wave5-client-2.json`):

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_9_join.ps1'
~~~

Build a committed, source-matched certified LAN kit:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\build_wave_5_part_9_lan_join_kit.ps1'
~~~

On the second physical PC, extract the whole kit and run from its folder:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\run_wave_5_part_9_lan_join.ps1 -Address '<HOST LAN ADDRESS>' -Port 25652
~~~

HOST presses F8; enter its current invite in the masked JOIN prompt. The portable
launcher accepts Address/Port and optional GodotRoot, creates that computer's
own identity and embeds no owner drive path. Bundle includes runtime/plugin,
canonical source/content, notices, README, source commit and hashes; no Git,
Python or installed Godot is needed. Owner saves, profiles, invite secrets, Git,
caches, logs and verification evidence are excluded. Precommit kits are explicitly
uncertified verification candidates. Distribute the committed certified kit only.

## Owner LAN acceptance gate

Use two separate physical computers on the same LAN, JOIN connecting to HOST's
LAN address. No WAN forwarding, UPnP or overlay requirement. Play approximately
15 minutes: both move/jump/sprint, mine/place, use drops/inventory/tools,
gather/craft, open Workbench/storage/Kiln/Rest Mat by normal input, read Manual,
craft Kiln/Charcoal and check independent survival. Compete for one block/drop,
shared storage and Kiln output; no duplicates or lost legitimate resources.
Disconnect/reconnect the same identity, then HOST F10. JOIN must leave gameplay
and see ended view; restart HOST/new invite and verify saved world/characters.

Keep network addresses and invites private. Record:

~~~text
Build/commit:
Two separate PCs:
Connection type:
LAN address used (do not publish):
Invite accepted:
Session duration:
Movement:
Voxel edits:
Drops/inventory:
Crafting/functional objects:
Survival:
Contention:
Reconnect:
Host shutdown:
Save/reload:
Any notable lag:
Bugs:
Overall acceptance decision:
~~~

Codex cannot certify a physical LAN session it did not conduct. Until the owner
reports it: **LAN HUMAN ACCEPTANCE REQUIRED**. Only after automated W5.9 PASS,
owner local/LAN acceptance, no blocking correctness issue and issue classification
may Wave 5 close. Never mark it fully closed before that report.

## Residual networking work and handoff

Direct WAN is unverified/deferred. CGNAT limitations, NAT traversal, relay,
internet matchmaking/discovery/friends/one-click expiring invites, account/backend
assessment, secure transport and internet-scale testing belong to Wave 17.
ENet gameplay is unencrypted; UUID is not strong account ownership proof.
No host migration or dedicated server is implemented; crash restores only the
last successful HOST save. High-player-count performance remains bounded to
actual measurements. Preserve Wave 17's combat/settlements/machines/vehicles/
vessels/portals/realms/advanced save/resync/dedicated-server planning.

The [Wave 6 readiness handoff](WAVE_5_TO_WAVE_6_READINESS_HANDOFF.md) describes
stable interfaces and future hazards only. **No Wave 6 implementation has begun.**
