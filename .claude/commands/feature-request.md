---
description: Request a new feature. I'll analyze 5 implementation approaches, recommend the best one, and create a detailed plan. Runs in the background so you can keep working.
---

Launch a background agent to process this feature request. Do NOT process the feature yourself — delegate entirely to the agent.

Use the Agent tool with `run_in_background: true` and the following prompt:

---

You are processing a feature request for the Gloam project (a Flutter Matrix chat client at /Users/sabizmil/Developer/matrix-chat). The tech stack is Flutter + matrix_dart_sdk + Riverpod + drift, targeting iOS, Android, macOS, Windows, Linux. The design system uses a green-on-black aesthetic with Spectral/Inter/JetBrains Mono typography.

For each feature described below:

1. Check existing files with Glob to determine the next FEAT number
2. Read relevant source files to understand the current architecture
3. Read the competitive analysis at COMPETITIVE_ANALYSIS.md and design system at docs/plan/09-design-system.md for context
4. Create a markdown file in `docs/features/` named `FEAT-NNN-short-description.md` with:
   - **Title**: Short description
   - **Requested**: Today's date
   - **Status**: Proposed
   - **Description**: What the user wants, expanded with UX context
   - **User Story**: "As a [user], I want [feature] so that [benefit]"
   - **5 Implementation Approaches**: For each:
     - Name and one-line summary
     - Technical approach (how it works)
     - Pros and Cons
     - Effort estimate
     - Dependencies
   - **Recommendation**: Which approach and why, considering the existing codebase, design system, cross-platform needs, and UX emphasis
   - **Implementation Plan**: Step-by-step for the recommended approach:
     - Files to create or modify (with paths)
     - New dependencies needed
     - State management approach
     - UI components to build
     - Edge cases
   - **Acceptance Criteria**: Checkboxes
   - **Related**: Links to related bugs, features, or plan docs
5. Read existing `docs/features/ROADMAP.md` and update it with any new features, keeping existing entries
6. Return a summary of the features created with the recommendation for each

The user's feature request:

$ARGUMENTS
