# W6.1 closure — Readiness, UI & Integration Foundation

**CLOSED — OWNER ACCEPTED, 2026-10-18 (Australia/Perth).** The owner reports
manual testing at published commit
`16d6ccd2da86a0f71d2929e18caa373c0206d48b`, all **9/9** UI acceptance checks
PASS and no blocking defects. The supplied observations are exactly:

- Inventory open/close
- Crafting, Workbench, Storage and Kiln
- Names, quantities and durability
- Scrolling and Crafting Manual
- 1920x1080, 1280x720, 960x540 layouts
- Split/swap/quick transfers
- Pending/accepted/rejected feedback
- HOST/JOIN disconnect and reconnect
- Smooth drops without ghost items

This is the owner's decision and report, separate from automated certification.
No additional topology, duration, test-world identity or manual observations are
inferred. The [W6.1 specification and repair history](WAVE_6_PART_1_READINESS_UI_AND_INTEGRATION_FOUNDATION.md)
remain available.

## Retained automated evidence

| Record | Verified fact |
| --- | --- |
| Certified publication | `16d6ccd2da86a0f71d2929e18caa373c0206d48b` |
| Final W6.1 receipt | `.verification/wave6/w6_1/run-20261017T033757778523000/gate.json` |
| Receipt SHA-256 | `fa644f2db0adc3f3c11658dac36da69c732d7a581612cfc598ff8ed0d26ad2b3` |
| Source manifest | Same run's `source_manifest.json`, SHA-256 `4041e0c66397f7f46759a6dd68f173e4a6e2d7325ab9bfc94f58646783115ca7` |
| Runner manifest | Same run's `runner_manifest.json`, SHA-256 `e7f509bece9d98190673658b0969bf314e57263506739ca4b6438250f6862ddc` |
| Source reconciliation on 2026-10-18 | All 478 manifest entries match exact Git blob bytes at the certified publication |
| Final receipt flags | `passed=true`, `certified=true`, `snapshot_matches_source=true`, `full_regressions=true`, `focused_graphical=true`, `focused_only=false`, `secret_redaction=true` |
| Complete nested regression receipt | `.verification/wave5/w5_9/run-20261017T034030253/gate.json`: certified PASS, full Waves 0–4 / W5.1–W5.8 chain including W5.6 Repair 1 |

The receipt's `starting_commit` is the pre-implementation baseline
`7623595424dfb3ca6c98e45bfcf28afdab3e353c`, not the final certified SHA.
Its `manual_acceptance=OWNER UI ACCEPTANCE REQUIRED` remains an accurate
historical run field; today's owner decision does not modify it.

Keep all original raw logs, screenshots, checks, manifests, nested receipts and
failed diagnostics at their original ignored local paths. This includes
`run-20261016T110659565588100/gate.json` beneath `.verification/wave6/w6_1/`,
the retained earlier attempts and `run-20261017T033008-drop-repair/` baseline,
candidate, failed and repaired long-frame drop probes. Do not replace failures
with later PASS evidence. These local artifacts are not bundled into this commit.

No runtime gate was rerun for this documentation-only closure. Later documentation
and existing dirty source/editor/UID files have no new full-manifest certification;
the reconciliation above applies to the recorded publication only.

## Next boundary

[Wave 5 LAN-first closure](WAVE_5_CLOSURE.md) and its manual traceability limits
remain unchanged. Direct WAN remains **UNVERIFIED / DEFERRED TO WAVE 17** under
the [scope amendment](WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md). No new LAN
topology or WAN certification is inferred from this UI acceptance.

The [W6.2 Forge foundation specification](WAVE_6_PART_2_FORGE_FOUNDATION.md) is
proposed for owner approval only. Preserve the established Forge-first W6.2–W6.18
roadmap. W6.1 acceptance authorizes no W6.2 or W6.3 implementation by itself.
