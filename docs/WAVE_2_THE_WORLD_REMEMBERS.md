# Wave 2 — The World Remembers

Wave 2 adds a persistent world to the Wave 1 streamed terrain and player loop:

> Select or create world → generate from its seed → break and place blocks → move → save → quit → relaunch → restore the same world, edits, and player state.

The main scene remains `res://scenes/main/wave_1_playground.tscn`; the scene now hosts Wave 2 behavior. Wave 3 items and inventory are not part of this increment.

## World identity and selection

A world ID is an independent, stable save identity. The default development ID is `development`. Use `--world-id=<id>` after Godot's `--` separator to select another world. IDs are 1–64 ASCII letters, digits, underscores, or hyphens. A seed is not a world ID: two IDs can use the same seed and retain different edits and player positions.

For a new world, `--seed=<numeric-or-text>` resolves through the existing deterministic seed function. An existing world always loads its stored seed. Passing an explicit, conflicting seed rejects startup and leaves the saved world untouched. The stored metadata includes the world ID, development display name, normalized seed, save version, worldgen version, content version, creation time, and last save time.

The production save root is `user://worlds/<world_id>/`. `--world-root=<absolute-path>` is a development and test override; the game refuses roots inside the repository. World saves and isolated verification profiles are not tracked by Git.

## Schema and compatibility

The initial format is `save_version = 1`, `worldgen_version = 1`, and `content_version = 1`. The authoritative file is `world.json` in the world directory. It has an envelope with a version, a JSON payload string, and the payload's SHA-256 checksum. The payload contains:

- `metadata`: world identity, seed, format/generator/content versions, and timestamps.
- `player`: `position` as three finite numbers, `yaw`, `pitch`, and the optional selected development block's canonical ID.
- `voxel_overrides`: a sparse array of `{ "position": [x, y, z], "block": "leyforge:..." }` entries.

No generated terrain array or transient numeric voxel IDs are saved. An edit that restores the deterministic base voxel removes its override. At load, every saved canonical block ID is resolved through the current catalog to the current runtime voxel number. Unknown IDs, duplicate/invalid coordinates, malformed player data, unsupported save/content/worldgen versions, and checksum mismatches reject the world clearly. A future migration can branch at the save version check; no speculative migrations are implemented.

The terrain generator uses the stored seed and worldgen version 1 rules. Its worker callbacks take a locked snapshot of sparse overrides relevant to each generated block, including blocks filled by fast Air/Stone paths. Loaded edits remain available after blocks stream out and regenerate. The player interaction signals record changes; the player controller does not write files.

## Safe player restoration

The saved position is checked against the deterministic base plus overrides before the player becomes active. The check requires clear body space and nearby solid support. An unsafe position uses the deterministic origin-area safe spawn and emits `WAVE_2_PLAYER_FALLBACK` with the reason. The view orientation and development block selection are retained in that fallback; valid positions restore the position, yaw, pitch, and development block selection. The fallback searches a bounded area near the origin and fails startup clearly if it finds no safe position. Runtime movement waits until the streamed area and its collision are ready.

## Save lifecycle and integrity

F5 performs a synchronous save and shows `Saved`. F10 saves and quits only after success. Closing the window follows the same controlled path. A failed save reports an error and keeps the process open. Startup loads an existing world or creates an unsaved new state; the first explicit or controlled-quit save writes the initial file. The overlay shows world ID, seed, save version, dirty/saved status, override count, and the last load/save status.

A save is serialized and checked, written to `world.json.pending`, flushed and closed, then read back and validated. The current authoritative file is moved to `world.json.previous` before the validated pending file is promoted to `world.json`. A crash after moving the primary but before promotion leaves the previous copy loadable. If the primary is missing, the loader can open that previous copy and reports recovery. A malformed existing primary is rejected even when a previous copy exists; it is never silently overwritten. A failed world load disables saving. Save also refuses to replace an authoritative file whose bytes changed or disappeared since load, guarding against external edits or corruption during play. Interrupted `.pending` files are non-authoritative.

This is a small integrity foundation, not a complete future save migration or recovery interface. Explicit cleanup or repair of a corrupt primary remains an operator action. Sudden OS termination can still lose unsaved in-memory changes.

## Verification

Production target: Godot `4.7.2-stable`. Approved local verification runner:

`D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe`

Run both gates from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_1.ps1 `
  -GodotExecutable 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_2.ps1 `
  -GodotExecutable 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe'
```

Wave 2's gate uses disposable external world/profile directories. Its focused tests cover identity and same-seed isolation, stored seed precedence, current and future versions, sparse break/place/negative/boundary edits, base-state collapse, player state, canonical ID remapping, unknown IDs, malformed authoritative data, and recovery from an interrupted promotion. It also launches an unsafe saved player position and requires a safe-spawn fallback, then launches a corrupt disposable world and requires exit code 1 with the authoritative file unchanged.

The rendered flow launches three separate processes. Run A moves the player, breaks four terrain voxels, places Grass/Dirt/Stone at three cells, streams those new edits out and back before saving, saves, and quits. Run B restores the exact player state and all seven voxel/collision states, streams the source area out and back, and rechecks them. Run C selects another world ID with the same seed and proves original terrain and independent player state. Frames and JSON reports are written to ignored `.verification/wave2/`.

## Current limits

- There is one local player and no World Library UI, autosave schedule, inventory, drops, or profile/settings model.
- The content and generator versions currently have one supported value. An incompatible version rejects load; migration work is deferred until a real version change.
- The save uses a single world JSON file and sparse edits. It does not yet address unbounded very large worlds, concurrent writers, or multiplayer authority.
- Exact `4.7.2-stable` qualification remains a separate follow-up when an approved executable is available. This increment uses no intentional 4.8-only API.
