# Meow Survivors Project Context

This file is the high-level project context entrypoint for Claude Code style workflows.
It should stay aligned with `AGENTS.md`, but remain concise and operational.

## Project Identity

- Project: Meow Survivors
- Genre: Survivor + tower defense hybrid
- Engine: Godot 4.6
- Language: GDScript
- Main Scene: `res://scenes/game/main_game.tscn`
- Current Stage: MVP prototype implementation

## Primary Sources

When working in this repository, use these sources in order:

1. `design/gdd/*.md` for system rules
2. `design/concept/game-concept.md` for game vision
3. `docs/architecture/*.md` for technical direction
4. `AGENTS.md` and `.Codex/docs/*.md` for collaboration and coding rules
5. `CONTRIBUTING.md` for branch, commit, and PR expectations

If design and implementation disagree, do not silently pick one.
Call out the mismatch and decide whether to update docs or code.

## Documentation Map

- Agent and collaboration entrypoint: `AGENTS.md`
- Coding standards: `.Codex/docs/coding-standards.md`
- Collaboration principle: `docs/process/COLLABORATIVE-DESIGN-PRINCIPLE.md`
- Workflow guide: `docs/process/WORKFLOW-GUIDE.md`
- Document map: `docs/process/document-map.md`
- Reorganization plan: `docs/process/document-reorganization-plan.md`
- Refactor notes: `docs/architecture/refactor-checklist.md`
- Engine reference: `docs/reference/engine/godot/`

## Project Structure

### Runtime

- `src/core/`: reusable components and low-level systems
- `src/data/`: data access and global state scripts
- `src/game/`: orchestration and manager layer
- `src/gameplay/`: gameplay entities and combat behavior
- `src/ui/`: UI logic
- `scenes/`: Godot scenes
- `assets/`: assets and data files

### Project Docs

- `design/gdd/`: system design docs
- `design/concept/`: concept and high-level design
- `design/reviews/`: design review outputs
- `docs/process/`: workflow and collaboration docs
- `docs/architecture/`: technical direction and refactor notes
- `docs/reference/`: engine docs, examples, archive
- `production/`: gate checks, logs, state snapshots

## Current Technical Reality

- `src/game/main_game.gd` is still the main orchestration script.
- The project is already moving toward manager/component separation.
- New logic should prefer `src/game/`, `src/core/`, and `src/gameplay/` rather than expanding `main_game.gd`.
- Data-driven behavior is preferred, but prototype exceptions may exist temporarily.

## Collaboration Rules

- Ask before writing files when the user has not already approved edits.
- Show scope before multi-file changes.
- Do not commit or create PRs without explicit instruction.
- Treat document cleanup, path moves, and refactors as user-facing changes that require clarity before execution.

## Tooling Context

- `.Codex/docs/` contains the project-owned rules that should guide current work.
- `.claude/` contains inherited template assets and compatibility references.
- `.agents/` contains project-available skills used by the current Codex environment.

If `.claude/` and `.agents/` overlap, prefer the project’s current documented structure and rules rather than assuming the original template is authoritative.
