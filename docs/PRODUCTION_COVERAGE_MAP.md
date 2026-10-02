# Leyforge Production Coverage Map

This is a coverage map, not an implementation mandate. It exists so the clean production repository has a known home for the major parts of Leyforge, LFE, Forge-ENG and The Forge while leaving room for systems we discover later.

## Leyforge game domains

Known major domains include:

- application/bootstrap and game flow
- player, camera, input and interaction
- voxel world interaction and building
- procedural world generation, terrain, biomes, caves and resources
- canonical blocks, items and content
- gathering, drops, inventory, equipment and hotbars
- tools, durability and progression
- crafting, processing and industry
- player construction/building
- survival and character state
- combat
- Flux, runes, abilities and magic
- creatures and ecology
- NPCs
- settlements, civilisation, jobs and labour
- automation, machines and logistics
- economy, trade and commerce
- knowledge, lore and discovery
- quests, events and narrative
- factions, cultures and governments
- movement, travel and routes
- oceans and maritime systems
- vessels and naval systems
- structures, dungeons and megaprojects
- realms/dimensions and portals
- UI/UX, accessibility, settings and localisation
- audio
- saving/loading and world lifecycle
- multiplayer and networking
- sessions, joining/leaving, permissions and authority
- performance/scalability
- packaging, updates and release flow
- future modding/extensibility if justified

Not every domain needs its own implementation immediately.

## Multiplayer / networking

Multiplayer is a planned first-class capability. We should not network every early feature immediately, but early architecture should avoid single-player-only assumptions where that would make networking painful later.

Likely future concerns include:

- host/client and/or dedicated-server topology
- authoritative simulation ownership
- deterministic/shared world identity
- session lifecycle
- player identity
- joining/leaving/reconnect
- replication
- voxel edit replication
- inventory and resource transaction authority
- NPC/settlement simulation authority
- machine/automation authority
- combat authority
- save ownership
- permissions
- prediction/interpolation where useful
- version/content compatibility
- latency handling
- anti-duplication protections
- multiplayer-safe persistence
- headless/dedicated-server execution if desired

A small networking proof should be introduced after the core world/player/persistence foundation is stable.

## LFE — Leyforge Engine

Potential runtime areas that may emerge from real requirements:

- core/common runtime
- deterministic IDs and RNG
- voxel runtime
- content registry/loading
- world runtime
- world generation
- persistence/serialization
- entity runtime
- simulation scheduling and near/far simulation
- navigation/pathfinding
- interaction and transactions
- logistics
- Flux/magic primitives
- networking/replication/session infrastructure
- platform abstraction
- performance/scalability
- diagnostics/debugging
- testing hooks

Do not implement an area merely because it appears here.

## Forge-ENG

Potential reusable authoring infrastructure:

- Forge workspace/project model
- canonical content schemas
- editing transactions
- validation
- import/export
- compilation/baking
- asset processing
- previews
- runtime compatibility checks
- undo/redo
- dependency/reference tracking
- content indexing/search
- batch operations
- test/simulation hooks
- packaging
- extensibility if justified
- future collaboration/version-aware tooling if useful

## The Forge

Potential creator-facing tools:

- Block Forge
- Item Forge
- Recipe Forge
- Material/Texture tools
- Model Forge
- Structure Builder
- Building/Settlement tools
- Dungeon Forge
- Creature Forge
- NPC Forge
- animation tools
- Biome Forge
- Worldgen/World Forge
- Realm Forge
- Vessel Forge
- automation/industry tools
- magic/rune tools
- quest/event/dialogue tools
- faction/culture/economy tools
- preview/test worlds
- simulation/debug panels
- validation and packaging tools

This list is intentionally open-ended.

## Shared production concerns

Across all layers:

- canonical IDs
- deterministic behaviour where required
- schema/version management
- save/content compatibility
- testing
- profiling and diagnostics
- accessibility
- performance
- source-control hygiene
- reproducible builds
- platform support
- release packaging

## Showcase rule

The first production phase remains the broad, shallow Leyforge Showcase Slice.

The goal is not to finish everything listed above. It is to establish a real expandable foundation across Leyforge's defining pillars, then deepen systems iteratively.

If a new domain appears that is not listed here, add it. The repository is allowed to evolve with the game.
