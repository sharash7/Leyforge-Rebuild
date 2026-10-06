# Wave 5 Part 6: Authoritative survival and the shared Wave-4 loop

## Owner acceptance recorded for W5.6 repair 1

**AUTOMATED CERTIFIED + OWNER ACCEPTED**

Accepted build: **0.5.8-wave5-w5.6**.
Accepted SHA: **cced5167004e3056c150bbd16fee25252c665843**.
Accepted commit: fix: complete W5.6 owner survival and interactions.

The owner manually retested and confirmed functional objects, smoothed drops,
Thirst, Fatigue, Exposure, the Crafting Manual, and no noticeable gameplay blockers.
The longstanding JOIN world remaining after HOST exits is assigned to W5.7;
it does not reopen W5.6. Wave 5 remains in progress.

Initial automated candidate application `0.5.7-wave5-w5.6`; protocol **5**; save/content/current
worldgen **4/1/2**, with stored worldgen v1 supported. W5.5 is AUTOMATED
CERTIFIED + OWNER ACCEPTED at `0.5.6-wave5-w5.5` /
`69cd29a4a50a540b7b2b9796ed10ad22f04be301`. W5.6 automated certification
requires a complete source-pinned `gate.json` from the verifier below. Owner
acceptance is recorded above. Wave 5 remains in progress.

## Owner acceptance repair 1

Owner findings require [repair 1](WAVE_5_PART_6_OWNER_ACCEPTANCE_REPAIR_1.md).
Accepted repaired build is 0.5.8-wave5-w5.6; protocol/save/content/worldgen stay 5/4/1/2.
The original qualification remains historical; owner repair retest is accepted above. Repair 1 fixes physical functional interactions, smooths JOIN drops,
adds the canonical Manual and explicitly amends Standard hydration/fatigue/
exposure. Tuning below describes initial 0.5.7 certification, not repaired canon.

## Authority and biology

HOST alone owns each character's health, stamina, hunger reserve, thirst
reserve, fatigue, exposure and recovery-delay/starvation/dehydration timing.
Values remain finite 0–100. The existing `LfeCharacterSurvival` is canonical.
JOIN sends legitimate movement, consume and Rest Mat intent, never damage,
health, shelter/rest facts, death or recovery decisions.

The host scene ticks after local and authoritative remote movement. World and
kiln time advances once per simulation step, then each active character's
biology receives the same delta with its own actual sprint, shelter and rest.
Inventory suppresses local controls while physics, both biology states and
workstations continue; SceneTree remains unpaused and time scale stays 1.
Disconnected records receive no biology steps and retain exact timing. Rejoin
resumes the retained character. Rest never skips or accelerates world time.

Standard production tuning is unchanged: hunger 4 reserve/hour, thirst
disabled, sprint cost 12/sec, regeneration 16/sec after spending/depletion
delays 1.25/2.25 seconds, sprint fatigue 0.18/min, covered awake rest recovery
0.05/min, benign outdoor exposure with sheltered recovery 2/min, health
regeneration 0.1/sec after 20 seconds when sufficiently nourished. Existing
starvation debt and Peaceful/Relaxed/Harsh hooks remain. No profile-settings
UI or test acceleration is exposed by owner launchers.

## Wire state, privacy and readiness

Exact owner views contain publication revision, discrete mutation revision,
health/stamina/hunger/thirst/fatigue/exposure, alive, thirst_enabled, bounded
profile metadata and authoritative sheltered/resting presentation facts.
Timing/debt remains HOST-owned and persisted, without exposing mutable objects.
Exact values are sent only to their owner; other avatars have no survival bars.

Reliable complete bootstrap precedes a ready survival HUD. Periodic complete
replacements publish at at most 10 Hz; only newer revisions apply. Missing
periodic packets require no replay. Damage, consume commit, rest changes and
recovery publish reliably. Consume retains the W5.5 expected resource revision
and canonical stack plus a survival mutation revision. Continuous hunger and
regeneration do not create a new mutation conflict every physics step.

Packets use strict UTF-8 JSON, exact keys, finite 0–100 numbers, bounded integer
revisions, strict booleans and known coherent profile metadata; maximum 1024
bytes. Resync contains no actor ID and HOST resolves its private response from
the authenticated binding. HOST limits requests to 5/sec. A missing/stale owner
view after three seconds requests current state every 0.5 seconds; an unresolved
wait ends the session after ten seconds. Movement/world/resource readiness keeps
its existing independent bounds.

| Channel | Traffic | Transfer |
| --- | --- | --- |
| 1 | movement intent, 30 Hz | unreliable ordered |
| 2 | movement replacement, 20 Hz | unreliable ordered |
| 3 | movement bootstrap, presence, recovery reset | reliable |
| 4 | voxel snapshots/deltas | reliable |
| 5 | voxel actions/results/resync | reliable |
| 6 | resource facts/bootstrap | reliable |
| 7 | resource/consume/rest transactions/results/resync | reliable |
| 8 | drop positions, 10 Hz | unreliable ordered |
| 9 | survival bootstrap/events/resync | reliable |
| 10 | complete survival replacement, at most 10 Hz | unreliable ordered |

