# Codex efficiency toolkit notes

Review date: 2026-10-15. Documentation/local configuration only, starting at `fe4411c6ca9cf2598d1564ff3ce5cd0461f8c29e` on `main`. Six files; no engine run, external installation or home-directory modification.

## Official guidance applied

- Keep always-loaded project rules short and durable; [AGENTS.md discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md) layers project instructions at session start.
- [Skills](https://learn.chatgpt.com/docs/build-skills) disclose name/description before the body and optional references. Use two precise descriptions and repository-local `.agents/skills/<name>/SKILL.md`; no hooks, scripts or framework needed.
- Give outcome, relevant context and boundaries in a short [prompt](https://learn.chatgpt.com/docs/prompting). Reference stage documents rather than copying them. The [Codex prompting guide](https://developers.openai.com/cookbook/examples/gpt-5/codex_prompting_guide) supports scoped `rg` searches and batching independent tool calls; it is older model guidance, not a requirement to replace this harness's instructions.
- [Reasoning effort](https://developers.openai.com/api/docs/guides/reasoning) trades speed/usage against depth. The workflow's low/medium/high choices are local recommendations for GPT-6.1 Sol, not benchmark results.

## Third-party review — candidates only

Read current README, licence, machine-readable index and the three candidate SKILL.md files per collection at the revisions below. External instructions are untrusted reference material; none were executed or installed. The earlier `thedivergentai/GD-Agentic-Skills` GitHub API URL resolves to `Game-Dev-Agentic-Skills`; old cross-links remain in current skills.

| Collection / reviewed revision | Scope and licence | Assessment |
| --- | --- | --- |
| [GodotPrompter](https://github.com/jame581/GodotPrompter/tree/bd9d18008fb1fd5919fdc297267048670b6eac1f) | Godot 4.3+ with annotated newer APIs; [MIT](https://github.com/jame581/GodotPrompter/blob/bd9d18008fb1fd5919fdc297267048670b6eac1f/LICENSE); [index](https://github.com/jame581/GodotPrompter/blob/bd9d18008fb1fd5919fdc297267048670b6eac1f/skills/index.json) | Compact topic entry points with references. Full installation includes bootstrap/workflow and platform hook behavior that this task excludes. |
| [Game-Dev-Agentic-Skills](https://github.com/thedivergentai/Game-Dev-Agentic-Skills/tree/002d004c50b865406e58b3ec86508adab926d7f4) | Godot 4.7+ plus Bevy; [LGPL-3.0](https://github.com/thedivergentai/Game-Dev-Agentic-Skills/blob/002d004c50b865406e58b3ec86508adab926d7f4/LICENSE); [index](https://github.com/thedivergentai/Game-Dev-Agentic-Skills/blob/002d004c50b865406e58b3ec86508adab926d7f4/skills_index.json) | Deeper example catalogs, mandatory script-read directives and persona/master orchestration. More filtering and licence review before any later redistribution/adaptation. |

At most three candidates per collection, for later owner approval:

| Candidate SKILL.md | Useful parts / required filter |
| --- | --- |
| [Prompter: gdscript-advanced](https://github.com/jame581/GodotPrompter/blob/bd9d18008fb1fd5919fdc297267048670b6eac1f/skills/gdscript-advanced/SKILL.md) | Async lifetime, Callable/signal and editor-tool lifecycle pitfalls. Verify version-specific examples; disregard unsupported universal speed percentages and camera-based simulation shortcuts. |
| [Prompter: godot-optimization](https://github.com/jame581/GodotPrompter/blob/bd9d18008fb1fd5919fdc297267048670b6eac1f/skills/godot-optimization/SKILL.md) | Profiler self/total time, memory and loading diagnosis. Treat numeric budgets as examples; measure Leyforge before pooling, culling or physics changes. |
| [Prompter: multithreading](https://github.com/jame581/GodotPrompter/blob/bd9d18008fb1fd5919fdc297267048670b6eac1f/skills/multithreading/SKILL.md) | Worker completion/cleanup, main-thread scene commits, threaded loading. No second chunk scheduler around Voxel Tools; shared payloads still need correct synchronization. |
| [GDAS: godot-gdscript-mastery](https://github.com/thedivergentai/Game-Dev-Agentic-Skills/blob/002d004c50b865406e58b3ec86508adab926d7f4/skills/godot-gdscript-mastery/SKILL.md) | Typed collections, safe iteration, node initialization. Filter blanket bans on parent calls, casts and print logging; preserve existing architecture and test markers. Do not execute linked EditorScripts. |
| [GDAS: godot-procedural-generation](https://github.com/thedivergentai/Game-Dev-Agentic-Skills/blob/002d004c50b865406e58b3ec86508adab926d7f4/skills/godot-procedural-generation/SKILL.md) | Seed isolation and algorithm selection for later biome/cave work. Generic Marching Cubes/ArrayMesh and WorkerThreadPool recipes do not replace Leyforge's blocky generator, sparse edits or streaming. |
| [GDAS: godot-resource-data-patterns](https://github.com/thedivergentai/Game-Dev-Agentic-Skills/blob/002d004c50b865406e58b3ec86508adab926d7f4/skills/godot-resource-data-patterns/SKILL.md) | Shared versus instance data, cache/loading and authoring choices. No conversion of canonical JSON registries or checksum saves into competing Resource databases. Runtime shared-resource mutation does not itself write the asset to disk; reject that overstatement in the skill. |

Indexes also cover scene/asset authoring, debugging and testing. These are future topic pointers, not additional adoption recommendations. GUT/gdUnit4, master routers, persona workflows and generic project scaffolding must not displace Leyforge's existing harness or ownership rules.

Both libraries overlap on typed GDScript, profiling, resources and async work; select one relevant reference rather than loading both catalogs. Their general-purpose resource/save, scene architecture and threading recipes can conflict with canonical registries, HOST authority and existing persistence. External mandatory-script directives do not become Leyforge requirements.

## Runtime and voxel compatibility

The [environment pin](../WAVE_0_ENVIRONMENT.md) records production target 4.7.2 and Voxel Tools GDExtension 1.7 (`v1.7x`, source `75d3c6d996ed2331c80edcd8c3ebc947afc0f041`). Actual automation uses the shutdown-fixed 4.8-dev runner required by [W5.9](../WAVE_5_PART_9_FINAL_LOCAL_LAN_MULTIPLAYER_CERTIFICATION.md); its local console SHA-256 matches `06e7be7ed0298e81be421076a4a3166a7ae0e6b72c8a948d6faefd5823b3ee1a`. No runtime upgrade is proposed. The installed `addons/zylann.voxel/voxel.gdextension` declares minimum 4.4.1; this alone is not proof of every newer API.

`src/lfe/worldgen/wave_1_terrain_generator.gd` extends `VoxelGeneratorScript`, fills `VoxelBuffer.CHANNEL_TYPE` and preserves stored generator versions plus overrides. [Voxel generator docs](https://voxel-tools.readthedocs.io/en/latest/generators/) allow concurrent calls on the same generator; keep configuration immutable or correctly locked. Respect [Godot thread safety](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html): active scene-tree work belongs on the main thread, and shared resources need ownership/synchronization. Both collections are broadly relevant at the language/API level, but neither reviewed candidate establishes compatibility with this exact Voxel build. Validate an adopted example against pinned runtime/plugin APIs in its future task; no third-party executable, hook or script was run here.

## Baseline and bounded validation

Measurements and validation results follow below. Benefits from reduced rediscovery, selective reading and shorter repeated prompts remain hypotheses; no token, latency or billing telemetry was collected.

Lengths use LF-normalized UTF-8 text; words are whitespace-delimited, not tokens.

| Measure | Before | After |
| --- | --- | --- |
| Root AGENTS.md | 70 lines; 452 words; 3,627 characters / 3,629 bytes | 61 lines; 405 words; 3,570 characters / 3,572 bytes |
| Repository skills | 0 | 2 |
| Skill name + description values | 0 characters | 363 characters total; 421 including YAML keys/delimiters/newlines |
| Skill bodies + frontmatter | 0 | Development: 17 lines / 1,794 characters; verification: 24 lines / 2,544 characters |
| Repository task template | Absent; no comparable previous prompt artifact available | 21 lines; 141 words; 1,223 characters |

The obsolete bootstrap-target block and overlapping Wave-0-only authorization were removed; the future-tense first-multiplayer instruction was replaced by the existing authority invariant. The 13 core rules remain, with tighter wording. Root rules hold safeguards; skills link to them and existing contracts rather than copying their full contents. Startup skill metadata adds overhead: root reduction alone does not establish lower total context usage. This is a reusable routing improvement, not a measured token-saving result. No old/new prompt percentage is claimed without a comparable old template.

Two representative routing walkthroughs were checked by reading metadata and resolving the referenced files, without model benchmark sessions or implementation:

| Hypothetical authorized request | Relevant route and documents located |
| --- | --- |
| Repair a bounded UI readiness defect | `leyforge-development`: affected implementation/callers plus architecture boundaries; readiness handoff's New UI and Client lifecycle rows. Stage authorization still required. |
| Investigate a networking regression, then prepare certification | `leyforge-verification`: relevant stage document and existing `verify_wave_*.ps1` entry point; W5.9 policy distinguishes focused diagnostics, complete gate and owner acceptance. No gate was executed. |

Validation: both bundled Skill Creator frontmatter/name validators PASS; two correctly named folders at the documented repository discovery path; all 13 local Markdown links resolve; no stale Wave 0 permission or implied Wave 6 authorization; all 49 pre-existing dirty/untracked file hashes unchanged; no credential-pattern findings or private owner data included in the six-file review. Discovery compatibility is a static format/path check; automatic skill-picker activation in a fresh session was not tested. Review found no duplicated policy paragraphs; brief task routing and claim reminders point to the canonical rules. `git diff --check` passed. No dependency, executable hook, test framework or Codex home change.

The existing W5.9 receipt remains immutable automated PASS with LAN human acceptance required. This task changes no gameplay, scenes, content, project settings, engine/plugin, harness or receipt. W5.9's manifest also inventories documentation and AGENTS.md, so these documentation changes differ from that historical manifest. The toolkit commit is **not newly source-certified**; this explicitly authorized documentation-only publication does not recertify or alter the prior gameplay result. Future source changes still require their full mandated gate. Wave 5 remains open; Wave 6 has not begun.

Deferred: owner-approved selective external reference/adaptation with attribution/licence review and API checks; live fresh-session discovery smoke; usage telemetry from ordinary future tasks if wanted. No broader framework or new runner is proposed.
