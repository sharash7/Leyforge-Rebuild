# ADR-0005: Wave 5 authoritative player survival

Status: implemented for W5.6; complete verifier certification required; owner acceptance pending.

Each world-local `LfePlayerCharacter` already owns canonical
`LfeCharacterSurvival` and its durable six values and timing/debt state. HOST
advances those instances; JOIN receives a read-only session view. No schema
migration, second survival implementation, or multiplayer balance is needed.

`LeyforgePlayerSurvival.advance` advances world/workstation time exactly once,
then advances biology separately for each active local/connected body. Actual
authoritative movement supplies sprint activity and landing speed. Shelter
uses bounded authoritative voxel samples at each actor, cached for 0.5 seconds.
Rest is actor-scoped transient state validated against a nearby surviving Rest
Mat and current shelter. Movement, death, disconnect, range/object/cover loss
cancel it. Disconnected character values and timing freeze; no wall-clock
award or decay occurs.

Protocol 5 adds owner-only reliable survival bootstrap/events/resync on channel
9 and complete unreliable ordered replacements on channel 10, at most 10 Hz.
Exact finite bounded schemas reject corrupt state. Publication revisions order
complete views without delta replay. A separate mutation revision protects
consume expectations from discrete damage/consume/rest/recovery changes;
continuous biology does not invalidate a request every physics step. Requests
reuse the W5.5 sequence, transaction ID, result cache and retry seam. Consumption
prepares inventory and canonical survival together and consumes no item for a
no-op. A requester can resync only its bound character.

Fall damage uses one shared Wave-4 formula on HOST bodies. Zero health cancels
actions/rest, chooses a bounded authoritative safe spawn, clears velocity/input,
retains resources, and invokes canonical 50-health/50-stamina recovery. A
reliable movement reset advances the owner's presence and input epochs;
pre-recovery inputs and snapshots cannot cross that fence. Other relevant
players receive leave/enter to clear interpolation history. HOST/OFFLINE retains
the same logical recovery; no inventory loss, tombstone or progression loss.

Save v4 already contains every player's survival and timing. HOST synchronizes
body transforms before its existing save path; transient rest is never saved.
JOIN owns no authoritative save. Stronger failure/reconnection persistence
hardening remains W5.7. Downed/revival, combat/PvP, weather/temperature, mana,
host migration, relay, LAN/WAN qualification and dedicated servers are deferred.
