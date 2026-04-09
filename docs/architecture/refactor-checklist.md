# Refactor Checklist

## P0

- [x] Unify damage application through `HealthComponent.apply_damage(...)`.
- [x] Extract combat feedback from `main_game.gd` into a dedicated manager.
- [ ] Add a small debug overlay for player HP, last damage event, and current wave state.

## P1

- [x] Split tower placement/building logic into `tower_manager.gd`.
- [ ] Move tower definitions out of `main_game.gd` into structured data/resources.
- [x] Move enemy spawn orchestration out of `main_game.gd` into a spawn manager.
- [ ] Normalize scene/component initialization order so runtime-added nodes do not depend on `_ready()` timing.

## P2

- [~] Replace ad-hoc game flow flags with a clear state machine for `ready`, `combat`, `upgrade`, and `game_over`.
  Progress: ready phase, upgrade selection, and game-over pause now use pause reasons instead of direct `Game.is_paused` writes.
- [ ] Convert more runtime-built nodes into pre-authored scenes where it improves readability/debugging.
- [ ] Add lightweight automated gameplay smoke tests for spawn, damage, and wave transitions.

## Risks To Watch

- Damage display drifting away from actual HP changes when a new attack source bypasses `HealthComponent`.
- New map/path content breaking enemy spawn because path validation is too close to the main scene.
- UI and pause-state regressions when upgrade, ready-state, and game-over flows overlap.
- Encoding/locale issues causing accidental corruption in large mixed-language script files.
