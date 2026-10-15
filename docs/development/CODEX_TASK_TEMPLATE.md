# Codex task handoff

Fill placeholders; reference the detailed stage specification instead of pasting it. Suitable for future W6.1-W6.18 tasks only after their prerequisites and explicit authorization.

```text
Task: <stage/title; SMALL, MEDIUM or LARGE>
Repository: D:\AI\Projects\Leyforge-Rebuild
Branch / starting SHA: <branch> / <full SHA; verify before editing>
Authorized scope: <components/files and explicit exclusions>
Relevant documents: <stage specification + only applicable ADR/contract paths>
Required behavior: <observable outcome and acceptance examples>
Preservation constraints: <task-specific protected paths/data; root AGENTS.md applies>
Verification gate: <focused checks, affected integrations, required full final gate;
                    source/runner matching and any separate owner acceptance>
Commit / push authorization: <none, commit only, or commit + normal push; target>
Use: $leyforge-development for implementation; $leyforge-verification for checks.
Expected final report: changed behavior/files; checks and evidence paths;
                       limitations/acceptance still pending; commit/SHA/push result.
```

This template does not replace stage policy or authorize the next stage.
