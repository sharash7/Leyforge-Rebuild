# Wave 5 Part 5: Resources, inventory and authoritative transactions

Application `0.5.6-wave5-w5.5`; network protocol **4**; save/content/worldgen **4/1/2**. W5.4 was accepted by the owner at `275615fb9a7032d56f868fe7853fb7e82470c937`. W5.5 automated certification requires a complete, source-pinned `gate.json` from the verifier below. W5.5 is **AUTOMATED CERTIFIED + OWNER ACCEPTED** at `0.5.6-wave5-w5.5` / `69cd29a4a50a540b7b2b9796ed10ad22f04be301`. The owner confirmed shared drops, independent Client 2 inventory/hotbar/equipment, tools/durability, finite sources, crafting/Workbench, placement, storage, kiln and resource persistence/reconnect. Survival was intentionally deferred to W5.6.

## Authority and the resource seam

HOST owns every world-local character inventory, equipment, crafting staging grid, drop, finite source, storage and kiln. Transport peer binding selects the actor. Requests cannot supply actors, survival changes, positions, item definitions, outputs or instance IDs. HOST revalidates canonical stacks, revisions, range, world relevance, actual body/aim, capability and context before committing.

`LfeResourceTransactions` routes commands to the existing gameplay/item primitives and the live world adapter. The inventory panel uses the same command seam in HOST/OFFLINE and JOIN. JOIN has session-only `LfeResourceReplica` views and ordinary display inventories; it creates no gameplay authority, character authority record or world-save object. UI mutations are commands, never changes to these views. A queued request is pending until the authoritative result arrives; independent state-channel publication supplies its visible facts. Incompatible occupied slots use one swap command. Craft outputs remain previews until HOST commits them.

Every command carries a sequence, random 128-bit transaction ID, operation, bounded arguments and expected domain revisions. HOST retains the last **256 completed results per character in this host session**, including rejected results. Exact retries return that result; reusing an ID for another payload or actor fails. Cache state survives transport reconnect, not host restart. Sequences reject conflicting old requests and jumps over 4096. Token bucket: 40 requests/sec, burst 16 per peer; resync requests are limited to 5/sec. Clients have one pending command, retry its identical packet after 500 ms, and disconnect after 10 seconds without a result. There is no durable retry journal.

## Replication and bounds

Channels 1–5 preserve admission, movement and voxel roles. Reliable channel **6** carries resource facts and the initial snapshot barrier; reliable **7** carries commands/results/resync; unreliable ordered **8** carries drop positions at **10 Hz**. HOST publishes resource revisions at 10 Hz, including canonical kiln progress. Resource relevance is 96 m plus loaded-region checks; private player/grid streams are owner-only. Leaving relevance removes presentation facts without deleting HOST records.

Streams are `player/id`, `grid/id`, `drop/id`, `source/id`, `storage/id` and `object/id`. Each changed domain receives a monotonic revision and a bounded replacement delta with its expected previous revision. Initial and resync replacements have no previous-revision requirement. Each transfer has a unique ID, part count, hash and 460-byte data chunks; maximum 128 parts, 2048 visible streams, 32 concurrent receive assemblies, five-second assembly deadline. Queue maximum is 4096 parts with eight drained per physics frame. Overflow disconnects safely. No fragment becomes visible until its complete content, hash and canonical schema validate. Gaps/conflicting parts/expiry request a current replacement. Readiness requires the complete initial relevant stream/revision digest, including private inventory, rather than the first personal fragment.

## Transactions and conservation

Pickup/drop/merge preserve quantities and tool identities. Dropped items retain the existing 1.2-second pickup cooldown. HOST derives drop location and grounding. Finite source harvesting uses actual held input and a renewable 300-ms lease; changing target/tool, losing range/line of sight, disconnecting or releasing cancels work. The final canonical source transaction depletes once and applies its output and wear. Dense Stone requires capability 2 and yields six Stone; food and water caches yield four each. These items can be moved, stored or dropped.

