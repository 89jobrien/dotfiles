<!-- godmode-workflow:begin -->

# Phased workflow

Unless the user clearly opts out (e.g. **"skip plan, just fix it"**), every
non-trivial task progresses through five phases. Short confirmations like
**"do it"**, **"act"**, **"go"** advance to the next phase.

## Phases

<godmode-phase name="ORIENT" mode="read-only" response-header="# Phase: ORIENT" skills="godmode handon">
Default phase. Read files, search code, run `godmode handon`, check task
graph. Summarize current state: branch, dirty files, relevant context.
No modifications to the repository. End by stating what you found and
what phase comes next.
</godmode-phase>

<godmode-phase name="PLAN" mode="read-only" response-header="# Phase: PLAN" skills="brainstorm, writing-plans">
Produce a written plan: files to touch, approach, risks. Still read-only
— no edits, no builds that write output. For complex work, invoke
`godmode:brainstorm` or `godmode:writing-plans`. End with "Type ACT to
proceed" (or suggest refinements).
</godmode-phase>

<godmode-phase name="ACT" mode="read-write" response-header="# Phase: ACT" skills="task-driven-development, parallel-agents">
Enter when the user approves: "act", "go ahead", "do it". Edit files,
run commands, dispatch subagents. For multi-task work, use
`godmode:task-management` and `godmode:parallel-agents` when tasks are
independent. After finishing, transition to VERIFY automatically.
</godmode-phase>

<godmode-phase name="VERIFY" mode="read + test" response-header="# Phase: VERIFY" skills="verification-before-completion">
Run `cargo check`, `cargo clippy`, `cargo test` (or `godmode verify`).
Invoke `godmode:verification-before-completion` for non-trivial changes.
Report results. If failures exist, return to ACT to fix them. When
green, state readiness and ask to SHIP.
</godmode-phase>

<godmode-phase name="SHIP" mode="commit/push" response-header="# Phase: SHIP" skills="cap, handoff">
Commit, push, update handoff: `godmode:cap`, then `godmode handoff`.
Only entered with explicit user approval. After shipping, return to
ORIENT for the next task.
</godmode-phase>

## Phase transitions

- **User can skip phases**: "skip plan, implement now" jumps to ACT.
  "just fix it" implies ORIENT → ACT → VERIFY → SHIP in one pass.
- **After each ACT turn**, default back to VERIFY unless the user says
  otherwise.
- **Multiple ACT turns** are fine — the user can keep approving.
- When the user gives a lettered choice or short confirmation, advance
  to the most obvious next phase without asking.

## Skill invocation rule

Before responding in any phase, check if a godmode skill applies.
1% chance it’s relevant = invoke it. Process skills (`brainstorm`,
`systematic-debugging`) before implementation skills
(`task-driven-development`, `parallel-agents`).

## Task graph

Tasks live in @.ctx/GODMODE.tasks.yaml. Use `Bash(godmode task)` CLI for
state transitions. Independent chains can run in parallel via
`Skill(godmode:parallel-agents)`. A task is runnable when all `depends_on`
items are `done`.

## Memory bank

- Persistent context lives in @.ctx/memory-bank/
- Read before substantive work: !`ls .ctx/memory-bank/`
- update after milestones: @.ctx/memory-bank/activeContext.mbx.md and @.ctx/memory-bank/progress.mbx.md.
- See @AGENTS.md for the full file list.

## Agent-specific guidance

For subagent conventions, Codex integration, and memory-bank file
inventory, see @AGENTS.md.

<!-- godmode-workflow:end -->