ENet capacity is 11 including reserved channel 0. Historical protocols are
W5.2=1, W5.3=2, W5.4=3, W5.5=4, W5.6=5. Older builds reject with
`protocol_mismatch` before build-version comparison.

## Movement, shelter, consumption and recovery

HOST decides sprint from the correct actor's alive/stamina/fatigue state and
actual movement result. Holding Shift while stationary/blocked does not drain
stamina. JOIN predicts availability from its latest owner view; normal movement
reconciliation resolves stale predictions. Walking remains possible when sprint
is denied. Local and remote landings use the shared rule: speed greater than
12 m/s causes `min(100, (fall_speed - 12) * 3)` damage on HOST. Opening Inventory
does not stop falling or grant immunity. No client damage command exists.

Shelter queries use authoritative voxels around the actor, independent of HOST
camera interest: solid overhead cover within four cells and at least three
cardinal sides within three cells. Each actor has its own half-second cache.
Rest Mat intent validates object/function, active/alive body, loaded relevance,
three-metre proximity and current shelter. Movement, death, disconnect, leaving
range, removal or invalid cover cancels that actor's rest.

F submits selected-slot consume through the existing idempotent resource ledger.
Canonical consume prepares both inventory removal and survival before publishing
either. Provisions restore up to +30 hunger without instant health. Full hunger
consumes nothing. Standard Drinking Water remains a no-op, preserves stored
thirst and the item, and hydration stays hidden. Harsh focused fixtures expose
hydration and use the same atomic transaction. An exact retry returns the
retained result; changed payload under the same transaction ID rejects.

HOST detects death through all biology paths, cancels harvest/rest/held actions,
clears movement, finds existing bounded safe spawn using voxels/sources/players,
teleports the body safely, retains inventory/equipment/staging/world resources,
and invokes canonical health=50/stamina=50 recovery. Remote recovery increments
input and presence epochs and sends a reliable reset. Old input epochs reject;
old snapshots cannot reconcile the recovered body. Prediction intent and other
peers' interpolation histories clear. Recovery requires no reconnect.

## HUD and persistence

The shared development survival panel consumes authoritative local facts in
HOST/OFFLINE and `LfeSurvivalReplica` in JOIN. It displays Health, Stamina, Food,
Fatigue, Exposure and shelter/rest status. Water appears only when the active
profile enables thirst. Before bootstrap it displays Synchronizing survival.
It never predicts health or consumption effects.

The existing HOST save includes all character values and timing/debt alongside
resources and transforms. No save migration or client world save is added.
Disconnect cancels transient rest and gathering while preserving durable state;
save/quit retains existing safe crafting staging release/retention rules.

## Owner commands and acceptance

HOST:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_6_host.ps1
```

CLIENT / JOIN:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_6_join.ps1
```

Defaults: HOST `wave5-w56-owner-test`, seed 184552221, port 25652, canonical
`user://identity/local_profile.json`; JOIN `127.0.0.1:25652` and the same durable
`user://identity/development/wave5-client-2.json`. Import-first launchers use the
approved fixed Godot console/editor pair and delete no cache, save or profile.

Check independent HUDs; sprint/recovery with Client and Host Inventory open;
harvest provisions and consume below full Food; verify full Food and Standard
water consume no item; take a legitimate high fall; use a covered/enclosed Rest
Mat and move to cancel; close/rejoin Client with non-default biology; save/quit
HOST and restart both. Retain the accepted movement/voxel/drop/tool/crafting/
Workbench/storage/kiln loop while doing so. Owner judgement remains separate.

## Verification and boundary

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\AI\Projects\Leyforge-Rebuild\tools\development\verify_wave_5_part_6.ps1
```

Append-only evidence lives at `.verification/wave5/w5_6/run-UTC/`: source hashes,
focused protocol/transaction tests, actual separate rendered ENet HOST/JOIN/
third identity, bootstrap/stamina/consume/rest/fall/recovery/reset/reconnect/
save traces, one/two/three-player world/kiln invariant and exact graphical
launchers from missing class cache. Complete W5.5 and all earlier regression
receipts are required for certification; skip modes remain uncertified. Failed
runs remain available. Source projection preserves unrelated editor/project
changes and UID sidecars separately, excluding them from publication.

No downed/revival, combat/PvP, temperature/weather, mana, tombstones or inventory
death loss; no LAN/WAN qualification, relay, UPnP, dedicated server or host
migration. W5.7 reconnect/persistence failure hardening has not begun.
