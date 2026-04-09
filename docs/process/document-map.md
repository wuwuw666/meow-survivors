# Document Map

This file explains where to look for different kinds of project information in Meow Survivors.

## Start Here

If you are new to the repository, read in this order:

1. `README.md`
2. `AGENTS.md`
3. `design/concept/game-concept.md`
4. `design/gdd/systems-index.md`
5. `.Codex/docs/coding-standards.md`

## If You Need Gameplay Rules

Read:

- `design/gdd/*.md`
- `design/concept/game-concept.md`

Use this section for:

- combat rules
- wave rules
- XP and upgrade logic
- tower placement and system dependencies

## If You Need High-Level Vision

Read:

- `design/concept/game-concept.md`

Use this section for:

- genre definition
- player fantasy
- design pillars
- intended core loop

## If You Need Design Review History

Read:

- `design/reviews/*.md`

Use this section for:

- review outcomes
- design feedback snapshots
- historical design decisions

## If You Need Coding Rules

Read:

- `.Codex/docs/coding-standards.md`
- `AGENTS.md`

Use this section for:

- file placement rules
- GDScript naming conventions
- module boundaries
- refactoring expectations

## If You Need Collaboration Rules

Read:

- `AGENTS.md`
- `docs/process/COLLABORATIVE-DESIGN-PRINCIPLE.md`
- `CONTRIBUTING.md`

Use this section for:

- when to ask before editing
- how to propose multi-file changes
- commit and PR expectations

## If You Need Workflow Guidance

Read:

- `docs/process/WORKFLOW-GUIDE.md`
- `docs/process/document-reorganization-plan.md`

Use this section for:

- project workflow examples
- documentation cleanup history
- how the current document structure was chosen

## If You Need Architecture Context

Read:

- `docs/architecture/*.md`

Use this section for:

- refactor plans
- future ADRs
- system boundary notes

## If You Need Engine Reference

Read:

- `docs/reference/engine/godot/`

Use this section for:

- Godot version context
- Godot-specific best practices
- migration and deprecated API notes

## If You Need Examples Or Historical Reference

Read:

- `docs/reference/examples/`
- `docs/reference/archive/`

Use this section for:

- sample sessions
- template examples
- archived non-project engine references

## If You Need Production History

Read:

- `production/gate-checks/`
- `production/session-logs/`
- `production/session-state/`

Use this section for:

- previous gate reviews
- historical session notes
- temporary work state

Important:

- production logs may contain old paths
- treat them as historical snapshots, not current source of truth

## Directory Ownership Summary

- `design/` answers: what the game should be
- `docs/process/` answers: how we work
- `docs/architecture/` answers: why the implementation is shaped this way
- `docs/reference/` answers: what we consult
- `production/` answers: what happened during development

## Current Entrypoints

The main maintained entry documents are:

- `README.md`
- `AGENTS.md`
- `CLAUDE.md`
- `.Codex/docs/coding-standards.md`
- `docs/process/COLLABORATIVE-DESIGN-PRINCIPLE.md`
- `CONTRIBUTING.md`

If any of these disagree with the current repository structure, they should be updated first.
