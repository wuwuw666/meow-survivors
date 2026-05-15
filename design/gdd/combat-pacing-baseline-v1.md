# Combat Pacing Baseline v1

> **Status**: Draft
> **Author**: user + Codex
> **Created**: 2026-05-14
> **Last Updated**: 2026-05-14
> **Related Docs**:
> - `design/gdd/wave-system.md`
> - `design/gdd/difficulty-curve-system.md`
> - `design/gdd/enemy-spawn-system.md`
> - `design/gdd/tower-system.md`
> - `design/gdd/tower-mod-system.md`

---

## Overview

This document defines the first pacing baseline for Meow Survivors. Its purpose is to keep enemy movement speed, spawn cadence, tower response speed, and non-pausing tower equipment rewards tuned around the same player experience target.

The current design direction is:

- Combat should not pause for routine build decisions.
- In-run build depth should come from tower equipment or skills attached to specific towers.
- Long-term build should come from tower selection, unlocks, and tower pool shaping outside the run.
- Players must have enough time to read pressure, choose a response, and safely equip rewards without the game becoming frantic noise.

This document does not replace the wave or difficulty systems. It is the tuning baseline those systems should consume.

---

## Core Pacing Principle

The game should feel pressured, not rushed.

Pressure means the player sees a threat, understands why it matters, and has a short window to respond. Rushed means enemies cross the map before towers and player decisions visibly matter.

For MVP, the target is:

```text
Enemy wave pressure gives the player problems.
Tower placement and tower equipment give the player readable answers.
Wave pacing gives the player short natural windows to execute those answers.
```

---

## Current Map Reference

The current main map path in `scenes/game/main_game.tscn` is approximately:

```text
main path length ~= 2550 px
```

This value is used only as a tuning reference. If the path changes, all travel-time targets should be recalculated from path length.

Formula:

```text
travel_time_sec = path_length_px / enemy_speed_px_per_sec
```

Example using the current path length:

| Enemy Speed | Travel Time |
|---:|---:|
| 95 px/s | 26.8s |
| 80 px/s | 31.9s |
| 70 px/s | 36.4s |
| 55 px/s | 46.4s |
| 40 px/s | 63.8s |

Design note: If enemies feel too fast even when travel time looks reasonable, the likely cause is spawn density, enemy clustering, tower wind-up, or too few low-pressure windows rather than raw movement speed alone.

---

## Enemy Movement Baseline

### Target Travel Times

| Run Phase | Waves | Target Travel Time | Player Experience |
|---|---:|---:|---|
| Learn | 1-2 | 28-38s | Can observe route and place first towers |
| Pressure | 3-5 | 24-34s | Must react, but can still recover |
| Build Check | 6-8 | 20-30s | Must use tower layout and control tools |
| Climax | 9-10 | 16-26s | Build must be working, mistakes matter |

### Enemy Role Speed Ranges

These are first-pass safe ranges for the current map scale.

| Enemy Role | Speed Range | Design Purpose |
|---|---:|---|
| Basic | 58-72 px/s | Default readable pressure |
| Runner | 74-88 px/s | Fast problem unit, not default baseline |
| Tank | 38-50 px/s | Slow pressure sponge |
| Elite | 48-62 px/s | Reward-bearing threat with readable presence |
| Boss | 28-40 px/s | Climax anchor, should not rush past tower setup |

Current data note:

- `normal_a` currently uses speed `94`, which is above the recommended runner range and likely contributes to the "too fast" feel.
- `normal_b`, `normal_c`, `elite`, and `boss` are closer to the proposed bands.
- The first tuning pass should reduce runner speed before reducing all enemies.

---

## Spawn Cadence Baseline

### Problem With Constant Spawn Pressure

If enemies spawn at a constant interval for the whole wave, the player receives no natural breathing window. That becomes especially harmful after the game adopts non-pausing tower equipment.

The wave should be built from pulses:

```text
pulse A
short gap
pulse B
short gap
special pressure or elite
short low-pressure reward window
cleanup
```

### Pulse Structure

