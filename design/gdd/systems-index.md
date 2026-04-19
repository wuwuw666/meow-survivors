# Systems Index: Meow Survivors

> **Status**: Draft
> **Created**: 2026-04-01
> **Last Updated**: 2026-04-15
> **Current Direction**: C-Tangy hybrid progression

---

## Overview

《Meow Survivors》当前采用“幸存者操作 + 塔防主导 + 三层成长”的混合结构。

当前确认的成长拆分为：

1. **角色局内成长**
   由 `xp-system`、`upgrade-selection-system`、`upgrade-pool-system` 负责
2. **塔局内变化**
   由 `tower-mod-system` 负责
3. **塔局外成长**
   由结算与后续局外成长系统负责

这意味着当前版本的设计原则是：

- XP 升级只强化角色
- 塔在单局中的花样来自改造件
- 塔的长期积累来自局外资源
- 防线胜负主要由塔位、塔协同和角色补位共同决定

---

## Current Interpretation Notes

### 1. 塔依然是防线主角

塔阵负责：

- 主持续输出
- 关键区域覆盖
- 结构性防线强度

角色负责：

- 补漏
- 救火
- 运营
- debuff / 支援

### 2. XP 不再直接强化塔

角色升级只服务角色局内 build，不再承担：

- 塔数值升级
- 塔行为升级
- 塔局外成长

### 3. 塔的局内花样来自改造件

塔在本局内的差异主要来自：

- 连射
- 分叉
- 强控
- 范围变化
- 联动触发

这些变化由 `tower-mod-system` 提供。

### 4. 局外成长留给塔体系

每局结算后获得的长期资源，主要用于：

- 新塔解锁
- 塔基础成长
- 分支或科技扩展

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc |
|---|---|---|---|---|---|
| 1 | Input System | Core | MVP | Approved | `design/gdd/input-system.md` |
| 2 | Collision Detection System | Core | MVP | Approved | `design/gdd/collision-detection-system.md` |
| 3 | Damage Calculation System | Core | MVP | Approved | `design/gdd/damage-calculation-system.md` |
| 4 | Difficulty Curve System | Meta | MVP | Approved | `design/gdd/difficulty-curve-system.md` |
| 5 | Map System | Meta | MVP | Approved | `design/gdd/map-system.md` |
| 6 | Movement System | Core | MVP | Approved | `design/gdd/movement-system.md` |
| 7 | Health System | Core | MVP | Approved | `design/gdd/health-system.md` |
| 8 | Target Selection System | Core | MVP | Approved | `design/gdd/target-selection-system.md` |
| 9 | Enemy System | Gameplay | MVP | Approved | `design/gdd/enemy-system.md` |
| 10 | Enemy Spawn System | Gameplay | MVP | Approved | `design/gdd/enemy-spawn-system.md` |
| 11 | Wave System | Gameplay | MVP | Approved | `design/gdd/wave-system.md` |
| 12 | Tower System | Gameplay | MVP | Revised | `design/gdd/tower-system.md` |
| 13 | Tower Placement System | Gameplay | MVP | Revised | `design/gdd/tower-placement-system.md` |
| 14 | Auto Attack System | Gameplay | MVP | Approved | `design/gdd/auto-attack-system.md` |
| 15 | Coin System | Economy | MVP | Approved | `design/gdd/coin-system.md` |
| 16 | XP System | Progression | MVP | Revised | `design/gdd/xp-system.md` |
| 17 | Upgrade Pool System | Progression | MVP | Revised | `design/gdd/upgrade-pool-system.md` |
| 18 | Upgrade Selection System | Progression | MVP | Revised | `design/gdd/upgrade-selection-system.md` |
| 19 | Tower Mod System | Progression | MVP | In Design | `design/gdd/tower-mod-system.md` |
| 20 | UI System | UI | MVP | Revised | `design/gdd/ui-system.md` |
| 21 | Settlement System | UI / Meta | MVP | Revised | `design/gdd/settlement-system.md` |
| 22 | Save System | Persistence | v1.0 | In Design | `design/gdd/save-system.md` |
| 23 | Unlock System | Progression | v1.0 | In Design | `design/gdd/unlock-system.md` |
| 24 | Tower Meta Progression System | Progression | v1.0 | In Design | `design/gdd/tower-meta-progression-system.md` |

---

## Growth Structure Map

### Hero In-Run Growth

- `xp-system`
- `upgrade-selection-system`
- `upgrade-pool-system`

Purpose:

- 角色机动
- 角色支援
- 角色生存
- 少量角色直接战斗成长

### Tower In-Run Growth

- `tower-mod-system`
- `tower-system`

Purpose:

- 塔攻击形态变化
- 塔覆盖变化
- 塔与角色 / 其他塔的联动变化

### Tower Meta Progression

- `settlement-system`
- `tower-meta-progression-system`
- `save-system`（未来）

Purpose:

- 塔长期成长
- 新塔解锁
- 跨局积累

---

## Recommended Design Priority

当前优先顺序：

1. 先把角色 XP 成长线写清楚
2. 再把塔改造系统写清楚
3. 再定义结算如何喂给塔局外成长
4. 最后补塔长期成长与存档系统

---

## Next Steps

- [x] 将 XP 系统改为只服务角色局内成长
- [x] 将升级选择与升级池改为角色专属
- [x] 新增 `tower-mod-system.md`
- [x] 重写 `settlement-system.md` 以接入塔局外成长资源
- [x] 设计 `tower-meta-progression-system.md`
- [x] 在 UI 中明确区分角色升级、塔改造和结算奖励
- [x] 将塔系统与塔位交互改为兼容塔改造 + 局外成长模型
- [x] 补 `save-system` 与塔局外成长的数据落盘边界
- [x] 补 `unlock-system` 作为长期解锁状态查询层
- [x] 补 UI 对局外成长界面的入口与回流路径
