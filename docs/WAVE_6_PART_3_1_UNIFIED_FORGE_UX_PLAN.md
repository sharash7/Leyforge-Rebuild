# W6.3.1 — Unified Forge UX proposal

**DIRECTION ACCEPTED — DOCUMENTATION RECONCILIATION AUTHORISED;
FINAL OWNER REVIEW PENDING. NO UI IMPLEMENTATION AUTHORISED.** Prepared 2026-10-19
(Australia/Perth) against `447bbd310afa6278bc3bdb359e3707585372b27d`.
This complements findings F11/F21 in the [alignment audit](WAVE_6_PART_3_1_ALIGNMENT_AUDIT.md).
The [W6.3 acceptance record](WAVE_6_PART_3_CLOSURE.md) retains the supplied feedback
and its chronology. W6.3 remains accepted; these recommendations do not imply
unresolved blocking functional defects.

The owner directs W6.3.1 to establish the coordinated interaction contract now,
before more workspaces proliferate. Final text and publication approval remain
separate. Useful Block/Texture and World workflows should inform an early
coordinated shell/interaction implementation review; Entity/Blueprint are later
adopters, not prerequisites. W6.17–18 integrate/harden established patterns and
Wave 19 may provide final high-fidelity theme/icons/art. This replaces the first
proposal's late W6.16/17 readiness trigger without changing historical feedback.

## Evidence and usability goals

The owner reports dense controls, too much similar text, indistinct buttons,
little new-user guidance, missing searchable voxel assets and confusion between
asset IDs and existing block-colour references. Source review confirms explicit
workspace tabs, manual ID entry to open a voxel asset, several flow rows of
similar buttons, and a shared inspector mixing identity, palette, recovery and
technical data. Scroll/collapse support and successful historical three-size
automation already exist. No fresh UX session or accessibility conformance audit
was performed for this plan.

The [shell](../tools/forge/forge.gd) already hides catalog actions/status while
the Voxel Asset tab is active. Do not report that hidden toolbar as a persistent
W6.3 bug. The remaining problem is learning which document, source and reference
an action addresses. The [voxel workspace](../tools/forge/workspaces/voxel_asset/voxel_asset.gd)
uses “Stable asset ID”, “Swatch key (stable)” and “Existing solid block ID”, but
labels alone do not provide discovery or clear mental grouping.