| Wave Phase | Pulse Count | Gap Between Pulses | Notes |
|---|---:|---:|---|
| Waves 1-2 | 2 | 2.5-4.0s | Clear tutorial readability |
| Waves 3-5 | 2-3 | 2.0-3.0s | Introduce runner or tank pressure |
| Waves 6-8 | 3 | 1.5-2.5s | Layout and control check |
| Waves 9-10 | 3-4 | 1.0-2.0s | High pressure, still readable |

### Spawn Interval Ranges

| Wave Phase | Normal Spawn Interval | Burst Spawn Interval | Notes |
|---|---:|---:|---|
| Waves 1-2 | 1.6-2.2s | Avoid burst | Let the player read enemies |
| Waves 3-5 | 1.2-1.8s | 0.8-1.1s | Short burst only inside a pulse |
| Waves 6-8 | 0.9-1.4s | 0.65-0.9s | Use with enemy caps |
| Waves 9-10 | 0.7-1.2s | 0.5-0.8s | Boss wave may mix minions |

Rule: A low interval should be compensated with slower movement, lower enemy count, or a pulse gap. Do not lower spawn interval and raise movement speed at the same time unless testing a deliberate spike.

---

## Tower Response Baseline

Tower usefulness should be tuned by expected hit opportunities, not only DPS.

Formula:

```text
effective_time_in_range = covered_path_length / enemy_speed
expected_hits = effective_time_in_range / attack_interval
```

For MVP, expected hits against a basic enemy should be:

| Tower Type | Expected Hits Against Basic Enemy | Design Meaning |
|---|---:|---|
| Fish | 3-5 hits | Reliable damage tower |
| Yarn | 2-4 hits | Applies control early enough to matter |
| Catnip | Passive | Must clearly amplify nearby towers |
| High-damage tower | 1-3 hits | Slow but noticeable impact |

### Tower Feel Targets

| Tower | Primary Feel | Tuning Priority |
|---|---|---|
| Fish | "This is my main damage line." | Keep attack interval and range high enough for repeated hits |
| Yarn | "This buys me time." | Slow effect should extend enemy time in danger zones by 15-30% |
| Catnip | "This area became stronger because I planned it." | Aura value must be visible through nearby tower performance |

### Practical First Pass

Before adding more tower types:

1. Confirm basic enemies receive at least 3 Fish tower shots while crossing a useful tower coverage segment.
2. Confirm Yarn slow visibly changes whether a runner leaks.
3. Confirm Catnip placed near 2 towers is better than another raw damage tower in at least some situations.

---

## Non-Pausing Equipment Windows

Because tower equipment no longer pauses combat, waves must intentionally create natural action windows.

### Reward Flow

```text
Elite or milestone reward triggers
-> equipment supply enters queue
-> combat continues
-> player opens supply when safe
-> player chooses equipment while combat continues
-> compatible towers highlight
-> player clicks a tower to attach equipment
```

### Low-Pressure Window Rules

After an elite death or milestone reward:

- Do not spawn a new high-speed pulse for `3.0-5.0s`.
- Do not spawn another elite during this window.
- Allow existing enemies to continue moving.
- Keep the wave alive, but lower the pressure enough that the player can interact.

This is not a pause. It is a pacing valley.

### Equipment Queue Limits

| Parameter | MVP Value | Reason |
|---|---:|---|
| Max queued supplies | 2 | Prevent UI backlog and decision overload |
| Offer count | 3 | Keeps build choice meaningful |
| Attach time limit | None for MVP | Pressure comes from enemies, not an artificial timer |
| Replacement | Not allowed | One equipment slot per tower keeps choices legible |

---

## Wave Pacing Baseline

### Wave 1

Purpose: Teach path, tower placement, and basic enemy readability.

- Mostly Basic enemies.
- No elite.
- No runner-heavy pulse.
- Player should have time to place at least one tower and observe it working.

### Wave 2

Purpose: Confirm first layout and resource loop.

- Basic enemies plus small runner preview if needed.
- Still avoid hard pressure.
- The player should feel towers are useful.

### Wave 3

Purpose: First real pressure change.

- Introduce Runner as a small pulse.
- Reward players who placed coverage near early path segments.
- Do not combine high runner speed with high spawn density.

### Waves 4-5

Purpose: Start build direction.

- First elite can appear here.
- Elite death creates the first equipment supply.
- Follow elite death with a low-pressure window.

