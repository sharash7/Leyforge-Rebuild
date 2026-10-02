# Leyforge Showcase Slice v0.1

## Intent

The first production target is a broad, shallow, playable slice of Leyforge that demonstrates the foundations of the game's major pillars.

It is not a throwaway prototype and it is not intended to be content-complete.

The slice should feel like a small sneak peek of the eventual game: enough functionality to understand how Leyforge's systems fit together, with foundations designed to be expanded rather than replaced.

## Development philosophy

**Breadth is the priority, not a hard limit on depth.**

A feature may be taken further than originally planned when doing so:

- makes the game materially more fun or understandable;
- validates an important technical foundation;
- creates reusable LFE capability;
- creates useful Forge-ENG / Forge capability; or
- supports several later systems.

Park deeper work when it is mostly content volume, polish without dependencies, or distant edge-case handling while major showcase pillars remain absent.

## Showcase pillars

The initial slice should eventually contain basic versions of:

- deterministic voxel world generation;
- player movement and interaction;
- voxel breaking and placement;
- gathering and physical resource acquisition;
- inventory and hotbar;
- tools;
- crafting;
- building;
- persistence;
- exploration;
- a small NPC camp/settlement;
- basic NPC identity, movement and labour;
- one simple settlement construction loop;
- basic automation/logistics;
- Flux / magic;
- basic combat;
- creatures/enemies;
- at least one cave/ruin-style exploration site;
- early Forge tooling used on real game content;
- multiplayer-aware architecture, followed by a small networking proof when the core foundation is stable.

## Milestones

### S0 — Clean Foundation

Goal: create the canonical production repository and a functioning blank Godot project.

- [ ] Create fresh GitHub repository.
- [ ] Clone exactly one working copy.
- [ ] Create blank Godot project.
- [ ] Confirm chosen Godot version.
- [ ] Install chosen voxel plugin.
- [ ] Confirm plugin loads without errors.
- [ ] Establish repository skeleton.
- [ ] Establish `.gitignore`.
- [ ] Launch one empty startup scene.
- [ ] Commit clean bootstrap.

### S1 — Standing in Leyforge

Goal: enter a generated voxel world and interact with it.

- [ ] Deterministic seed value exists.
- [ ] Generate simple voxel terrain.
- [ ] Add basic block registry/content definitions.
- [ ] Add first-person player controller.
- [ ] Add movement.
- [ ] Add mouse look.
- [ ] Add gravity.
- [ ] Add jump.
- [ ] Add sprint.
- [ ] Add collision.
- [ ] Target a voxel.
- [ ] Break a voxel.
- [ ] Place a voxel.
- [ ] Keep the initial block palette deliberately small.

Initial candidate block palette:

- Air
- Grass
- Dirt
- Stone
- Sand
- Water
- Oak Log
- Oak Leaves

### S2 — Persistent Survival Loop

Goal: make the voxel interaction loop matter and survive restart.

- [ ] Save/load world identity and seed.
- [ ] Persist voxel edits.
- [ ] Physical drops.
- [ ] Pickup.
- [ ] Inventory.
- [ ] Hotbar.
- [ ] Item stacks.
- [ ] Basic tools.
- [ ] Harvest/tool rules.
- [ ] Tool durability.
- [ ] Small crafting system.
- [ ] Workbench or equivalent first station.
- [ ] Persist player/inventory state.

### S3 — First Forge Capability

Goal: create the first authoring tool only when maintaining real content becomes painful.

Likely first target:

**Block / Item Forge v0.1**

Potential capability:

- [ ] inspect canonical content definition;
- [ ] create/edit canonical ID;
- [ ] assign name/category;
- [ ] assign texture/model reference;
- [ ] assign material/harvest/tool properties;
- [ ] assign drop;
- [ ] validate definition;
- [ ] save canonical definition;
- [ ] game reads exactly the same definition.

This milestone may move earlier or later depending on actual production friction.

### S4 — Living Camp

Goal: prove the first civilisation loop.

Candidate starting camp:

- Campfire
- Two tents
- Storage
- Work area
- Three residents

