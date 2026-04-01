# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.6 (local: F:\godot)
- **Language**: GDScript (primary), C++ via GDExtension (performance-critical)
- **Rendering**: 2D with canvas-based rendering
- **Physics**: Godot built-in 2D physics (GodotPhysics, Jolt available)

## Naming Conventions (GDScript)

- **Classes**: PascalCase (e.g., `PlayerController`)
- **Variables/Functions**: snake_case (e.g., `move_speed`, `take_damage()`)
- **Signals**: snake_case past tense (e.g., `health_changed`, `enemy_killed`)
- **Files**: snake_case matching class (e.g., `player_controller.gd`)
- **Scenes**: PascalCase matching root node (e.g., `PlayerController.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_HEALTH`, `FIRE_RATE`)

## Performance Budgets

- **Target Framerate**: 60 FPS
- **Frame Budget**: 16.6ms per frame
- **Draw Calls**: Target < 100 per frame
- **Memory Ceiling**: Target < 512MB RAM usage
- **Max Enemies On-Screen**: 50-100 for MVP, optimize for more

## Testing

- **Framework**: GUT (Godot Unit Tester)
- **Minimum Coverage**: Core mechanics (combat, tower placement, wave system)
- **Required Tests**: Upgrade system calculations, enemy spawn logic, collision detection

## Forbidden Patterns

- Hardcoding gameplay values (use exported variables or config files)
- Using `print()` in production code (use proper logging)
- Accessing nodes by path string (use `$Path` or `get_node()` with groups)

## Allowed Libraries / Addons

- [To be determined as project progresses]

## Architecture Decisions Log

- [No ADRs yet — use /architecture-decision to create one]