### Waves 6-8

Purpose: Validate tower equipment and lane coverage.

- Mix Basic, Runner, and Tank.
- Let Yarn or control equipment solve visible problems.
- Pressure should come from composition, not only more bodies.

### Wave 9

Purpose: Pre-boss stress test.

- Strong mixed pulses.
- Shorter gaps, but still enough for cleanup.
- Player should understand whether their build is ready.

### Wave 10

Purpose: Climax.

- Boss should be supported by minions.
- Avoid making the boss a lone HP bag.
- Boss speed should be slow enough that tower layout matters.
- The player should see their equipped towers contribute clearly.

---

## Tuning Knobs

| Knob | Source | Safe Range | Primary Effect |
|---|---|---:|---|
| Enemy speed by role | `assets/data/enemy_data.json` | See role table | Readability and reaction time |
| Spawn interval | `WaveManager` or future wave config | 0.5-2.2s | Density and urgency |
| Pulse gap duration | Future wave config | 1.0-5.0s | Breathing room |
| Spawn budget | `WaveManager` or future wave config | Wave-specific | Total pressure |
| Enemy mix | `WaveManager` or future wave config | Wave-specific | Type of pressure |
| Tower range | `src/data/tower_data.gd` | Tower-specific | Hit opportunities |
| Tower attack interval | `src/data/tower_data.gd` | Tower-specific | Response speed |
| Slow strength | Tower behavior config | 10-35% slow | Control value |
| Equipment low-pressure window | Future tower equipment flow | 3.0-5.0s | Non-pausing usability |

---

## First Tuning Pass Recommendation

Make changes in this order when implementation begins:

1. Reduce only `normal_a` runner speed from `94` into the `80-86` range.
2. Convert continuous wave spawning into 2-3 pulses per wave.
3. Add a `3.0-5.0s` pressure valley after elite reward creation.
4. Verify Fish expected hits against Basic enemies before changing Fish damage.
5. Verify Yarn slow prevents at least some runner leaks before raising Yarn damage.
6. Keep Catnip as a layout amplifier, not an emergency fix.

Do not tune everything at once. The first playtest should isolate whether the bad feel comes more from movement speed or from uninterrupted spawn density.

---

## Acceptance Criteria

### Feel Criteria

| ID | Criteria |
|---|---|
| AC-PACE-01 | In waves 1-2, the player can visually track enemies from spawn to first tower contact. |
| AC-PACE-02 | A basic enemy is hit by a Fish tower at least 3 times when crossing a normal coverage area. |
| AC-PACE-03 | Runner enemies feel like special pressure, not the default pace of the whole game. |
| AC-PACE-04 | After an elite reward, the player can open or attach equipment without a hard pause. |
| AC-PACE-05 | Wave 10 feels like a boss-supported climax rather than a lone slow target or an unreadable rush. |

### Numeric Criteria

| ID | Criteria |
|---|---|
| AC-NUM-01 | Current map travel time for Basic enemies should usually stay above 28s before wave 6. |
| AC-NUM-02 | Runner travel time should usually stay above 22s before wave 6. |
| AC-NUM-03 | Pulse gaps should not be shorter than 1.5s before wave 8. |
| AC-NUM-04 | Elite reward windows should provide 3.0-5.0s before the next high-pressure pulse. |
| AC-NUM-05 | Same-wave tuning should not simultaneously increase enemy speed, spawn budget, and lower spawn interval. |

### Playtest Questions

After each tuning pass, answer these questions:

1. Did the player understand why pressure increased?
2. Did towers visibly affect the outcome before enemies reached the base?
3. Did non-pausing equipment feel tense but usable?
4. Did failure feel like a build or placement problem, not pure speed overload?
5. Did the player want to try a different tower equipment choice next run?

---

## Open Questions

1. Should equipment supplies be opened from a screen-edge queue button, a keyboard shortcut, or both?
2. Should opening a supply show the 3 choices near the queue or near the selected tower?
3. Should wave config move out of `WaveManager` into a data file before the pacing pass?
4. Should the first elite always appear at a fixed wave for MVP testing?
5. Should runner speed scale by wave, or should runner pressure come only from count and spawn timing?
