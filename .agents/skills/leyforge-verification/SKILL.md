---
name: leyforge-verification
description: Select and report Leyforge development checks, affected integration regressions or required final stage certification after changes or during failure investigation.
---

# Leyforge verification

Apply root [AGENTS.md](../../../AGENTS.md) for the approved runner, isolation and evidence rules. The authorized stage specification defines required commands and acceptance criteria; this skill does not replace them.

Choose the level from the change and intended claim:

| Level | Work and claim |
| --- | --- |
| Development checks | Run focused validation for the changed component and risky invariants. Documentation-only tasks need path/frontmatter/whitespace and scope checks, unless their stage explicitly requires more. Report focused results. |
| Integration checks | Exercise affected callers and cross-system contracts. Changes to generation, saves, authority, transactions or lifecycle require the relevant existing regressions. Explain coverage and remaining gaps. |
| Final certification | Run the full required gate against final source and approved runner before claiming certification or publishing when stage policy requires it. Focused/skip-regression/shortened-soak diagnostics cannot replace mandatory final regressions. |

Find existing entry points in `tools/development/verify_wave_*.ps1` and the relevant stage document. For W5.9, use the [certification policy](../../../docs/WAVE_5_PART_9_FINAL_LOCAL_LAN_MULTIPLAYER_CERTIFICATION.md); do not run it merely because this skill was selected. Future stages must name their gate rather than assume W5.9 certifies new work.

For multiplayer, retain required separate graphical HOST/JOIN OS processes and real UI/input coverage. Physical two-PC LAN owner acceptance is distinct from automated evidence; follow the current [scope amendment](../../../docs/WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md).

Retain complete raw logs and append-only receipts. Return exit status, pass/failure counts, failing test identifiers and exact evidence paths; extract only failing markers and nearby context with scoped searches. Read full logs when those excerpts cannot explain a failure. After a repair, rerun affected checks and every final regression required by stage policy. Do not repeatedly rerun passing suites without a new change or unresolved concern.

Check source/runner identity before reusing a receipt. A historical PASS remains evidence for its recorded snapshot; it is not a fresh source-match assertion for a changed manifest.
