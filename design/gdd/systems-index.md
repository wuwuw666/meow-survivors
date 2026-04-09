# Systems Index: 喵族幸存者 (Meow Survivors)

> **Status**: Draft
> **Created**: 2026-04-01
> **Last Updated**: 2026-04-03
> **Source Concept**: design/concept/game-concept.md

---

## Overview

喵族幸存者是一款幸存者类 + 塔防混合游戏，核心循环是：移动定位 → 自动攻击 → 敌人波次 → 升级选择 → 塔位放置。系统设计聚焦于可爱画风下的策略成长体验，共识别 22 个系统，其中 20 个为 MVP 必需。

设计支柱约束：
- **可爱即正义**: 所有视觉反馈系统必须符合可爱美学
- **成长的爽感**: 升级/数值系统必须让玩家感受到明显变强
- **策略有深度**: Build 和塔位决策必须有意义的权衡

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | 输入系统 | Core | MVP | Approved | design/gdd/input-system.md | — |
| 2 | 碰撞检测系统 | Core | MVP | Approved | design/gdd/collision-detection-system.md | — |
| 3 | 伤害计算系统 | Gameplay | MVP | Approved | design/gdd/damage-calculation-system.md | — |
| 4 | 难度曲线系统 | Meta | MVP | Approved | design/gdd/difficulty-curve-system.md | — |
| 5 | 升级池系统 | Progression | MVP | Approved | design/gdd/upgrade-pool-system.md | — |
| 6 | 地图系统 | Meta | MVP | Approved | design/gdd/map-system.md | — |
| 7 | 移动系统 | Core | MVP | Approved | design/gdd/movement-system.md | 输入系统, 地图系统 |
| 8 | 生命值系统 | Core | MVP | Approved | design/gdd/health-system.md | 碰撞检测系统 |
| 9 | 目标选择系统 | Core | MVP | Approved | design/gdd/target-selection-system.md | 碰撞检测系统 |
| 10 | 经验系统 | Progression | MVP | Designed | design/gdd/xp-system.md | 碰撞检测系统 |
| 11 | 金币系统 | Economy | MVP | Designed | design/gdd/coin-system.md | 碰撞检测系统 |
| 12 | 自动攻击系统 | Gameplay | MVP | Designed | design/gdd/auto-attack-system.md | 目标选择, 生命值, 伤害计算 |
| 13 | 敌人系统 | Gameplay | MVP | Designed | design/gdd/enemy-system.md | 生命值, 伤害计算, 移动系统 |
| 14 | 防御塔系统 | Gameplay | MVP | Designed | design/gdd/tower-system.md | 目标选择, 伤害计算, 生命值 |
| 15 | 敌人生成系统 | Gameplay | MVP | Designed | design/gdd/enemy-spawn-system.md | 敌人系统, 波次系统 |
| 16 | 波次系统 | Gameplay | MVP | Designed | design/gdd/wave-system.md | 敌人生成, 难度曲线 |
| 17 | 升级选择系统 | Progression | MVP | Designed | design/gdd/upgrade-selection-system.md | 经验系统, 升级池系统 |
| 18 | 塔位放置系统 | Gameplay | MVP | Designed | design/gdd/tower-placement-system.md | 地图系统, 防御塔系统, 金币系统 |
| 19 | UI系统 | UI | MVP | Designed | design/gdd/ui-system.md | 生命值, 经验, 金币, 波次 |
| 20 | 结算系统 | UI | MVP | Designed | design/gdd/settlement-system.md | 波次, 金币, 经验 |
| 21 | 存档系统 | Persistence | v1.0 | Not Started | — | — |
| 22 | 解锁系统 | Progression | v1.0 | Not Started | — | 存档系统, 金币系统 |

---

## Categories

| Category | Description | Systems in this project |
|----------|-------------|-------------------------|
| **Core** | Foundation systems everything depends on | 输入系统、碰撞检测系统、移动系统、生命值系统、目标选择系统 |
| **Gameplay** | The systems that make the game fun | 伤害计算系统、自动攻击系统、敌人系统、防御塔系统、敌人生成系统、波次系统、塔位放置系统 |
| **Progression** | How the player grows over time | 经验系统、升级池系统、升级选择系统、解锁系统 |
| **Economy** | Resource creation and consumption | 金币系统 |
| **Persistence** | Save state and continuity | 存档系统 |
| **UI** | Player-facing information displays | UI系统、结算系统 |
| **Meta** | Systems outside the core game loop | 难度曲线系统、地图系统 |

---

## Priority Tiers

| Tier | Definition | Target Milestone | Design Urgency |
|------|------------|------------------|----------------|
| **MVP** | Required for the core loop to function. Without these, you can't test "is this fun?" | First playable prototype | Design FIRST |
| **v1.0** | Required for full release experience. Meta progression, unlocks, polish. | v1.0 release | Design after MVP complete |

---

## Dependency Map

### Foundation Layer (no dependencies)

1. **输入系统** — 接收原始输入，所有交互的基础
2. **碰撞检测系统** — 提供碰撞查询API，攻击/拾取/被击的基础
3. **伤害计算系统** — 纯公式计算，无状态依赖
4. **难度曲线系统** — 纯数值配置数据
5. **升级池系统** — 升级定义数据库
6. **地图系统** — 地图数据定义，塔位坐标
7. **存档系统** — 持久化API（v1.0）

