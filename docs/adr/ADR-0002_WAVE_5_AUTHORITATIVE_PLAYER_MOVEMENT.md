# ADR 0002 — Authoritative player movement

Status: adopted for W5.3, 2026-10-05.

Use host-authoritative player transforms. Clients send strictly validated movement intent,
with actor identity resolved from authenticated transport peer binding, never from the packet.
Predict the local client body with the same Leyforge movement rules and reconcile using
ordered host snapshots. This implementation does not claim rollback/input replay.

Extend the existing LfeNetworkSession through its raw post-authentication send_bytes/peer_packet path.
Input and snapshots use separate unreliable ordered channels; bootstrap and relevance changes use a reliable channel.
Advance network protocol to 2, retaining save/content/worldgen versions 4/1/2 and stored worldgen v1 support.
The accepted W5.2 build remains historically protocol 1.

Materialize a real host remote CharacterBody3D for each admitted identity, with its own collision VoxelViewer.
Keep this authoritative body and terrain interest active independently of host avatar visibility/camera position.
Persist each body's transform into its existing world-local character before save and disconnect.
Use bounded safe spawn fallback without replacing identity or personal state.

Compute per-peer relevance from authoritative positions with 96/128 m hysteresis, always including self.
Reliable enter/leave and presence epochs protect avatar lifecycle across unreliable snapshot loss/reordering.
Use bounded interpolation for remote client presentation.
Put players on a separate collision layer and exclude it from player masks, intentionally disabling player-player blocking.

JOIN generates a presentation/prediction base world from the authenticated host seed/worldgen manifest,
without world save or gameplay authority. Host voxel overrides and finite resource changes are unsynchronized.
Server collision and reconciliation win. Voxel override replication is deferred to W5.4.
No inventory/crafting/survival transaction replication, gameplay RPC, PvP or dedicated server is added.