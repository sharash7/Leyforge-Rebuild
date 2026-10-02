# Wave 0 Environment

This file pins the clean-bootstrap dependencies and the repeatable validation entry point. It does not authorize Wave 1 gameplay work.

## Godot

- Production target: Godot `4.7.2-stable`.
- Source tag: `4.7.2-stable`.
- Source commit: `ed1daf0bf001b61586d9930840f2f1394092c079`.
- Project feature level: Godot `4.7`, using the Compatibility renderer for the blank bootstrap scene.

Godot `4.7.2-stable` is the current production-stable release selected for the project. Local automation must still use a runner approved for its environment; the repository does not vendor an engine binary.

## Voxel Tools

- Project: Zylann's Voxel Tools for Godot.
- Edition: GDExtension.
- Release: `1.7` for Godot `4.5+`.
- Tag: `v1.7x`.
- Source commit: `75d3c6d996ed2331c80edcd8c3ebc947afc0f041`.
- Release asset: `GodotVoxelExtension.zip`.
- Download: <https://github.com/Zylann/godot_voxel/releases/download/v1.7x/GodotVoxelExtension.zip>
- SHA-256: `600737572a5e25541ba6f503e842a3717ba19afafa5474510a6ceff995a1d2d8`.
- Installed path: `addons/zylann.voxel/`.

The release archive is committed unmodified. Its `voxel.gdextension` descriptor declares Godot `4.4.1` as the minimum compatible engine and selects platform-specific editor and release libraries. Do not combine this GDExtension with a Godot build that already includes the Voxel Tools module, because the native classes would conflict.

## Validation

Run the Wave 0 gate from the repository root with a known-safe Godot console executable:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/development/verify_wave_0.ps1 -GodotExecutable "C:\path\to\godot.console.exe"
```

The gate uses isolated application-data directories, imports the project in a headless editor session, launches the configured startup scene, instantiates the `VoxelTerrain` native class, and checks the bootstrap markers. Godot-generated `.godot/` state remains ignored.
