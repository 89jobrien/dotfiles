---
name: session-to-skill
description: Use at end of a session (or on demand) to extract repeated tool patterns into a reusable skill. Triggers on "extract this as a skill", "save this as a skill", "I keep doing this", or when you notice the same command sequence run 2+ times.
---

# Session to Skill

## When to Use

- User says "save this as a skill" or "I keep doing this"
- You notice the same Bash command or tool sequence run 2+ more times in the session
- End of a session where significant workflows were executed

## Step 1: Identify Candidate Patterns

Review the conversation history mentally for:
- Bash commands run more than once with the same structure
- Multi-step sequences (Read → Bash → Edit) done more than once
- Commands the user had to correct or clarify (indicating a skill would have helped)
- Commands with complex flags that are hard to remember

## Step 2: Classify Each Pattern

For each candidate, determine:
- **Trigger**: When would someone need this? What symptom or goal?
- **Scope**: Is this project-specific (goes in `~/.claude/skills/PROJECT/`) or global (goes in `~/.claude/skills/`)?
- **Type**: One-shot command, multi-step workflow, or reference table?

## Step 3: Draft the Skill

Use this template to draft the skill content. Present it to the user for review before writing:

```markdown
---
name: {kebab-case-name}
description: Use when {trigger condition}. Symptoms - {what the user sees that means they need this}.
---

# {Title}

## When to Use
{1-2 sentences}

## Commands

{The exact commands, copy-paste ready, with comments explaining flags}

## Common Failures

| Symptom | Fix |
|---------|-----|
| ... | ... |
```

## Step 4: Determine Destination

Skill placement rules:
- Global utility → `~/.claude/skills/{name}/SKILL.md`
- Project-specific → `~/.claude/skills/{project-prefix}/{name}/SKILL.md` (e.g., `mbx/`, `maestro/`)
- Personal workflow → `~/.claude/skills/joe/{name}/SKILL.md`

## Step 5: Write and Register

After user confirms the draft:
1. Write the SKILL.md file to the determined path
2. Check if the skill needs to be registered in any plugin manifest (look in `~/.claude/plugins/` for any skills.json or manifest files)
3. Confirm to the user: "Skill saved to {path}. Invoke it with: Skill tool, name: {name}"

## Examples of Good Skills to Extract

From common session patterns:
- `devloop-analyze` — the `env -u ... op run ... devloop analyze` incantation
- `jobrien-vm-ssh` — the exact sshpass command for the VM
- `baml-regen` — the version-align + regenerate workflow
- `pieces-health` — curl check + PiecesOS restart if down

## What NOT to Extract

- One-off commands specific to a single task
- Commands that will change frequently (use a justfile recipe instead)
- Simple git commands (already in muscle memory)
- Anything already covered by an existing skill (check `~/.claude/skills/` first)