### Core Layer (depends on foundation)

1. **移动系统** — depends on: 输入系统（驱动移动）
2. **生命值系统** — depends on: 碰撞检测系统（检测被击）
3. **目标选择系统** — depends on: 碰撞检测系统（查询范围内敌人）
4. **经验系统** — depends on: 碰撞检测系统（拾取经验球）或击杀事件
5. **金币系统** — depends on: 碰撞检测系统（拾取金币）或击杀事件

### Feature Layer (depends on core)

1. **自动攻击系统** — depends on: 目标选择, 生命值, 伤害计算
2. **敌人系统** — depends on: 生命值, 伤害计算, 移动系统（enemy move）
3. **防御塔系统** — depends on: 目标选择, 伤害计算, 生命值
4. **敌人生成系统** — depends on: 敌人系统, 波次系统（触发）
5. **波次系统** — depends on: 敌人生成, 难度曲线
6. **升级选择系统** — depends on: 经验系统, 升级池系统
7. **塔位放置系统** — depends on: 地图系统, 防御塔系统, 金币系统
8. **解锁系统** — depends on: 存档系统, 金币系统（v1.0）

### Presentation Layer (depends on features)

1. **UI系统** — depends on: 生命值, 经验, 金币, 波次（显示数据）
2. **结算系统** — depends on: 波次, 金币, 经验（统计展示）

---

## Recommended Design Order

| Order | System | Priority | Layer | Agent(s) | Est. Effort |
|-------|--------|----------|-------|----------|-------------|
| 1 | 输入系统 | MVP | Foundation | game-designer, gameplay-programmer | S |
| 2 | 碰撞检测系统 | MVP | Foundation | game-designer, engine-programmer | M |
| 3 | 伤害计算系统 | MVP | Foundation | systems-designer | S |
| 4 | 难度曲线系统 | MVP | Foundation | systems-designer | S |
| 5 | 升级池系统 | MVP | Foundation | game-designer | S |
| 6 | 地图系统 | MVP | Foundation | level-designer | S |
| 7 | 移动系统 | MVP | Core | game-designer, ux-designer | S |
| 8 | 生命值系统 | MVP | Core | game-designer | S |
| 9 | 目标选择系统 | MVP | Core | game-designer, ai-programmer | S |
| 10 | 经验系统 | MVP | Core | game-designer | S |
| 11 | 金币系统 | MVP | Core | economy-designer | S |
| 12 | 自动攻击系统 | MVP | Feature | game-designer, gameplay-programmer | M |
| 13 | 敌人系统 | MVP | Feature | game-designer, ai-programmer | M |
| 14 | 防御塔系统 | MVP | Feature | game-designer, gameplay-programmer | M |
| 15 | 敌人生成系统 | MVP | Feature | game-designer | S |
| 16 | 波次系统 | MVP | Feature | game-designer, systems-designer | M |
| 17 | 升级选择系统 | MVP | Feature | game-designer, ux-designer | M |
| 18 | 塔位放置系统 | MVP | Feature | game-designer, level-designer | S |
| 19 | UI系统 | MVP | Presentation | ux-designer, ui-programmer | M |
| 20 | 结算系统 | MVP | Presentation | ux-designer | S |
| 21 | 存档系统 | v1.0 | Foundation | engine-programmer | S |
| 22 | 解锁系统 | v1.0 | Feature | game-designer, economy-designer | M |

---

## Circular Dependencies

- **None found** — 依赖图为单向 DAG，无循环。

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| 碰撞检测系统 | Technical | 6个系统依赖，性能敏感（大量敌人同屏） | 早期原型验证性能预算 |
| 波次系统 | Design | 核心循环驱动者，难度曲线设计不确定 | 原型验证"波次节奏"是否有趣 |
| 升级选择系统 | Design | Build多样性 vs 决策疲劳，平衡困难 | 原型测试玩家反馈 |
| 目标选择系统 | Technical | "最近敌人"算法在高密度敌人场景下的性能 | 与碰撞检测一起原型验证 |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 22 |
| Design docs completed | 21/22 |
| Design docs still missing | — (all MVP docs written; v1.0 save/unlock pending) |
| Design docs reviewed | 10 |
| Design docs approved | 10 |
| MVP systems designed | 15/20 |
| v1.0 systems designed | 0/2 |

---

## Next Steps

- [x] MVP 全部 20 个系统 GDD 设计完成
- [x] 批量设计审查完成（11 个文档，均 NEEDS REVISION）
- [x] 修复 P0 级问题：波次缩放不一致（boss_bonus 0.35→0.68，Wave10 HP 从公式/表格不一致修正为 3.50x，参考 Brotato 实际数据标定）
- [x] 碰撞控制权冲突 — 已实现（引用计数暂停机制）
- [x] Buff 公式错误 — 已修正术语（percent_additive/flat_additive）
- [x] Boss 保证生成 — 已实现（enemy-spawn-system §5.1）
- [x] 星级公式校准 — 未找到对应定义，疑似幽灵项
- [ ] 修复完成后开始 Godot 原型实现
- [ ] 原型验证高风险系统：碰撞检测、波次节奏
- [ ] 实现完成后运行 `/gate-check pre-production`
