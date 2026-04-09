# Meow Survivors

Meow Survivors is a cute survivor-defense prototype built with Godot 4.6 and GDScript.
The core loop combines auto-attacks, enemy waves, level-up choices, and tower placement.

## Project Snapshot

- Genre: Survivor + tower defense hybrid
- Engine: Godot 4.6
- Language: GDScript
- Platform target: PC
- Current stage: MVP prototype implementation
- Main scene: `res://scenes/game/main_game.tscn`

## Core Loop

```text
Move -> Auto attack -> Defeat enemies -> Gain XP -> Choose upgrades -> Place towers -> Survive stronger waves
```

## Design Pillars

1. Cute but combat-readable visuals
2. Frequent, satisfying sense of growth
3. Meaningful build and tower-placement decisions

## Project Structure

```text
src/                  # Runtime code
scenes/               # Godot scenes
assets/               # Game assets and data
design/gdd/           # System design documents
design/concept/       # Game concept and high-level design
design/reviews/       # Design review records
docs/process/         # Collaboration and workflow docs
docs/architecture/    # Refactor notes and architecture decisions
docs/reference/       # Engine docs, examples, archive
production/           # Gate checks, session logs, project records
.Codex/docs/          # Project rules and coding standards
```

## Key Documents

- [Game Concept](design/concept/game-concept.md)
- [Systems Index](design/gdd/systems-index.md)
- [Agent Guide](AGENTS.md)
- [Coding Standards](.Codex/docs/coding-standards.md)
- [Collaboration Principle](docs/process/COLLABORATIVE-DESIGN-PRINCIPLE.md)
- [Document Reorganization Plan](docs/process/document-reorganization-plan.md)

## Current Implementation Notes

- `src/game/main_game.gd` is still the main orchestration script.
- The project is actively being split into managers and reusable components.
- New work should prefer `src/game/`, `src/core/`, and `src/gameplay/` over growing `main_game.gd`.

## Getting Started

1. Install [Godot 4.6](https://godotengine.org/download).
2. Open the project from this repository root.
3. Run the main scene at `scenes/game/main_game.tscn`.
4. Read the design and rules docs before changing gameplay behavior.

## Development Rules

- Gameplay behavior should follow the docs in `design/`.
- Project-level collaboration and coding rules live in `AGENTS.md` and `.Codex/docs/`.
- If design docs and implementation disagree, document the mismatch before changing behavior.

## License

MIT. See [LICENSE](LICENSE).
