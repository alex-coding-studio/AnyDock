# AnyDock Agent Instructions

## Semina

projectId: d9b91b6c-e6aa-4169-9671-96386aa84d78

Use this ID directly over local or remote MCP, including in linked worktrees.

## Start of work

- For an overview, coordination or direct work, use `semina_read_project` and follow relevant pagination for project state, generated progress and modules. Read the affected modules and relevant decisions and pitfalls.
- For assigned work, use `semina_read_task`, then `semina_read_node` for the linked module and relevant decisions and pitfalls. Use the project view when a task has no module or needs broader context. Read related pending questions and leave them open until decided.
- Read the applicable [engineering rules](docs/ENGINEERING.md), [product and operations contracts](docs/PROJECT.md) and the active Delivery Contract when assigned. For UI work, read the [UI foundation](docs/ENGINEERING.md#ui-foundation-and-architecture) and the relevant Semina tray or settings decisions before editing.

## End of work

- Record authorized settled decisions with their reasons and verified reusable pitfalls under the affected module. Keep unresolved questions in pending cards and agreed work in Tasks. Read existing cards first, pass the current revision and reread and reconcile conflicts.
- Update the module's current state after verified delivery, normally after merge. The coordinator updates the project card when the project phase or release state changes.
- Only the task owner or its authorized Agent completes a delivered task. Include `knowledgeImpact` in the same call using `{cardIds: [...]}` for cards created or updated, or `{none: "one-line reason"}` when there is no knowledge impact. Include an updated linked module to avoid marking it `needsUpdate`; revising the module clears that flag. Keep tasks in progress during review, CI and merge. Read-only work carries no automatic write duty.

## Run and delivery

- Develop with Swift 6 and an SDK containing the macOS 26 glass APIs, targeting macOS 14 and later. Use the pinned toolchain inputs, committed hooks and versioned [commands](docs/ENGINEERING.md#commands). Run `./scripts/lint.sh`, `./scripts/test.sh` and `./scripts/build.sh` as applicable. Launch with `./scripts/run.sh` only on explicit request.
- Open a ready PR with the bot identity and start independent review. Require current-head approval and a passing GitHub Actions `Lint, test and build` job. Only [the auto-merge workflow](docs/PROJECT.md#merging-pull-requests) merges reviewed PRs.
- Keep signing, notarization and release packaging on the release Mac. Tagging, asset upload and publication need separate user authorization. Follow the [release procedure](docs/PROJECT.md#release) and its shared Sparkle reference.

## Project roles and workflows

- Track follow-up work in Semina Tasks. GitHub Issues are disabled and pull requests are limited to collaborators. For coordinator-assigned work, report milestones through the assigned channel with the current PR, head and gate state.
- Alex performs interactive UI acceptance. Open UI-bearing PRs with `needs-acceptance`; the architect removes it after Alex accepts. Workers use automated checks and source inspection for validation. Interactive tests, probes, Computer Use, app launch or replacement and device checks require an explicit request. Preserve UI Alex has accepted as adequate unless the task calls for changing it.
- For authorized local acceptance, build the exact PR worktree and follow [Operation](docs/PROJECT.md#operation). After merge, rebuild from the default branch for the return to the regular local build.