Aim for a creator who can identify the active asset, open existing work, choose
an editing tool, understand draft versus published state, find a recoverable
error and test the published result without memorising canonical IDs. Keep
advanced technical identities available on demand. This is a proposed behavior
contract under final text review; no measured usability target is claimed to be
met yet. The [M08 amendment](WAVE_6_PART_3_1_PROPOSED_AMENDMENTS.md#early-unified-interaction-contract)
records this planning direction without authorising implementation.

## Shared interaction contract established in W6.3.1 planning

| Requirement | Common interaction rule for future authorised tasks |
| --- | --- |
| Four-domain navigation | One consistent Asset/Entity/Blueprint/World hierarchy, active document breadcrumb and available-workflow navigation; no empty framework or workspace bus. |
| Searchable library | Canonical-derived typed discovery, with separately identified profile drafts and bounded derived caches; no shadow registry or implicit canonical creation. |
| New/Open/Recent | Reuse the same meanings across real workspaces; preserve current dirty/conflict/recovery state before switching and never silently merge or overwrite. |
| Identity separation | Label authored assets, block/item definitions, render material references and local swatch keys distinctly; show resolved runtime output as derived data, not a second authored identity. |
| Persistent document state | Keep active identity, dirty/draft state, current validation revision, published version and current/stale/missing bake unmistakable; no single green check that conflates them or transient message that erases recovery state. |
| Lifecycle actions | Save Draft, Validate, Publish, Bake, Test and Export remain separate, target-labelled actions with prerequisites and destination/revision visible. |
| Context inspectors | Show the selected document, cells, swatch/material/reference, issue or recovery context; hide unrelated technical detail through explicit disclosure, not lost access. |
| Editing tools and hierarchy | Discoverable labelled tools, readable active modes, clear primary/secondary/destructive actions and visible plane/selection/box state; no colour-only meaning. |
| Keyboard/mouse principles | Text entry and modals take priority; tools act only in their context, camera gestures never edit source, focus loss cancels pending gestures and shortcuts do not leak across documents. Document exact bindings before changing them. |
| Responsive layout | Preserve viewport space, reachable lifecycle/recovery actions and collapsible/restorable panels at all three existing validation sizes; layout state stays profile-local. |
| Accessibility and feedback | Persistent labels, visible keyboard focus, logical tab order, concise text-backed status/errors, tooltips and recovery guidance; icons supplement labels. |
| Switching/conflict/recovery | Explain saved draft versus published source and stale dependencies; preserve last good bytes and unfinished-gesture cancellation, with explicit safe choices only when state requires them. |

These are shared planning rules, not a new schema, UI framework or implemented
accessibility certification. The first authorised tasks should apply them to
real workflows and report task-based evidence; exact shortcuts/layout/theme and
any common implementation extraction remain bounded implementation decisions.

## Navigation hierarchy

Home remains the project entry with canonical root, active/recent documents,
draft/recovery notices and links to available workflows. Organise growing
navigation under the four approved domains:

| Domain | Example future destinations and scope boundary |
| --- | --- |
| Asset Forge | Voxel models, full blocks, materials, 32×32 textures, item/tool/equipment assets; only implemented destinations are actionable |
| Entity Forge | Creature/entity definition, visual/attachment and collision workflows when their runtime consumers exist |
| Blueprint Forge | Structures/buildings/assemblies referencing canonical definitions; placed instances remain world state |
| World Forge | Versioned generation/biome/world parameter workspaces and disposable previews; no owner world editing inferred |

Use an active-document breadcrumb such as `Asset Forge / Voxel Asset / display
name`, with type badge and inspectable canonical ID. Distinguish workspace
navigation from switching the open document. Show unavailable future capabilities
as explanatory coverage when useful, not an expanse of empty clickable editors.
Do not implement automatic workspace discovery or a plugin bus to achieve this.

## Asset library and New/Open/Recent

The future library is a derived searchable view over canonical sources and
profile drafts. It is not a second authority or registry. Begin with file-derived
voxel asset discovery using the existing strict path/ID parser; add other asset
types only as real workflows consume them.

- Search display name and canonical ID; filter by type and draft/published state.
  Cards or rows show type, name, ID, source state and a bounded preview if useful.
  A stale/corrupt source remains discoverable with a clear diagnostic.
- **New** chooses the supported asset type, then asks for identity/name and
  explains uniqueness. It does not create canonical content until Publish.
- **Open** selects an asset rather than requiring a memorised ID. If a draft and
  published source both exist, show their states and offer the existing safe
  source/draft/recovery choices. Never silently overwrite or merge them.
- **Recent** stores profile-local references to documents, not copies of content.
  Missing/moved/conflicted entries explain the problem and offer library/recovery
  navigation. A future rename workflow needs its own canonical reference policy.
- Switching documents must retain the current save/recovery guarantees and
  unfinished-gesture cancellation. Ask Save draft / Keep recovery / Cancel only
  where needed by actual state; do not add unconditional confirmation friction.

Initial search can be a small improvement in the next authorised asset workflow.
Full multi-domain library navigation, thumbnail caching and Recent integration
belong to the coordinated pass after enough document types exist. Cache location,
invalidation and limits must be explicit and outside `content/`.

## Clear actions and document state

| Action | Creator meaning | Visible state and safeguards |
| --- | --- | --- |
| Save draft | Preserve local edits/history for later work | Name the draft destination/state; no canonical change; report failure and retain last good bytes |
| Validate | Check this revision and its references | Show valid/stale/error/warning with actionable location; revalidate when source/dependencies change |
| Review / Publish | Apply reviewed canonical source changes | Show identity/destination/version and diff; explicit confirmation; conflict explanation and recovery path |
| Bake | Compile published source into derived runtime data | Show published version/hash and current/stale/missing output; baking a dirty draft must not imply those edits were published |
| Test | Consume the relevant published/baked revision in disposable runtime | Name the consumer and tested revision; distinguish standalone model proof from gameplay/terrain testing |
| Export | Copy a named draft or bake to a chosen safe location | State which artifact is copied and why; preserve protected roots and source |

Avoid a generic “Save” that makes publication ambiguous. Do not combine
Publish/Bake/Test into an implicit mutation chain. Display draft dirty state,
validation state, published revision and bake state independently. A single green
check must not suggest all four succeeded. Recovery/conflict status persists until
resolved; transient hover/tool feedback must not erase it.

## Model workspace and context-sensitive inspector

The eventual layout has a compact document/action header, a library area, central
viewport with tool strip, context inspector and concise status/diagnostic drawer.
Allow the library/inspector to collapse, retain viewport space and restore panels
through obvious controls. This layout is a proposal for the coordinated pass;
the next small workspace need not rebuild the entire shell.

| Context | Inspector content |
| --- | --- |
| Document/model | Display name, type, bounds/density readout, source/draft state and publication identity |
| Selected cells | Count/bounds, active swatch and permitted operation; distinguish empty selection from empty model |
| Palette swatch | Local key, literal colour or block-colour reference mode, resolved colour preview and reference diagnostic |
| Block reference picker | Existing solid blocks with names and IDs, clearly labelled “colour only”; no gameplay property inheritance implied |
| Validation issue | Field/cell/reference location, reason, affected revision and next valid action |
| Recovery | Preserved draft/source conflict details and explicit recovery/export choices; technical detail expandable |

Identity and palette references need separate visual groups. A voxel asset ID
names authored geometry, a block/item ID names gameplay content, a render
material reference names an approved visual definition, and a swatch key is local
to one model. Resolved runtime colour/material/mesh data is derived output.
Search results/selectors must carry type labels even when IDs look alike;
introducing material references still requires approved consumer/schema scope.

The construction plane, active tool and selection/box extent should be visible
near the viewport where they affect editing. Retain 1 m reference, cell/metre
coordinates, explicit camera hints and frame controls. Camera/selection/layout
never enter document history. The common focus/input/camera principles are
defined above now. Exact mouse/keyboard bindings must be documented and tested
for each authorised workflow, with text/modal precedence and no accidental edit
during navigation; existing bindings change only in a separately authorised task.

## Visual hierarchy, accessibility and feedback

Use headings/group spacing for Identity, Tools, Palette, Selection and Lifecycle;
render technical IDs/details as secondary information. Primary current actions,
secondary utility actions, active tools and destructive recovery actions need
distinct treatment. Do not make destructive actions more prominent than routine
editing. A status icon should have text; colour alone must not carry meaning.

Keep persistent accessible text labels, keyboard focus visibility, sensible tab
order and tooltips describing action, shortcut and prerequisites. Icons supplement
labels. Explain disabled actions, especially Bake/Test when the current source or
output is absent/stale. Tooltips should not be the only path to essential guidance.
Native colour selection needs a visible swatch/key/reference label.

Show a short action/result message near the relevant context, plus expandable
technical detail. Distinguish “draft saved”, “source published” and “bake created”.
Errors identify cause and recovery action: stale source → reopen/export, missing
reference → choose valid block, invalid plane target → choose valid cell. Avoid
generic operation-committed text when the actual action can be named. New-user
guidance should demonstrate the next valid step without blocking experienced users.

At 1920×1080 and 1280×720 retain normal multi-panel editing. At 960×540 collapse
secondary panels and wrap/scroll controls while preserving the viewport, status,
close, recovery and publication actions. Test actual reachable controls after
reflow, font/display scaling and keyboard navigation; historical screenshot PASS
does not certify the redesigned layouts. Persist layout in the Forge profile,
never in canonical content, commands or game saves.

## Group A — small improvements within upcoming authorised workspaces

These are candidates to include naturally in bounded workspace tasks; this plan
does not separately authorise them:

| Candidate | Why it fits incrementally | Verification |
| --- | --- | --- |
| Clarify source/draft, asset/block/swatch labels and “colour only” hints | Uses existing states and controls without a shell rebuild | Owner can identify target document/reference and mutation destination |
| File-derived voxel search/Open selector | Solves the immediate missing discovery path | Correct IDs/types; corrupt/missing source; draft conflicts; no parallel registry |
| Tooltips, active tool highlight, clearer action/status text | Reuses existing tools/results and input owners | Text/focus isolation, shortcut behavior, no colour-only state |
| Group crowded fields/actions and move technical details behind disclosure | Improves readability with existing scroll/collapse patterns | Three sizes, reachable recovery/publish, no lost editing state |
| Revision/bake stale-state explanation | Exposes existing lifecycle semantics | Dirty draft vs published source vs stale output never conflated |

Each candidate maps to audit F11/F21 (B, medium/high), depends on the actual
document/result owner, should have UI/profile-only impact and needs focused
rendered verification plus affected stage regressions. Do not add a style system,
global event bus or duplicate state store for these improvements.

## Group B — early coordinated shell and interaction implementation review

The coordinated pass covers shared four-domain navigation, multi-type searchable
library/New/Open/Recent, document/action/state presentation, inspector patterns,
layout persistence, consistent visual hierarchy, keyboard/accessibility treatment
and reusable interactions across workspaces. Separate the common interaction
design from final theme/icon/art production, which can mature later.

The coordinated design contract is defined in W6.3.1 now. Review early bounded
shell/interaction implementation after useful Block/Texture and World workflows
reveal genuine common patterns. Do not wait for every advanced Block/Material
feature, Entity/Blueprint maturity or W6.16/17. The owner reviews concrete scope
and task-based acceptance before any implementation; the present direction does
not authorise a rebuild. Reuse proven controls/owners and extract shared behavior
only when demonstrated, without a generic UI framework or repeated shell rewrites.

As Entity and Blueprint workflows mature, extend the established patterns to
them rather than making them prerequisites for the early coordinated review.
Reserve W6.17–W6.18 for interaction integration and hardening alongside living-world
integration and full certification. Final high-fidelity theme, iconography and
artistic polish may remain Wave 19; discovery, clear state and usable lifecycle
actions belong to the earlier interaction work. Preserve all stage numbers.

Before implementation, agree task-based acceptance examples: a new creator opens
an existing asset through search, resumes its draft, distinguishes an asset from
a colour reference, edits a model, resolves a validation issue, publishes exactly
the intended source, bakes and tests the expected revision, then changes workspace
without losing work. Record actual observations and assistance needed; do not
invent completion times or per-test passes. Include recovery, keyboard operation,
three viewport sizes and relevant rendered regressions. Final document text and
publication approval remain pending; any implementation needs separate owner
authority. W6.4 is NOT AUTHORISED. Stop after documentation preparation/validation.
