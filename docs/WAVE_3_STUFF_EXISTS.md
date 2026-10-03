# Wave 3 - Stuff Exists

Wave 3 makes matter conserved, authoritative gameplay state:

> Break a voxel -> see its physical drop -> pick it up -> manage inventory -> select a hotbar stack -> place one voxel -> transfer to/from storage -> save -> quit -> restart -> continue using the restored resources.

Normal play starts with an empty inventory. Basic terrain blocks produce their own canonical content when broken; pickup is a separate physical interaction. Wave 4 survival, tools, crafting and processing remain outside this implementation.

## Canonical content and identity

The existing `content/blocks/wave_1_blocks.json` remains the canonical catalog, resolved by `src/lfe/content/block_catalog.gd`. Its five blocks are unchanged in identity and numeric terrain mapping. Air has no inventory projection. Grass, Dirt, Stone and Sand expose inventory capability, stack capacity 64, placement and a simple same-content drop projection on the original block definition.

A block is never registered again as a separate item. `leyforge:stone` is the same canonical identity in generated terrain, a stack, a drop and placement. The runtime voxel number serves the blocky mesher; save data and stacks use the canonical string.

The same catalog supports optional item-only definitions in its `items` array. These occupy the same canonical ID namespace, have no voxel mapping, and may declare compatible equipment slots. There are currently no production item-only definitions or equippable items. Focused and rendered verification use an isolated `test:hand_token` fixture outside the repository to prove this path. Only explicit `--wave3-playtest` runs can use `--wave3-test-content=<absolute-fixture>`.

The fixed representative container has one canonical definition in `content/world_objects/wave_3_crate.json`. It is a storage object, rather than a duplicate block/item definition.

## Runtime ownership and transactions

Reusable state lives under LFE:

- `src/lfe/transactions/item_stack.gd`: canonical content plus positive integer quantity within its definition's limit.
- `inventory.gd`: bounded containers, validated restore and detached read snapshots.
- `item_transactions.gd`: add/remove, move/merge/split, swap and transfer.
- `src/lfe/entities/resource_state.gd`: authoritative player inventory, hotbar selection, equipment, drop instances and world storage.
- `src/lfe/persistence/world_save.gd`: validated atomic world persistence and v1 migration.

Transactions prepare detached state, validate both endpoints, then publish synchronously without intermediate UI callbacks. Full transfers reject without mutation if the requested quantity cannot fit. Explicit partial transfers publish only the accepted quantity and preserve the source remainder. Equipment uses this same transfer seam with slot compatibility checks.

Player placement validates range, streamed/editable data, an empty target and body collision before invoking inventory-to-voxel conversion. The resource runtime stages removal, calls the synchronous world-edit operation, and consumes exactly one only after success. Breaking similarly commits the voxel removal before publishing the corresponding drop. A reentrant conversion/pickup guard protects the conversion interval. These are local authoritative operations ready for a future host/server orchestration layer; they do not implement networking.

The game-facing world, player controller, resource presenter and inventory panel live under `src/game/`. UI handlers request validated operations and never edit authoritative slot arrays directly.

## Inventory, hotbar and equipment

There is one 27-slot player inventory: nine hotbar slots and eighteen backpack slots. The hotbar displays the first nine slots directly; it has no copied stacks. Number keys and mouse-wheel cycling select a bounded quick slot, which persists separately from legacy development block selection.

The inventory panel supports click movement and merging, right-click splitting into a destination, swapping unlike stacks and shift-click transfers to/from an open crate. Selected sources are highlighted; stack counts and rejection feedback are visible. Empty slots use `null` in serialized state.

Equipment has two named foundation slots, `hand` and `body`. Only definitions compatible with the destination slot can move there. The panel exposes the state and the validated inventory transfer path. Protection, damage, durability, harvesting tiers and other equipment gameplay are deferred.

## Physical drops and pickup

A drop contains a cryptographically generated 128-bit instance identity, canonical stack and bounded world position. Instance identity is independent of node order, inventory slot and world-generation RNG.

The placeholder is an anchored quarter-voxel cube with a collision shape and quantity label. Anchoring gives it a stable physical presence while terrain streams; it does not fall through unloaded terrain. It is intentionally not a gravity/attraction simulation.

Approaching within 1.65 units of the player's body center triggers the authoritative pickup path. A short transient delay allows a newly created drop to be seen. A full inventory leaves it unchanged. Partial pickup moves the accepted quantity and leaves the exact remainder with the same world instance ID. A fully collected ID is removed only after inventory acceptance; repeating pickup against that ID returns zero.

Manual drops consume one or the selected entire stack and spawn outside the immediate pickup radius. A blocked/unloaded drop location rejects without consuming anything. Multiple identical drops remain separate instances. Nearby drop merging is deliberately deferred.

Drop state and presentation belong to the world app, independently of streamed voxel chunks. Moving a viewer far enough to unload the terrain and returning cannot remove or duplicate these instances.

## Persistent storage

A single fixed nine-slot crate is established near the deterministic origin spawn for new/migrated worlds. Its generated stable ID, canonical object ID, position and bounded slot contents persist. Loading an existing crate restores its original position even if the player last saved far away.

Approach within four units and press E to open storage. Transfers in either direction use the same inventory transaction runtime, including merging, partial capacity and rollback. The crate cannot be placed, moved or broken in Wave 3, so stored contents cannot be silently destroyed through a break operation. It is independent of voxel streaming and isolated by world ID.

## Save v2 and v1 migration

The save envelope and metadata now use `save_version = 2`. `worldgen_version = 1` and `content_version = 1` remain unchanged. Deterministic terrain generation is unchanged.

