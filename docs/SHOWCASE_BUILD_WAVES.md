# Leyforge Showcase Build Waves v0.3

These waves are dependency-oriented navigation markers, not hard gates.

## Continuous rules

- Persistence grows with every persistent feature.
- Networking awareness grows with every authoritative feature.
- Forge tooling grows when real authoring pain appears.
- Focused tests protect deterministic generation, saves, transactions, registries, networking and other corruption-prone foundations.
- Breadth is the priority; useful/fun depth is allowed.

## Wave 0 — Clean Birth
Fresh repo; apply starter pack; create real blank Godot project; install/verify required voxel plugin(s); startup/test scene; diagnostics/test entry point; commit.

## Wave 1 — Standing in Leyforge
Stable IDs and deterministic seed/RNG; simple generated voxel terrain; small block palette; player controller; movement; target/break/place voxel.

## Wave 2 — The World Remembers
World identity/lifecycle; save-format version; save/load seed, voxel edits and player state; integrity/recovery foundation.

## Wave 3 — Stuff Exists
Drops/pickup; canonical item/content runtime; inventory/hotbar/storage/equipment; transactions; first Block/Item/Texture/Material/Model Forge slices when useful.

## Wave 4 — Survival & Creation
Gathering/tools; crafting/processing; building; health/basic survival; progression; early Blueprint/Recipe/Resource/Equipment Forge slices.

## Wave 5 — Multiplayer Proof #1 — Local/LAN
Two-player authoritative shared world; local/LAN host/join; secure private admission;
movement and relevance; authoritative voxel mutations; inventories/resources;
crafting/workstations; independent survival; reconnection; HOST-owned persistence;
duplicate/abuse prevention; disconnect cleanup; local/LAN certification.

Owner scope amendment dated 2026-10-15: direct WAN is not a Wave 5 closure
requirement. Existing W5.8 connectivity and historical results remain intact;
external-WAN owner acceptance is deferred to Wave 17. W5.9 automated certification
and subsequent owner LAN acceptance are required before Wave 5 closes or W6.1
implementation starts. See `WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md` and ADR-0008.

## Wave 6 — The World Becomes Alive
Biomes/climate; caves/geology/resources; weather/time; water foundations; flora; creatures; farming/husbandry; Biome/Worldgen/Structure/Creature/Ecology Forge slices.

Status reviewed 2026-10-19: [W6.1 closed with owner acceptance](WAVE_6_PART_1_CLOSURE.md).
[Wave 5 LAN-first closure](WAVE_5_CLOSURE.md), its traceability limits and WAN
deferral remain unchanged. [W6.2 is CLOSED — OWNER ACCEPTED](WAVE_6_PART_2_CLOSURE.md).
[W6.3 is CLOSED — OWNER ACCEPTED](WAVE_6_PART_3_CLOSURE.md) at `447bbd3`;
historical automated certification and the later owner decision remain separate.
The [W6.3.1 audit](WAVE_6_PART_3_1_ALIGNMENT_AUDIT.md),
[proposed amendments](WAVE_6_PART_3_1_PROPOSED_AMENDMENTS.md) and
[unified UX plan](WAVE_6_PART_3_1_UNIFIED_FORGE_UX_PLAN.md) are delivered for owner
review before W6.4. The owner accepts the reconciliation direction with refinements;
W6.3.1 documentation reconciliation is authorised, FINAL OWNER REVIEW PENDING
for final text and the exact publication set. Block/Material/Texture delivery is
provisionally before W6.7 consumption, earlier if W6.6 water needs it; existing-cube
W6.4 need not await completed Block Forge. Shared interaction design is defined
now, with early implementation review after useful Block/Texture and World
patterns; W6.17–18 integrate/harden. No implementation/publication is authorised;
W6.4 remains NOT AUTHORISED. Preserve the owner-established
Forge-first W6.2–W6.18 sequence in the
[W6.1 specification](WAVE_6_PART_1_READINESS_UI_AND_INTEGRATION_FOUNDATION.md).
Future equipment expansion and living-world systems remain later work.

## Wave 7 — Adventure & Progression
Combat/gear; loot/relics; status effects; boss/threat; skills/perks; map/codex/research; equipment/animation/rig/hitbox/knowledge Forge slices.

## Wave 8 — People
Persistent NPCs; households/jobs/schedules; navigation; dialogue/knowledge/language/rumours; relationships/social actions; companions/delegation; NPC/Humanoid/Character/Dialogue/Social/Companion Forge slices.

## Wave 9 — Civilisation
Camp-to-hamlet; seven settlement pillars; labour/projects/construction; services/education/health/safety/utilities; governance/justice/emergency foundations; districts/planning/complexes; Player Blueprint; Settlement/Building/District/Infrastructure/Megaproject Forge slices.

## Wave 10 — Industry & Magic
Automation/logistics/power; multi-stage industry; Flux/magic; runes/rituals; civilisation magic; magical ecology; Automation/Process/Magic/Rune/Ritual/VFX Forge slices.

## Wave 11 — Society
Ancestry/culture/language; religion; factions; government; law/ownership/permissions; education/institutions; related Forge slices.

## Wave 12 — Economy & Events
Currency/barter; markets; wages/businesses; contracts; credit/debt; banking/insurance proof; tax/treasury; trade routes/caravans; black market; quests/requests/events/history; related Forge slices.

## Wave 13 — Travel & Transport
Roads/routes; mount; work animal; cart/wagon; rail/minecart/elevator proof; long-distance travel; Route/Infrastructure and transport tooling.

## Wave 14 — Ocean Leyforge
Coast/ocean; swimming/diving/fishing/marine ecology; marine weather/current/wave foundation; vessel; shipwright repair/salvage; port/crew/trade; naval damage/combat; Vessel/maritime Forge slices.

## Wave 15 — Beyond the Overworld
Tiny second realm; portal; realm-specific law; cross-realm material/provenance; Realm/Portal/World/Biome Forge slices.

## Wave 16 — Living World Scale
Simulation LOD; background NPC/machine/settlement/ecology work; reconciliation; scalability/performance; simulation debug tooling.

## Wave 17 — Multiplayer Proof #2
Combat; settlements; machines; vehicles/vessels; portals/realms; multiplayer-safe save/resync; headless/dedicated-server pathway.

Planned online-connectivity workstream: direct WAN; CGNAT/Starlink compatibility;
NAT traversal assessment; reliable relay fallback; internet friend/session
discovery; clickable one-use/expiring invitations; click-to-join flow;
platform/network backend assessment; secure transport design; internet-scale
network testing. These are future architecture/planning responsibilities,
including deferred W5.8 direct-WAN human acceptance, not completed capabilities.

## Wave 18 — Forge Ecosystem Completion
Give every known Forge workspace a small real workflow; mature shared Forge-ENG schemas/editing/history/validation/references/indexing/import-export/baking/preview/variants/migration/batch/packaging/test hooks; dogfood Forge-created content.

## Wave 19 — Art & Presentation
Production voxel visual language; materials/textures/shaders; character/creature/equipment/machine/structure/vessel visuals; lighting/VFX; animation; audio/music; UI/icons/cartography; visual QA.

## Wave 20 — Product Quality
Complete connected UI; settings; accessibility; controller; localisation readiness; performance/graphics profiles; low-end scalability; diagnostics.

## Wave 21 — Production Showcase
Save migration/integrity/recovery; content compatibility; exported build; headless/server build; release diagnostics; update/version pathway; full connected showcase playthrough.

## Wave 22 — Optional Intelligence Layer
Bounded NPC/world intelligence interface; authoritative action validation; AI-assisted Forge proposals with validation and human approval.
