# W5.6 owner acceptance repair 1

Status: W5.6 AUTOMATED CERTIFIED / OWNER ACCEPTANCE PENDING / REPAIR REQUIRED.
Only owner manual retest can close W5.6. W5.7 has not begun.

Candidate: **0.5.8-wave5-w5.6**. Starting automated build: 0.5.7-wave5-w5.6 /
7f55c612a098dd23e160ffa0f9b7757cfc7df317. Protocol remains **5**, save **4**,
content **1**, current worldgen **2**; stored worldgen v1 remains supported.
No durable record or wire schema changes.

## Findings, root causes and previous coverage gap

JOIN drop roots jumped directly to 10 Hz HOST position facts. Functional
interactions needed a complete physical normal-input proof. Standard hydration
and nearly invisible fatigue/exposure needed the owner's canon amendment.
Crafting needed a discoverable in-game guide to the real canonical recipes.

The prior resource tests sent stable object IDs directly to the transaction
seam. They proved validation/conservation but bypassed crosshair resolution.
JSON-decoded cells contain floats; array equality against integer cells failed
in the client replica. JOIN displayed the real Workbench prompt but resolved
no ID, so RMB fell through to placement. Accepted-build JSON and rendered
input reproductions are retained. E already reaches the same interaction
function and needed no separate input rewrite. The rendered slot proof found
a second failure: the high-layer noninteractive session status panel swallowed
craft-grid clicks. It and its label now ignore pointer events; the status layer sits behind
inventory/Manual, and biology stays readable above the open panel. Prior direct
transactions bypassed this UI obstruction as well. The origin crate was also
misclassified by JOIN's shared storage endpoint lookup: HOST accepted it, but
the panel immediately closed because it looked for a placed-object record.
The panel now identifies crates from the validated authoritative storage family.

## Functional interaction repair

Validated cells resolve with the canonical coordinate decoder. Normal RMB/E
resolve the actual stable target ID, submit the existing owner-bound command,
and open only after HOST acceptance plus matching grid/storage/station facts.
The origin crate uses its actual crosshair target instead of the first crate.

A functional voxel whose descriptor is arriving owns the interaction. JOIN
shows “Synchronizing object…” during a five-second bounded wait; no placement
fallthrough, fake ID or successful UI occurs. Looking away cancels; expiry
offers truthful retry feedback. HOST retains actor authentication, alive/ready
state, object/function existence, authoritative proximity/relevance and context
validation. Workbench staging stays private and conserved through close/death.

## Drop presentation repair

Only JOIN roots follow the latest HOST target at exponential follow rate
12/sec. Spawn is exact; corrections above **0.75 m** snap. Small corrections
converge and stop within 1 mm, without extrapolation. Bob/rotation stay on the
Visual child. Reliable merge/despawn hides/removes losing nodes immediately.
Pickup uses HOST record positions, never interpolated visuals. HOST quantities,
identities, clustering and 10 Hz traffic remain unchanged. Retained traces
record HOST positions, received targets and rendered roots for lag, convergence,
snap and ghost checks.

## Owner-directed survival canon amendment

These are intentional post-certification balance changes, using the same sole
LfeCharacterSurvival implementation.

| Standard rule | Production rate |
| --- | --- |
| Hunger | 4 reserve/hour |
| Thirst | enabled, 5 reserve/hour |
| Water | +35 up to 100; one serving only on effect |
| Sprint stamina | 12/sec |
| Stamina regeneration | 16/sec after existing 1.25/2.25 sec delays |
| Sprint fatigue | +1 point/min |
| Sheltered Rest Mat fatigue | -2 points/min |
| Ordinary walking/gathering fatigue | zero |
| Alive outdoor exposure | +0.5 point/min |
| Sheltered exposure | -2 points/min, once whether resting or awake |
| Health regeneration | existing 0.1/sec after 20 sec when nourished |

Peaceful/Relaxed retain disabled hydration; Harsh retains enabled hydration
and existing profile multipliers. No profile UI. Standard HOST/OFFLINE and
JOIN display Water. Full hydration and disabled-profile consumption are no-ops
retaining the item. Water/food still atomically prepare inventory and biology,
check expected state and reuse the W5.5 sequence/128-bit ID/cache/retry ledger.
Exact retries apply at most one item/effect; changed payloads/stale stacks reject.

Exposure is an interim cover reserve without weather, temperature, wetness,
disease or health damage. Active alive actor time and HOST per-actor shelter
drive it. Saved values/debt/delay load unchanged; rates apply afterward.
World/Kiln time advances once, then each active character advances separately.
Disconnected biology freezes. Inventory/Manual never pause physics, biology,
other players or Kiln time. Actual HOST sprint activity drains stamina; fatigue
100 still gates sprint. HOST landing speed retains min(100,(speed-12)*3) above
12 m/s. Death retains safe spawn, 50/50 health/stamina, resources and stale
movement epoch protection.

