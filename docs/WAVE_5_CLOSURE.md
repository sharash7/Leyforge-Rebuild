# Wave 5 closure — Local/LAN

Decision recorded **2026-10-16 (Australia/Perth)** against `main` at
`c14406f6143b9e03bb3906cd4c7f159a36afbaea`.

**CLOSED FOR PROGRESSION — OWNER-ACCEPTED LAN-FIRST SCOPE.** The owner reports
that the W5.9 two-computer multiplayer test works and explicitly approves
progression into Wave 6. This records the owner's overall acceptance decision;
it is not a Codex-conducted physical LAN test or a completed per-test checklist.
The current task authorizes documentation/planning only. W6.1 implementation
and W6.2 or later work have not begun in this task.

## Evidence and source identity

| Record | Retained fact |
| --- | --- |
| Automated certification commit | `fe4411c6ca9cf2598d1564ff3ce5cd0461f8c29e` (`test: certify local LAN multiplayer foundation`) |
| Final receipt | `.verification/wave5/w5_9/run-20261015T092724971/gate.json` (local ignored evidence, not bundled into this documentation commit) |
| Receipt SHA-256 | `dbf56c00e09d9ec6ea285793dbe01f9a868183870063e2f6eadd4bcee579c2c6` |
| Source manifest | Same run's `source_manifest.json`; SHA-256 `f72b322f3605ae8e04ff766ade893c1b07830e92c6b92c4a5e2afc5283334ae0` |
| Source reconciliation on 2026-10-16 | All 469 pinned files and the inventoried path set exactly match Git blobs at `fe4411c6ca9cf2598d1564ff3ce5cd0461f8c29e` |
| Receipt status | `passed=true`, `certified=true`, `snapshot_matches_source=true`, `secret_redaction=true`, `classification=AUTOMATED_CERTIFIED` |
| Automated coverage | 585 focused checks, no focused failures; full Waves 0–4 and W5.1–W5.8 regression chain including W5.6 Repair 1; three-process continuous soak 660.015 seconds / 45 cycles; separate five-player smoke |
| Version tuple | Application `0.6.1-wave5-w5.9`; protocol/save/content/worldgen `7/4/1/2`; stored worldgen v1 supported |
| Console runner SHA-256 | `06e7be7ed0298e81be421076a4a3166a7ae0e6b72c8a948d6faefd5823b3ee1a` |
| Graphical runner SHA-256 | `87d0a6077abe38b905f973b23d9f27fd4f3b7a8db2309dfd6807fad7dff582c8` |

The receipt's `starting_commit` is
`bbe49b2e79193ae241c9a6eaaa73485abae403ae`: that is the pre-W5.9 baseline,
not the final certified publication SHA. The manifest comparison above binds
the final candidate bytes to `fe4411c6ca9cf2598d1564ff3ce5cd0461f8c29e`.
Raw reports, copied regression receipts, metrics, screenshots, failed and
uncertified attempts remain unchanged at their original paths. The automated
matrix and measurement limits remain in the [W5.9 contract](WAVE_5_PART_9_FINAL_LOCAL_LAN_MULTIPLAYER_CERTIFICATION.md).

The post-certification [Codex toolkit commit](development/CODEX_TOOLKIT_NOTES.md),
`c14406f6143b9e03bb3906cd4c7f159a36afbaea`, changed six workflow/skill documents.
Within the W5.9 inventory it changes `AGENTS.md` and adds three development
documents. Thus neither that commit, this documentation update, nor the dirty
working tree has a fresh full-manifest source match. Existing local editor/test/
content changes and UID sidecars are outside this closure publication. No new
runtime certification is claimed and no gate was rerun for this documentation task.
The existing LAN-kit builder checks the complete committed inventory: packaging
current HEAD as a newly certified kit requires a new matching full gate. Do not
weaken that check or relabel the old receipt to make packaging succeed.

## Owner report and missing detail

The 2026-10-16 task supplies two facts: W5.9 two-computer multiplayer works
(reported LAN success under this task's LAN-first scope), and the owner approves
Wave 6 progression. It supplies no itemized observations or manual test artifact.

The [original owner form](WAVE_5_PART_9_FINAL_LOCAL_LAN_MULTIPLAYER_CERTIFICATION.md#owner-lan-acceptance-gate)
also asks for the tested commit/kit, explicit two-physical-PC same-LAN topology
and private LAN-endpoint confirmation, invite acceptance, approximately 15-minute
duration, movement, voxel edits, inventory/drops, crafting/functional objects,
survival, contention, reconnect, HOST shutdown, save/reload, lag and bugs.
Those details are **NOT REPORTED individually** here. Do not mark any of those
rows PASS, assert the tested commit, infer a duration, or publish addresses/invites.
The owner's overall decision is recorded without claiming checklist completeness.

The current explicit closure/progression direction is the authority for closing
the stage despite that incomplete manual traceability. This is an owner decision
record, not proof that every mandatory form observation was supplied. If a later
review requires checklist-complete physical acceptance, the missing fields must
come from the owner; automated evidence cannot fill them in.

## Residual classification and next boundary

- No new blocking correctness defect is identified by this bounded review;
  it does not establish that the dirty working tree is defect-free.
- Manual test traceability is incomplete as listed above; retain that limitation.
- Direct WAN remains **UNVERIFIED / DEFERRED TO WAVE 17**, under the
  [scope amendment](WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md) and
  [ADR-0008](adr/ADR-0008_WAVE_5_LAN_FIRST_COMPLETION_AND_WAN_DEFERRAL.md).
  The receipt still correctly says `real_LAN_certified=false`,
  `real_WAN_certified=false`, `manual_acceptance=LAN HUMAN ACCEPTANCE REQUIRED`:
  those are historical automated-run facts, not fields to overwrite.
- Unencrypted ENet, self-held UUID identity, no migration/dedicated server,
  last-successful-save crash recovery and bounded player-count measurements
  remain current architectural limits. WAN/relay/discovery/account/secure
  transport work stays in Wave 17; no online acceptance is implied.

Use the [readiness handoff](WAVE_5_TO_WAVE_6_READINESS_HANDOFF.md) and
[proposed W6.1 specification](WAVE_6_PART_1_READINESS_UI_AND_INTEGRATION_FOUNDATION.md)
for the next implementation task. General progression approval does not expand
this task beyond documentation or authorize speculative systems.
