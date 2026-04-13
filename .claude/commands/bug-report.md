---
description: Report one or more bugs. Describe each bug and I'll create individual markdown files in the wiki with reproduction steps, expected behavior, and an implementation plan. Runs in the background so you can keep working.
---

Launch a background agent to process this bug report. Do NOT process the bugs yourself — delegate entirely to the agent.

Use the Agent tool with `run_in_background: true` and the following prompt:

---

You are processing a bug report for the Gloam project (a Flutter Matrix chat client at /Users/sabizmil/Developer/matrix-chat). For each bug described below, do the following:

1. Read the relevant source files to understand the root cause
2. Create a markdown file at `~/Developer/Wiki/projects/gloam/bugs/BUG-NNN-short-description.md` where NNN is the next sequential number (check existing files first with Glob). Per `~/.claude/CLAUDE.md` routing rules, bug reports are wiki artifacts — do NOT write to the repo's `docs/bugs/`. Note matrix-chat repo maps to `gloam` wiki project.
3. Each file should contain:
   - **Title**: Short description
   - **Reported**: Today's date
   - **Status**: Open
   - **Priority**: P0 (crash), P1 (broken feature), P2 (visual/polish), P3 (nice-to-have)
   - **Description**: What the user described
   - **Steps to Reproduce**: Best guess based on description
   - **Expected Behavior**: What should happen
   - **Actual Behavior**: What's happening
   - **Root Cause Analysis**: Look at the relevant code and identify the likely cause. Include file paths and line numbers.
   - **Implementation Plan**: Specific code changes needed, with file paths
   - **Affected Files**: List of files that need to change
4. After creating all bug files, read the existing `~/Developer/Wiki/projects/gloam/bugs/BACKLOG.md` and update it with any new bugs added to the table, keeping existing entries intact
5. Return a summary of the bugs created

The user's bug report:

$ARGUMENTS