## Read-only canonical Crafting Manual

A visible Crafting Manual button is available in personal inventory/crafting,
Workbench and Kiln. OFFLINE/HOST/JOIN use the same local validated
LfeRecipeCatalog. Every runtime recipe appears once under Personal 2×2,
Workbench 3×3 or Kiln; future validated entries appear automatically.

Details show canonical names/counts, context, ingredients, shaped/shapeless
rules, explicit empty cells, allowed mirroring and station fuel/time. Shapeless
recipes invent no positions. Shaped patterns explain translation within the
grid and empty surrounding cells. No auto-fill/craft, queue or extra registry.
Escape closes Manual first, then normal inventory close releases staging.

The current catalogue has 14 entries; tests count dynamically. Stone Kiln
requires six Stone/two Oak Planks at a Workbench:

~~~
Stone      Stone   Stone
Stone      Empty   Stone
Oak Plank  Stone   Oak Plank
~~~

Canonical pattern: SSS / S S / PSP; horizontal mirror is disabled.
Charcoal Burn: two Oak Heartwood input + one Oak Heartwood fuel → two Charcoal,
eight world seconds. The Manual derives these facts from runtime definitions.

## Verification

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\verify_wave_5_part_6_repair_1.ps1'
~~~

Evidence: .verification/wave5/w5_6_repair_1/run-UTC/. Failures remain retained;
SkipRegression is diagnostic and uncertified. Publication/raw source manifests
are separate. Graphical proof uses exact normal W5.6 launchers and import-first
preparation from an isolated missing class cache. A temporary test-only autoload
attaches observation and physical Input/GUI events to the normal main scene.
Production scripts/content match the manifest; generated tests/instrumented
project have an explicit receipt. Normal launchers expose no test flags,
acceleration or gameplay cheats.

Separate rendered HOST/JOIN/third processes use actual ENet. Crosshair RMB/E,
slot clicks, buttons and F prove Workbench/storage/crate/Kiln/rest, Manual
access, displayed-pattern Kiln craft/placement, charcoal processing/output,
water and production rates. Focused checks cover profiles, bounds/no-ops,
unchanged saved state, catalogue completeness/future entries and cell identity.
Drop traces measure lag/convergence/snap/merge. Mandatory W5.6 regression retains
bootstrap, sprint/depletion/recovery, falls/spoofs, actor rest/shelter, safe
recovery/stale movement, private routing, reconnect/freeze/save restore, and
one/two/three-player world/Kiln time. The full chain covers Wave 0–4 and
W5.1–W5.5. Only explicit canon expectations change. Three identity/save comparisons use
the test suite's existing exact full-precision JSON number helper for newly
fractional fatigue/exposure; all durable fields remain checked, with no numeric
tolerance. The direct mismatch and exact serialized comparison are retained.

## Owner commands and retest

HOST:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_6_host.ps1'
~~~

CLIENT / JOIN:

~~~powershell
powershell -NoProfile -ExecutionPolicy Bypass -File 'D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_6_join.ps1'
~~~

Defaults: world wave5-w56-owner-test, seed 184552221, port 25652.
HOST identity user://identity/local_profile.json; SAME durable Client 2
user://identity/development/wave5-client-2.json. No cache/save/profile deletion.

1. Connect both windows; verify independent Health/Stamina/Food/Water/Fatigue/Exposure.
2. Harvest/drop matching items; JOIN sees smooth approach and immediate merge disappearance.
3. Physically open placed Workbench with RMB/E; verify 3×3 UI.
4. Open placed Storage Box/origin crate; deposit/withdraw shared contents.
5. Open inventory Manual; read Stone Kiln's full pattern.
6. Close Manual, physically open Workbench, arrange six Stone/two Planks, take output and place Kiln.
7. Physically open Kiln; read Charcoal Burn, add two timber/one fuel, fire and withdraw two Charcoal.
8. Sprint JOIN; own stamina drains/fatigue grows. Open inventory: recovery/biology continue and HOST stays playable.
9. After thirst declines, F water consumes one for +35 up to 100. At full hydration F retains it.
10. Outdoors Exposure rises; valid sheltered Rest Mat recovers Fatigue/Exposure. Move to cancel only your rest.
11. Close/rejoin Client, save/restart HOST and reconnect; verify same identity/resources/survival. Accepted legitimate fall/safe recovery remains available.

Human acceptance stays pending owner observations. W5.7 hardening is outside
scope. No downed/revival, combat/PvP, temperature/weather, mana, LAN/WAN, relay,
dedicated server or host migration is implemented or certified.