The existing payload retains metadata, player position/yaw/pitch and sparse canonical voxel overrides. Its new `resources` object contains:

- the 27 inventory slots;
- the selected hotbar index (0-8);
- the two equipment slots;
- drops with stable instance ID, canonical stack and position;
- storage objects with stable instance ID, canonical container ID, position and nine slots.

All item quantities normalize to integers on validated load. JSON payloads preserve full numeric precision, including player and entity coordinates. Every resource structure is validated before publishing or saving: unknown IDs, invalid counts, wrong slot lengths, incompatible equipment, duplicate/cross-kind entity IDs, invalid positions and unknown container definitions reject the save.

A valid Wave 2 v1 file loads in memory with its exact world ID, name, seed, timestamps, player state and voxel overrides intact. It initializes empty inventory/equipment/drops/storage and selected slot zero. The actual game then establishes its representative empty crate. Merely opening a v1 file does not rewrite it. The next successful explicit or controlled-quit save writes v2 through the existing atomic path and retains the original v1 as the previous copy.

The pending-write/readback/checksum/rotation/promotion lifecycle remains active. Malformed primary data rejects startup and disables saving. A missing primary may recover its previous copy; a malformed existing primary is preserved for explicit operator repair. Pending files remain non-authoritative. External changes or disappearance of a loaded authoritative file prevent overwrite. The newly persisted state survives this recovery path too.

## Controls

| Control | Action |
| --- | --- |
| WASD / mouse / Space / Shift | Existing move, look, jump and sprint |
| Left mouse | Break targeted voxel into a physical drop |
| Right mouse | Place one unit from selected placeable hotbar stack |
| 1-9 | Select hotbar slot |
| Mouse wheel | Cycle hotbar, wrapping at the ends |
| I | Open/close inventory |
| E near the crate | Open inventory and storage |
| Left-click source, then destination | Move/merge, or swap unlike stacks |
| Right-click destination after selecting source | Move half the source stack (at least one), respecting capacity |
| Shift-click stack with storage open | Transfer as much as fits to/from storage |
| Q / Shift-Q | Drop one / the entire selected stack |
| Approach physical drop | Pick up as much as fits |
| F5 | Save |
| F10 / close window | Save, then quit only after success |
| Escape | Close inventory, or release the mouse |

Movement and voxel actions pause while inventory is open. Click the world after releasing the mouse to recapture it. Earlier Wave 1/2 regression drivers and explicit `--development-blocks` retain the infinite development selector (Q cycles blocks); normal gameplay uses conserved inventory.

## Verification

Production target remains Godot `4.7.2-stable`. Qualification here uses the approved fixed local runner:

`D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe`

Reported version: `4.8.dev.custom_build.a9c94cd21`. No intentional 4.8-only gameplay APIs are used. Exact 4.7.2 qualification remains separate when an approved executable is available.

Run from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/development/verify_wave_1.ps1 -GodotExecutable '<approved-fixed-console-runner>'
powershell -NoProfile -ExecutionPolicy Bypass -File tools/development/verify_wave_2.ps1 -GodotExecutable '<approved-fixed-console-runner>'
powershell -NoProfile -ExecutionPolicy Bypass -File tools/development/verify_wave_3.ps1
```

Wave 1 also invokes the Wave 0 plugin/environment gate. Wave 3 uses isolated temporary profiles and external disposable save roots, with process timeouts and script-error checks. It writes only ignored output under `.verification/wave3/`; generated saves and transient test definitions are not committed.

Focused tests cover canonical projection, item-only fixtures, runtime ID remapping, bounded stacks, container operations, equipment compatibility, partial/full pickup, repeated pickup, storage rollback, exact conservation, resource serialization, migration, malformed v1/v2, previous recovery and external-authority protection. A known quantity travels inventory -> drop -> inventory -> storage -> inventory -> placed voxel -> broken voxel -> drop -> inventory, followed by 300 deterministic randomized conservation checks.

Five rendered processes exercise:

1. A: actual player movement, break/drop/proximity pickup, inventory UI handlers, hotbar controls, collision/invalid placement rejection, exact final-unit consumption, break-after-place conservation, storage, manual drop, equipment fixture, negative-boundary edits, confirmed chunk unload/return, save and process exit.
2. B: exact restoration of player, inventory, hotbar, equipment, crate and drops, confirmed streaming, continued pickup/transfer and another successful save.
3. C: a separate world ID with the same seed, identical generated terrain and isolated player/voxel/resource state.
4. M: actual startup of a disposable v1 fixture, valid defaults, preserved edits/player, explicit v2 save and original v1 previous copy.
5. N: a fresh process restoring that migrated v2 state.

JSON reports, console logs and ten evidence frames accompany the rendered gate. `-SkipRenderedPlaytest` is an environment convenience; it cannot certify the complete Wave 3 exit gate.

## Deliberate limits and Wave 4 boundary

This is a local single-player resource foundation with small content and development-quality UI. There are no production equippables yet. Storage is one fixed crate; drops are anchored placeholders without merging or attraction. The save bounds drops at 10,000 and supports one representative storage object. Large-world entity partitioning, concurrent writers, server replication, ownership, nested containers, NPC/machine inventories and databases remain future work.

No Forge work was necessary: editing the five canonical block projections and one crate definition presented no repetitive authoring workflow that justified a Forge slice. Forge and Forge-ENG workspaces remain untouched.

Crafting, processing, furnaces, survival needs, harvesting tools/tiers, durability, combat, armour effects, automation, NPCs and multiplayer are not implemented. Wave 4 may transform resources only after this conserved foundation is accepted.
