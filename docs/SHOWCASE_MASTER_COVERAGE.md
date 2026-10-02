# Leyforge Showcase Master Coverage v0.3

This is the authoritative coverage checklist for the **miniature-universe showcase**.

It does not require full implementations. Each entry only needs a small real representative that proves the architecture and connects to the rest of Leyforge.

**Breadth is the priority; useful depth is allowed.**

Every Forge workspace is its own showcase section. A placeholder window does not count; the workspace must eventually author or validate real content used by the game.

## 01 — Product Shell & Player

- [ ] Boot/title/main menu, Continue, World Library and pause flow
- [ ] World creation, naming, seed input/random seed and basic world settings
- [ ] Profile/global settings and build/version identity
- [ ] Character identity, appearance, ancestry/background hooks and persistent player ID
- [ ] First-person body, visible held/equipped items and character persistence
- [ ] Keyboard/mouse, controller, rebinding, localisation readiness and accessibility foundations

## 02 — Movement, Interaction & Voxel Play

- [ ] Walk, sprint, jump, crouch, look, collision, steps/slopes and falling
- [ ] Swimming, diving, ladders, climbing/mantling and representative advanced traversal
- [ ] Voxel targeting/highlight, breaking, placing, rotation/orientation and stateful blocks
- [ ] Doors, shapes/directional blocks and persistent player modifications

## 03 — Canonical Content, Items & Materials

- [ ] Stable IDs, registries, schemas and the single-definition rule
- [ ] Representative blocks, items, tools, weapons, armour, consumables, components, currency and cargo
- [ ] Inventory, hotbar, equipment, storage, transfer, ownership and permissions
- [ ] Materials, provenance, quality/state, derived forms and substitution/capability rules
- [ ] Physical drops, gathering, mining, woodcutting, digging, harvesting and fishing

## 04 — Crafting, Building & Progression

- [ ] Hand crafting, workstations, furnace/smithing, transformations, by-products and repair
- [ ] Player free-building plus blueprint/project construction
- [ ] Overall progression, skill XP/proficiency, perks, capability and knowledge unlocks
- [ ] Representative loot, relics, treasure and identification/discovery

## 05 — Survival, Biology, Food & Agriculture

- [ ] Health, stamina/exertion, hunger, thirst, fatigue and rest/sleep
- [ ] Temperature, wetness, exposure, shelter and environmental hazards
- [ ] Injury, bleeding, poison/disease, medicine, treatment and recovery
- [ ] Flora/fungi, edible/useful plants and ecological eligibility
- [ ] Farming: till, seed, growth, harvest, cooking/processing and storage
- [ ] Husbandry: domestic animal, feeding, shelter, useful output and future breeding hook

## 06 — World, Worldgen & Environment

- [ ] Deterministic seeds, chunks, streaming, regional/site placement and world lifecycle
- [ ] Terrain, biomes/ecotones, climate, geology, resources and cave/Deep foundations
- [ ] Day/night, weather, wind, storms and calendar/season foundation
- [ ] Hydrology/liquids, rivers/inland water, coast/ocean connection and buoyancy foundations
- [ ] Structures, landmarks, ruins, dungeons/lairs and persistent cleared/changed state

## 07 — Creatures, Combat & Threats

- [ ] Passive wildlife, predator, monster, domestic and aquatic creature examples
- [ ] Habitat/population/ecology relationships and meaningful creature materials
- [ ] Melee, ranged, magic, blocking, armour, damage/status effects and death/downed flow
- [ ] Miniboss/boss/threat state and one settlement raid/siege-style event

## 08 — NPC People & Social Simulation

- [ ] Persistent NPC identity, appearance, inventory, equipment, home, household, job and schedule
- [ ] Needs, knowledge, relationships, memory/history and basic biological profile
- [ ] NPC navigation, route graph, doors/obstacles and loaded/unloaded recovery
- [ ] Contextual dialogue, known/unknown facts, rumours, truth/falsehood and one language difference
- [ ] Trust/loyalty/affection/rivalry plus persuasion, negotiation, intimidation and etiquette
- [ ] Companion/follower/hireling recruitment, commands, work, combat, carrying and dismissal
- [ ] Delegation/autonomy with off-screen resolution

## 09 — Settlements & Civilisation

