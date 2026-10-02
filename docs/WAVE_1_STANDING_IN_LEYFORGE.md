# Wave 1 — Standing in Leyforge

Wave 1 is the first playable production slice:

> Launch → deterministic streamed voxel terrain → safe player spawn → move/look/jump/sprint → target → break/place.

It deliberately does not persist voxel edits. Wave 2 owns world identity, save versions, voxel-edit persistence, and player-state persistence.

## Runtime

The main scene is `res://scenes/main/wave_1_playground.tscn`.

The world uses `VoxelTerrain`, `VoxelGeneratorScript`, `VoxelMesherBlocky`, `VoxelBlockyLibrary`, `VoxelViewer`, and `VoxelTool` from the pinned Zylann Voxel Tools GDExtension. Terrain is generated as streamed blocks around the player; it is not a fixed handcrafted patch.

The default development seed is `184552221`. Supply another explicit numeric or text seed after Godot's `--` separator:

```powershell
& '<approved-godot-console.exe>' --path 'D:\AI\Projects\Leyforge-Rebuild' -- --seed=12345
& '<approved-godot-console.exe>' --path 'D:\AI\Projects\Leyforge-Rebuild' -- --seed=Leyforge
```

Numeric seeds are normalized to a positive 31-bit value. Text seeds use a stable FNV-1a-derived value. Terrain noise is a pure coordinate-and-seed function and never reads global random state.

## Canonical Wave 1 blocks

`content/blocks/wave_1_blocks.json` is the single canonical Wave 1 block definition.

| Canonical ID | Voxel ID | Runtime role |
| --- | ---: | --- |
| `leyforge:air` | 0 | empty, non-solid, non-breakable |
| `leyforge:grass` | 1 | grass surface, development-placeable |
| `leyforge:dirt` | 2 | grass subsurface, development-placeable |
| `leyforge:stone` | 3 | deep terrain/exposed steep high ground, development-placeable |
| `leyforge:sand` | 4 | low-elevation surface band, development-placeable |

The canonical string is the persistent content identity. The numeric voxel ID is an explicit runtime mapping required by the blocky mesher; it is validated for uniqueness and round-trip resolution rather than being treated as the long-term identity by itself. No duplicate item definitions exist.

## Terrain

The generator produces broad rolling hills with smaller deterministic variation. Each column is layered as:

- Air above the column height.
- Grass on ordinary surfaces.
- Dirt beneath grass.
- Stone below the shallow layer.
- Sand at low elevations, with stone beneath it.
- Exposed stone only on sufficiently steep high ground.

The generator is read-only after configuration and uses only pure seed/coordinate calculations in worker callbacks.

## Controls

- WASD: move.
- Mouse: first-person look.
- Space: jump.
- Shift: sprint.
- Left mouse: instantly break the targeted breakable voxel.
- Right mouse: place the selected development block in the adjacent empty cell.
- Q: cycle Grass → Dirt → Stone → Sand.
- Escape: release the mouse; click the window to capture it again.

The Q selector is a development-only seam in the player controller. It is not an inventory or hotbar.

Targeting uses the Voxel Tools voxel DDA raycast at a maximum range of six voxels. The hit cell receives a yellow wireframe; the raycast's previous cell is the placement cell. Placement requires loaded/editable data, Air at the destination, and no overlap with the player's body AABB.

The upper-left overlay shows the active seed, player position, hit/placement cells, selected development block, and latest interaction status.

## Verification

Production compatibility target remains Godot `4.7.2-stable`. The approved automated runner remains:

`D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe`

Run the complete local gate with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\development\verify_wave_1.ps1 `
  -GodotExecutable 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.console.exe'
```

The gate:

1. reruns the Wave 0 environment/plugin gate;
2. executes focused headless tests for identities, determinism, layering, and interaction safety;
3. starts the streamed world headlessly and waits for terrain collision at spawn;
4. runs a rendered golden-path playthrough using the declared input actions;
5. captures spawn and chunk-boundary edit frames plus a JSON report under ignored `.verification/wave1/`.

Use `-SkipRenderedPlaytest` only on a machine without a display. A skipped rendered run is not equivalent to the full acceptance gate.

## Current limits

- Voxel edits live only for the current process and intentionally disappear on restart.
- Block colors are deliberately simple development visuals, not the production voxel art pass.
- Terrain generation is intentionally small: no biomes, caves, structures, ores, vegetation, water, climate, or ecology.
- The controller has no crouch, swimming, climbing, stamina, health, equipment, or animation.
- Uneven one-voxel rises may require jumping; advanced traversal is outside Wave 1.
- The automated qualification runner is the documented fixed 4.8 development build. A separate exact 4.7.2 qualification requires an approved executable when one is available.

Wave 2 and all later showcase systems remain unimplemented.
