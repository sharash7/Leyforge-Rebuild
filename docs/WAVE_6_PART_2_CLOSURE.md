# W6.2 closure — owner accepted

Status: **CLOSED — OWNER ACCEPTED**, recorded 2026-10-18 (Australia/Perth).
Accepted published commit: `d886702bac6a8ca9aec245ed08ca74371f7136c6` on `main`.
The [W6.2 specification](WAVE_6_PART_2_FORGE_FOUNDATION.md) defines the bounded
Forge foundation. This record separates the owner's decision from automated proof.

## Owner acceptance

The owner reports testing W6.2 at the published commit on 2026-10-18 with
**10/10 PASS and no blocking defect reported**, accepting:

1. Forge Home and workspace navigation.
2. Canonical block browsing.
3. Name/colour editing and preview.
4. Undo, redo and branched history.
5. Persistent drafts.
6. Validation and before/after review.
7. Disposable-clone publication/conflicts.
8. 3D orbit, pan, zoom and frame.
9. Camera/text-input isolation.
10. All three required viewport sizes: 1920×1080, 1280×720 and 960×540.

These are the supplied acceptance categories, not reconstructed per-input test
logs. No additional recovery, performance, topology or failure-injection owner
observations are inferred. The owner describes the UI as functional but early
stage; workflow-specific improvements are considered in the
[W6.3 proposal](WAVE_6_PART_3_VOXEL_ASSET_FORGE_DESIGN.md).

## Historical automated certification

Evidence root (ignored local artifacts):
`.verification/wave6/w6_2/run-20261018T093805-255505200/`.

| Evidence | Recorded result / identity |
| --- | --- |
| `gate.json` | `passed=true`, `certified=true`, `focused_only=false`, `focused_graphical=true`, `full_regressions=true`, `snapshot_matches_source=true` |
| `focused.json` | 57 recorded focused checks; preserve individual results in the original file |
| `publication.json` | Commit, origin/main and remote/main recorded as `d886702bac6a8ca9aec245ed08ca74371f7136c6`; `normal_push=true`, `certification_matches_committed_owned_blobs=true` |
| `precommit-review.json` | Records 496 source entries, source/index match and unchanged protected files |
| Nested W6.1 | `.verification/wave6/w6_1/run-20261018T093931401648900/gate.json`, certified full PASS |
| Nested W5.9 | `.verification/wave5/w5_9/run-20261018T094202110/gate.json`, certified PASS, complete Waves 0–5 regression chain and original full 660-second soak contract |

SHA-256 identities read during closure:

| File under evidence root | SHA-256 |
| --- | --- |
| `gate.json` | `8b0bb0c24c4bc0bea9e894505028cd94642adc3585b1dd87f1603a059aa7c8ba` |
| `source_manifest.json` | `380411b4b4314d808c4255038c24d4b4040104e1d2401e0a52834aa6efb15fb9` |
| `runner_manifest.json` | `e7f509bece9d98190673658b0969bf314e57263506739ca4b6438250f6862ddc` |
| `publication.json` | `54c6f22e9cef1b9e4b245d9afbf6d379795ef0786679977db9afd323952e28124` |

The gate's `starting_commit` is the earlier baseline
`b7964c8bcce21242d7881f6e2e01a24b50f7de13`, not the published certified commit.
The historical `manual_acceptance=OWNER FORGE ACCEPTANCE REQUIRED` fields stay
unchanged; this separate record supplies the later human decision. Closure
checks found all 20 manifest-covered owned Git blobs at the published commit
match their recorded SHA-256 values. The 21st owned file, `README.md`, is outside
that manifest's coverage; the two owned documentation files under `docs/` are
covered. This does not assert that all current dirty files match the certified
snapshot.

Retain every original log, screenshot, input report, fixture, recovery copy,
manifest and receipt. Earlier failed and focused-only runs remain under
`.verification/wave6/w6_2/`, including the `run-20261018T050617-701906000/`
publication failures and subsequent attempts. Also retain the later
`run-20261018T114324-393347300/gate.json`: it records `passed=false` and
`certified=false` starting from the published commit. It is not certification;
its cause is not diagnosed or relabelled by this documentation task. The earlier
published certified receipt and the owner's acceptance remain separately named.
Retain the W5.9 water negative control and repair evidence described in the
W6.2 specification. No failures are replaced by PASS receipts.

## Closure boundary

No runtime gate is rerun for this documentation-only closure. New documentation
and unrelated dirty source/editor/content/UID files receive no new automated
certification. Canonical content, owner drafts and game saves are unchanged.
WAN remains unverified and deferred to Wave 17 under the
[existing scope amendment](WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md).

W6.2 closes the existing presentation-authoring foundation, not spatial voxel
modelling. The [W6.3 design](WAVE_6_PART_3_VOXEL_ASSET_FORGE_DESIGN.md) is a
candidate for owner ratification. Neither closure nor that proposal authorizes
W6.3 implementation, new content, dependencies or save/protocol migrations.