- [ ] Camp-to-hamlet foundation covering Housing, Provisions, Health, Work, Safety, Infrastructure and Morale
- [ ] Households/population, migration/arrival and housing capacity
- [ ] Jobs/labour, storage, food, health services, education/research and extraction/work sites
- [ ] Safety/defence, governance, justice/law response and emergency-service foundations
- [ ] Utilities/infrastructure, roads, transport nodes, power/water-service concepts and logistics
- [ ] Settlement projects, reserves, staged NPC construction and persistent works
- [ ] Player Blueprint system and main-menu Workshop direction
- [ ] Districts/parcels/planning, complexes, megaproject/wonder hierarchy and cultural building variants

## 10 — Automation, Industry & Power

- [ ] Power source, network/capacity, machine, processing, transport/routing and storage
- [ ] Filters, faults/blockages, control/inspection and conserved quantities
- [ ] Multi-stage industry chain rather than single-step conversion

## 11 — Flux, Magic & Magical Ecology

- [ ] Personal Flux/mana, learning, focus and representative spells
- [ ] Runes, magical crafting and authored effects
- [ ] Ritual foundation
- [ ] Civilisation magic: source, battery, conduit, machine and ward
- [ ] Mana pockets/magical ecology plus corruption/stability or environmental consequence

## 12 — Knowledge, Research, Map & Narrative

- [ ] Discovery, archaeology, research station/institution, unknown-to-known progression and unlocks
- [ ] Map fog/discovery, landmarks, pins, routes, settlements, dungeons and portals
- [ ] Codex entries filtered by player knowledge
- [ ] Quests, lightweight requests, dynamic events, persistent aftermath/history and emergent narrative

## 13 — Peoples, Culture, Faith, Factions & Government

- [ ] Representative ancestry/people pipeline
- [ ] Culture affecting naming, dress, architecture, preferences and presentation
- [ ] Language and translation/understanding hooks
- [ ] Religion/faith/philosophy represented through NPCs, places, ritual and reactions
- [ ] At least two factions with reputation, interests/territory and player relationship
- [ ] Government authority/office/decision and settlement effect
- [ ] Law, ownership, permissions, violations and response

## 14 — Economy, Trade & Finance

- [ ] Value, price, stock and simple supply/demand
- [ ] Currency and barter
- [ ] Markets/merchants, buying/selling and stock movement
- [ ] Labour, wages and one business relationship
- [ ] Contracts/orders/services with obligations and payment
- [ ] Credit/debt and repayment; banking/insurance architecture proofs
- [ ] Taxation/public treasury
- [ ] Trade routes, caravans and regional exchange
- [ ] Smuggling/black-market/restriction example

## 15 — Travel & Transportation

- [ ] Road and route networks used by players/NPCs/trade
- [ ] Mount, work animal and handcart/wagon representative
- [ ] Rail/minecart/elevator representative
- [ ] Long-distance travel/route guidance

## 16 — Realms & Portals

- [ ] Overworld plus one small second-realm pocket
- [ ] Portal discovery/activation/travel/return and persistent state
- [ ] At least one different realm law/environmental rule
- [ ] Cross-realm material provenance and transport

## 17 — Oceans, Maritime & Vessels

- [ ] Generated coast/ocean and marine weather/current/wave/tide foundation
- [ ] Swimming/diving, fishing and marine ecology
- [ ] Working vessel with buoyancy, propulsion, steering and persistence
- [ ] Shipwright construction/repair/salvage
- [ ] Port/jetty/shipyard capability
- [ ] Crew role, maritime trade/cargo and route
- [ ] Piracy/naval hostility, basic naval damage/combat/boarding and fire/flooding foundations
- [ ] Maritime quest/event use of general systems

## 18 — Multiplayer & Networking

- [ ] Early proof: host/join, two players, identity, replicated movement, voxel edits and item transactions
- [ ] Authority, anti-duplication, reconnect/resync and multiplayer-safe persistence
- [ ] Later proof across combat, settlements, machines, vehicles/vessels and portals
- [ ] Dedicated/headless server pathway

## 19 — Living World Scale & Optional Intelligence

- [ ] Simulation LOD for NPCs, machines, settlements/ecology and reconciliation on return
- [ ] Performance/scalability budgets and low-end profiles
- [ ] Optional bounded living-world intelligence with authoritative validation

## 20 — UI, Audio, Art & Presentation

- [ ] HUD plus inventory, crafting, settlement, machine, dialogue, quest, map, combat and vehicle interfaces
- [ ] Settings, accessibility, controller, localisation-ready layout and notifications
- [ ] Voxel visual language, textures/materials/shaders, lighting and culture/realm/biome art direction
- [ ] Animation, VFX/particles, weather/Flux/combat effects
- [ ] SFX, ambience, creature/machine/weather audio and music
- [ ] UI/icons, cartography/Codex presentation and visual-reference/QA pipeline

