# Codex workflow

Keep the user's existing **GPT-6.1 Sol** configuration. These are starting points, not measured cost guarantees:

| Task size | Typical work | Reasoning effort |
| --- | --- | --- |
| SMALL | Documentation, straightforward fixes, contained changes | Low for clear mechanical work; medium if judgment is needed |
| MEDIUM | Single-system implementation, integration, bounded refactoring | Medium |
| LARGE | Major architecture, difficult failures, save/network changes, certification | High; consider higher effort only when unresolved complexity warrants it |

Increase effort before considering a different model. Suggest a model change only when the task's difficulty plausibly justifies its usage cost; do not silently switch configuration. No exact savings have been measured.

## Start and continue work

Open `D:\AI\Projects\Leyforge-Rebuild` as the project. Fill in the [task template](CODEX_TASK_TEMPLATE.md), referencing the detailed authorized stage specification. Use `$leyforge-development` for implementation/repairs and `$leyforge-verification` for validation/certification. Metadata permits automatic selection too; explicit mentions make intent clear. New skills may require a fresh Codex session before appearing in the skill picker. No global installation is needed.

Continue the same chat for short repairs and direct follow-ups. Start a new chat for a new stage or when accumulated context becomes large or misleading. Carry only current SHA, scope, relevant document paths, unresolved issues and evidence paths into the handoff. The detailed stage specification remains authoritative for W6.1-W6.18; the template grants no stage authority.

Search named directories/files first with `rg`; batch independent reads and inspect relevant ranges. Reuse discovered paths, then refresh mutable repository state at edit/publication boundaries. Load only the applicable skill and linked task material. Keep full logs in files and inspect targeted failure excerpts.

During development use focused checks; run affected integrations when contracts cross systems. Required final certification remains complete and source-matched. See `$leyforge-verification` for claim boundaries. Report behavior, concise results, evidence paths, limitations and commit/push state; avoid pasting whole receipts repeatedly.

## Current status pointer — 2026-10-16

W5.9 automated **PASS** at `fe4411c6ca9cf2598d1564ff3ce5cd0461f8c29e`;
the owner reports two-computer LAN success and approves Wave 6 progression.
[Wave 5 is closed for that scope](../WAVE_5_CLOSURE.md), with manual checklist
details incomplete and later documentation/dirty source not newly certified.
WAN remains deferred to Wave 17. The [W6.1 specification](../WAVE_6_PART_1_READINESS_UI_AND_INTEGRATION_FOUNDATION.md)
is proposed; this task implements no Wave 6 systems. The next task must authorize
the bounded implementation and its final gate.

This dated pointer creates no authority. Consult the [W5.9 policy](../WAVE_5_PART_9_FINAL_LOCAL_LAN_MULTIPLAYER_CERTIFICATION.md), [scope amendment](../WAVE_5_MULTIPLAYER_SCOPE_AND_WAN_DEFERRAL.md) and [readiness handoff](../WAVE_5_TO_WAVE_6_READINESS_HANDOFF.md) when status affects a decision. Retained receipt: `.verification/wave5/w5_9/run-20261015T092724971/gate.json`.

Research, candidate external skills and size measurements are in [toolkit notes](CODEX_TOOLKIT_NOTES.md); read them when evaluating workflow changes, not on every implementation task.
