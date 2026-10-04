# Wave 4 hold-LMB gathering interaction hotfix

Wave 4 is otherwise owner accepted. Application `0.4.5-wave4` corrects the final interaction defect and awaits the owner's spot-check. Wave 5 has not begun.

## Authority and scope

Repository: `D:\AI\Projects\Leyforge-Rebuild`, branch `main`. Starting HEAD: `1aab94f2260324fc3bac64c5279cab959f39dc5b` (`fix: correct Dense Stone voxel-scale presentation`). Fetch confirmed matching `origin/main`, 0/0 ahead/behind, an empty index and one worktree before changes. Integrity passed with the same three historical dangling blobs. The unrelated `.gitignore`, `project.godot` editor settings and `scenes/main/wave_1_playground.tscn` changes were backed up and preserved.

Only gameplay input/harvest orchestration, cancellation at menu opening, feedback, their verification drivers and current documentation change. Canonical balance, source semantics, resource transactions, durability, crafting, voxel generation and persistence remain unchanged. Dense Stone remains a unit-cube finite source yielding ordinary Stone with mining capability 2.

## Input and authoritative work

`LeyforgeFirstPersonPlayer.sync_primary_action_input()` sends continuous `Input.is_action_pressed("break_block")` state to `LeyforgeWave1Playground.set_primary_action()`. Normal world simulation polls before advancing work. The player's `_input()` handles release before GUI consumption; it clears the attempt immediately. Menu opening, Escape/mouse release, loss of runtime readiness and death also explicitly cancel. Input and world authority remain separate, with begin, held continuation and cancel seams; no networking is introduced.

An attempt cannot begin without active primary input. Each continuation validates the same current crosshair target, editable loaded terrain, range, occlusion, original voxel identity or exact finite-source snapshot, removal eligibility, health, menu state and recomputed tool effect. Changing equipped instance, losing capability or changing effective duration cancels. Looking away and returning begins again from zero. Cancelled work is transient, produces no output/wear and is never saved.

Full work performs exactly one existing authoritative break or source transaction, with its exact output and valid one-use durability cost. Work clears even if the transaction rejects. Excess time is discarded. While LMB stays held, a later input step may begin another valid target from zero; no completion loop or work transfer exists. All ordinary terrain, Heartwood, breakable leaves and finite gatherable sources use this contract. The explicit historical development selector remains the isolated instant-edit path for Wave 1/2 development gates, outside normal production gathering.

The highlight remains. Permanent instructions read **Hold LMB — gather/mine**; the crosshair and active-attempt status reinforce holding. No progress-bar redesign was needed.

## Balance and compatibility

Manual Heartwood remains 1 second, Wooden Axe approximately 0.667 seconds and Stone Axe approximately 0.333 seconds. Tool class/capability, recipe quantities, conservation, source stock and durability remain authoritative canonical data. Successful Heartwood mining yields one block; a successful Dense Stone source action delivers its existing six-unit stock and consumes one matching tool use. Cancelled attempts deliver neither.

Save schema remains 3, content version 1, newly created worldgen version 2 and existing stored v1 worlds remain v1. No payload or canonical definition changes occur. Existing worlds receive the interaction fix without migration; unfinished gathering was already transient.

## Verification

Full certified gate: `.verification/wave4/run-20261004T104910385/gate.json`, PASS, source hashes match. Approved runner `4.8.dev.custom_build.a9c94cd21`, SHA-256 `06E7BE7ED0298E81BE421076A4A3166A7AE0E6B72C8A948D6FAEFD5823B3EE1A`.

| Gate | Focused | Rendered | Result |
| --- | ---: | ---: | --- |
| Wave 0 | Bootstrap, plugin and runner qualification | — | PASS |
| Wave 1 | 50 | 23 | PASS |
| Wave 2 | 84 | 127 | PASS |
| Wave 3 | 432 | 159 | PASS |
| Wave 4 | 970 | 1,726 | PASS |

Wave 4 rendered phases: A 1,156; B 374; C 157; D 6; M1 8; N1 8; M2 9; N2 8. All 26 screenshots exist. The full regression run used no skip options.

Focused coverage instantiates the streamed production world and exercises both a real generated Heartwood voxel and finite Dense Stone sources. It proves no-input rejection, quick tap and partial-release conservation, full completion exactly once, target reset/no transferred work, swapped tool instance, lost capability, menu capture, death, range, occlusion, changed block/source and actual chunk unloading. Continued hold begins a second target from zero and conserves exact outputs and wear.

Rendered coverage starts attempts through actual pressed input and the production player handler, releases through the release callback, and opens/closes the actual inventory shell. It checks unchanged resources, source state and overrides after cancellation, then continues the original crafting/tool/mining loop. Successive tree voxels are harvested while primary input remains held. Inventories, tools, survival and processing state are not injected; timing uses the production simulation seam with Standard survival and no acceleration. Camera positioning and controlled damage remain identified test setup.

Evidence is append-only under ignored `.verification/wave4/run-<timestamp>/`: reports, 26 screenshots, source manifest, logs and gate receipt. Failed earlier attempts remain retained: the first focused fixture exited during normal headless bootstrap, a second exposed a typed-array fixture error, and a third found the Wave 3 rendered driver's stale pre-harvest target capture. The fixture and target capture were corrected without removing assertions. Full certification requires all prior gates, real rendered runs and source-hash agreement; skip switches cannot certify.

Review/staging uses an explicit eleven-path allowlist, with only the application-version hunk from `project.godot`. Verification artifacts, saves, unrelated editor settings and vendor files are excluded. The published commit and upstream equality are recorded in the ignored publication receipt.

## Owner spot-check

Launch a separate fresh world without deleting existing development saves:

```powershell
& 'D:\AI\Projects\leyforge\.local\Godot_v4.8-dev-a9c94-shutdown-fixed\godot.windows.editor.x86_64.exe' --path 'D:\AI\Projects\Leyforge-Rebuild' -- --world-id=wave4-hold-gather-spotcheck --seed=184552221
```

1. Target a tree trunk. Tap LMB: the log stays, with no drop. Hold less than one second and release: it stays and progress resets.
2. Hold for the full duration: exactly one trunk voxel breaks and one Heartwood drop appears. Pick it up and continue the existing crafting progression.
3. Start another log, look away and return: a fresh full duration is required. Open I while harvesting: no gathering continues behind the menu.
4. Craft tools normally. Verify axes retain their faster timings; hold across consecutive voxels and confirm individual breaks.
5. Craft a Stone Pickaxe and target a Dense Stone outcrop. Tap/partial hold/release must leave its six-unit stock and tool durability unchanged. A full hold yields the ordinary Stone stock once with one tool use; opening I midway cancels it.

Owner spot-check remains a human action. No Wave 5 implementation is included.