## 21 — Persistence, Content Architecture & Production

- [ ] Multi-world saves, world/player/NPC/machine/realm state and profile-vs-world separation
- [ ] Save versioning, migration, recovery/integrity and content compatibility
- [ ] Content packs/manifests, import/export and migration
- [ ] Focused deterministic, persistence, transaction, content, network and simulation testing
- [ ] Diagnostics/debug overlays, profiling and worldgen/network/entity visibility
- [ ] Build/export, headless build, release diagnostics, update/version pathway and future extensibility

## 22 — LFE Runtime Families

- [ ] Core IDs/events/commands/deterministic RNG
- [ ] Content runtime
- [ ] Voxel runtime
- [ ] World runtime
- [ ] Worldgen
- [ ] Persistence
- [ ] Entities
- [ ] Simulation
- [ ] Navigation
- [ ] Transactions
- [ ] Logistics/networks
- [ ] Magic runtime primitives
- [ ] Vehicles/vessels runtime
- [ ] Networking
- [ ] Platform services
- [ ] Diagnostics/profiling

## 23 — Forge-ENG Families

- [ ] Core workspace/project/session services
- [ ] Canonical schemas/data
- [ ] Editing transactions
- [ ] Undo/redo/history
- [ ] Validation
- [ ] References/dependencies
- [ ] Search/index/library
- [ ] Import/export
- [ ] Compilation/baking
- [ ] Preview infrastructure
- [ ] Asset processing
- [ ] Variants/inheritance/overrides
- [ ] Versioning/migration
- [ ] Batch operations
- [ ] Packaging/content packs
- [ ] Runtime compatibility validation
- [ ] Simulation/test hooks
- [ ] AI-assisted authoring interface with authoritative validation

## 24 — The Forge Workspaces

- [ ] Forge Home / Project Dashboard
- [ ] Voxel Asset Forge
- [ ] Block Surface Forge
- [ ] Texture Forge
- [ ] Material Forge
- [ ] Voxel Model Forge
- [ ] Item Model Forge
- [ ] Tool / Weapon / Equipment Forge
- [ ] Machine / Functional Object Forge
- [ ] Animation & Effects Forge
- [ ] Asset Variant / Override Forge
- [ ] Humanoid / Player / NPC Creator
- [ ] Character Customisation Forge
- [ ] Equipment Visual Forge
- [ ] Creature / Mob / Monster / Boss Creator
- [ ] Anatomy / Body Architecture Forge
- [ ] Skeleton / Rig Forge
- [ ] IK / Attachment Forge
- [ ] Character & Creature Animation Forge
- [ ] Hitbox / Collision / Gameplay Integration Forge
- [ ] Blueprint Forge
- [ ] Building Forge
- [ ] Structure Forge
- [ ] Settlement Forge
- [ ] District / City Planning Forge
- [ ] Megaproject / Wonder Forge
- [ ] Dungeon Forge
- [ ] Route / Infrastructure Forge
- [ ] Biome Forge
- [ ] Worldgen Forge
- [ ] World Forge
- [ ] Realm Forge
- [ ] Portal Forge
- [ ] Vessel Forge
- [ ] Automation / Machine Forge
- [ ] Recipe / Process Forge
- [ ] Resource / Material Forge
- [ ] Magic / Spell Forge
- [ ] Rune Forge
- [ ] Ritual Forge
- [ ] Creature Ecology Forge
- [ ] NPC / Person Forge
- [ ] Dialogue Forge
- [ ] Social / Relationship Forge
- [ ] Companion Forge
- [ ] Quest Forge
- [ ] Event / World-State Forge
- [ ] Lore / Knowledge / Codex Forge
- [ ] Faction Forge
- [ ] Culture Forge
- [ ] Religion / Belief Forge
- [ ] Government / Law Forge
- [ ] Economy Forge
- [ ] Market / Merchant Forge
- [ ] Contract Forge
- [ ] Trade Route Forge
- [ ] Agriculture / Ecology Forge
- [ ] Audio Forge / integration workspace
- [ ] VFX Forge / integration workspace
- [ ] UI / Icon / 2D Asset Forge integration
- [ ] Cartography Forge
- [ ] Preview / Test Forge
- [ ] Validation Forge
- [ ] Content Pack / Export Forge
- [ ] Import / Migration Forge
- [ ] AI-assisted Forge