Placement validates the selected owned stack, previous voxel, loaded terrain, body-derived ray, player overlap and functional record limit. Inventory consumption is prepared, then voxel/functional placement commits, or consumption is abandoned. Same-cell contenders cannot both commit. No legacy development placement bypass is exposed to JOIN.

Craft staging is personal even at a shared Workbench. Canonical 2x2/3x3 recipes produce outputs into the owner backpack. Disconnect returns staging where possible; a full backpack retains it. Saving resolves every actor grid first or visibly fails. Shared storage and kiln input/fuel/output use the same transaction primitives. Output endpoints permit withdrawal only. Kiln process state advances on HOST while either UI is open. Schema v4 already stores these resources and stateful identities; no save migration is required.

The verifier audits quantities across all players, equipment, personal staging, drops, storage and kiln channels, and global instance uniqueness. Crafting, harvesting and processing are explicit transformations with canonical input/output accounting. Test-only adversarial kiln fixtures are labelled separately from the legitimate timber-to-Workbench-to-tool progression.

## Verification

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\AI\Projects\Leyforge-Rebuild\tools\development\verify_wave_5_part_5.ps1
```

The gate runs detached protocol/transaction/corruption tests, real rendered HOST plus two distinct JOIN processes, physical drop and walking pickup, legitimate timber/Workbench/Wooden Pickaxe/Stone Pickaxe/Dense Stone progression, food/water, shared storage/kiln, synchronized same-drop/source/storage/kiln/placement races, retries/lost result, staged disconnect, save/reload and client-save negatives. It also runs clean-cache normal graphical owner launchers and the complete W5.4-to-Wave-0 regression chain. `-SkipRegression` is diagnostic only and never produces a certified receipt. Append-only evidence lives at `.verification/wave5/w5_5/run-UTC/`; failed receipts are retained. Source and approved-runner hashes are pinned. Publication projection excludes unrelated editor scene/project changes and untracked UID sidecars; the raw working bytes are separately preserved and checked.

## Owner manual acceptance

Run these from PowerShell as two normal windows, using the default persistent world and distinct stable identity:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_5_host.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File D:\AI\Projects\Leyforge-Rebuild\tools\development\run_wave_5_part_5_join.ps1
```

Defaults: HOST world `wave5-w55-owner-test`, seed 184552221, UDP 25652, canonical `user://identity/local_profile.json`; JOIN loopback and `user://identity/development/wave5-client-2.json`, matching the accepted Client 2 identity convention. Launchers import before graphical launch using the shutdown-fixed Godot 4.8-dev runner. Automation uses disposable project/profile roots; it never launches against shared save fixtures.

1. Break Dirt or timber with held LMB. Confirm both see the physical drop. Walk JOIN into it and confirm only JOIN inventory gains it; Q drops the selected item and HOST can walk into it.
2. Use I for backpack, number keys for selection, and the slot UI to split/transfer/swap/equip. Confirm independent inventory and exact tool wear.
3. Gather three logs; craft planks and sticks in 2x2, build/place a Workbench, then craft Wooden Pickaxe in its 3x3 grid. Mine three Stone and craft Stone Pickaxe. Hold LMB on Dense Stone; confirm six Stone, one depletion and wear on the exact equipped tool.
4. Gather food/water caches and move their items through inventory/drop/storage. Open the same crate in both windows; deposit/withdraw once. Populate kiln input and fuel, start once, observe shared progress and withdraw its canonical output.
5. Place owned ordinary and functional blocks; attempt occupied/inside-player/out-of-range targets. Failures must retain items. Stage an ingredient, close JOIN, reconnect with the same launcher, and confirm exact ownership. Save/close HOST, restart both and verify persisted resources and tool identities.

Record the owner's actual observations separately; automation does not certify this human acceptance.

## W5.6 boundary

Health, stamina, hunger, thirst, fatigue and exposure are not replicated. JOIN consumption survival effects, Rest Mat survival behavior and remote death/recovery synchronization remain deferred. No LAN/WAN certification, relay, UPnP, dedicated server, host migration or PvP is claimed.