Foundation features:

- [ ] stable NPC identities;
- [ ] names;
- [ ] movement;
- [ ] simple interaction;
- [ ] basic home/bed relationship;
- [ ] simple job;
- [ ] basic NPC inventory;
- [ ] minimal schedule/needs where useful;
- [ ] one settlement request/need;
- [ ] player supplies resources;
- [ ] NPC visibly performs labour;
- [ ] one small structure/project can be completed;
- [ ] settlement state persists.

### S5 — Baby Automation

Goal: demonstrate that Leyforge grows into an automation game.

Candidate first chain:

Manual Crank -> Basic Miner -> Item Chute -> Wooden Crate

- [ ] place machine;
- [ ] provide simple power/work input;
- [ ] machine performs useful action;
- [ ] item/resource output is conserved;
- [ ] output visibly moves;
- [ ] storage receives output;
- [ ] state persists.

### S6 — Flux Awakening

Goal: show that magic is also infrastructure.

- [ ] discover Flux/mana resource;
- [ ] basic personal mana/Flux state;
- [ ] one processing/crafting step;
- [ ] one basic magic station or device;
- [ ] one tiny magic-network concept if justified;
- [ ] two or three starter abilities;
- [ ] persist unlocked magic/state.

Candidate starter abilities:

- Stone Sense
- Spark Bolt

### S7 — Danger and Discovery

Goal: connect survival, exploration, combat and magic.

- [ ] one passive creature;
- [ ] one or more hostile creatures;
- [ ] basic melee;
- [ ] player health/damage;
- [ ] simple enemy behaviour;
- [ ] magic combat integration;
- [ ] basic cave generation or cave site;
- [ ] one ruin/site;
- [ ] meaningful resource/reward discovery;
- [ ] optional stronger enemy/miniboss if useful.


### S7.5 — Multiplayer Foundation Proof

Goal: prove that the clean runtime foundation can support more than one player without attempting to finish multiplayer.

Timing is flexible. Do this only after world/player/persistence foundations are stable enough to network sensibly.

- [ ] choose and document the initial authority/topology model;
- [ ] start/join a simple session;
- [ ] connect at least two players;
- [ ] replicate player presence and movement;
- [ ] replicate one authoritative voxel edit;
- [ ] prove basic clean leave/reconnect or resync handling;
- [ ] prevent obvious duplicate authoritative resource transactions;
- [ ] document what remains host/server authoritative;
- [ ] keep multiplayer-specific infrastructure separated from ordinary gameplay where practical.

This is a foundation proof, not the final multiplayer implementation.

### S8 — Showcase Candidate

Goal: stop adding major pillars temporarily and make the slice coherent.

- [ ] usable HUD/UI;
- [ ] understandable feedback;
- [ ] basic sound;
- [ ] basic animation/visual readability;
- [ ] reliable save/load;
- [ ] loading/start flow;
- [ ] stable controls;
- [ ] accessibility fundamentals;
- [ ] performance sanity pass;
- [ ] bug fixing;
- [ ] onboarding;
- [ ] packageable playable build.

## LFE growth rule

Do not design LFE as a complete engine in advance.

Potential areas may emerge as needed:

- voxel runtime;
- content runtime;
- world runtime;
- deterministic worldgen;
- persistence;
- entity runtime;
- simulation;
- interaction;
- logistics;
- Flux runtime.

Create these only from concrete game requirements.

## Forge / Forge-ENG growth rule

Do not build the complete Forge in advance.

Likely progression may include:

- Block / Item Forge
- Recipe Forge
- Structure Forge
- Biome / Worldgen tools
- Model Forge
- Creature Forge
- NPC Forge
- Dungeon Forge
- Vessel Forge
- World / Realm tools

The actual order should be determined by production friction.

## Success condition

The Showcase Slice succeeds when a player can enter a deterministic voxel world and experience a small connected loop that clearly demonstrates Leyforge's survival, building, civilisation, automation, magic, combat and exploration identity.

After that, development shifts from "make every pillar exist" to "deepen the weakest or most valuable pillar using the existing Leyforge design documentation as reference."
