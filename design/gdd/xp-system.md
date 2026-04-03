# 经验系统 (XP System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 成长的爽感（升级反馈清晰可感知）

## Overview

经验系统（XP System）管理游戏中玩家的**经验获取、等级提升和升级触发**。敌人死亡时掉落经验球 → 玩家靠近拾取 → 经验条增长 → 经验满后触发升级事件 → 升级面板弹出。这是驱动玩家 Build 成长的核心循环引擎。

**核心职责**：经验掉落 → 拾取 → 等级计算 → `level_up` 触发

**核心接口**:
- `add_xp(amount: int, source: String) -> void`
- `signal level_up(new_level: int)`
- `signal xp_changed(current: int, needed: int)`
- `get_level() -> int`
- `get_xp_to_next() -> int`

---

## Player Fantasy

**情感目标：看得见的成长**

经验球从敌人尸体上飞出，一颗颗飞向玩家——经验条一格格涨——"再捡几个就升级了"——满格时"叮"的升级音效+"LEVEL UP!"闪现，然后暂停世界让玩家从 3 个升级里选一个。这是最直接的"我在变强"的反馈链。

**玩家应该感受到**:
- "经验球飞过来的感觉好爽——像磁铁吸铁屑"
- "经验条快满了——再杀几个就升级了!"
- "升级时画面一闪，暂停让我选——好期待会出什么升级卡"

**玩家不应该感受到**:
- "我杀了怪但经验条没动"（掉落或拾取 bug）
- "升了几级但升级选项都一样"（升级池多样性不足，归升级池系统负责）
- "经验条满了但一直没弹出升级面板"（level_up 未正确触发）

---

## Detailed Rules

### 规则 1：经验来源（敌人掉落）

每种敌人类型定义固定的经验掉落值：

| 敌人类型 | 经验掉落 |
|---------|---------|
| normal_a (毛团怪) | 3 |
| normal_b (圆墩怪) | 3 |
| normal_c (壮壮怪) | 5 |
| elite (精英怪) | 10 |
| boss (Boss 怪) | 50 |

敌人死亡时生成经验球掉落物（与金币掉落物并行生成，互不干扰）。

### 规则 2：等级与升级所需经验

```
等级从 1 开始。每级升级所需经验：

xp_needed(level) = base_xp × (1 + (level - 1) × 0.3) 向上取整

默认 base_xp = 10

| 当前等级 | 升级所需XP | 累计所需XP |
|---------|-----------|-----------|
| 1 → 2   | 10        | 10        |
| 2 → 3   | 13        | 23        |
| 3 → 4   | 17        | 40        |
| 4 → 5   | 22        | 62        |
| 5 → 6   | 28        | 90        |
| 6 → 7   | 37        | 127       |
| 7 → 8   | 48        | 175       |
| 8 → 9   | 62        | 237       |
| 9 → 10  | 80        | 317       |
| 10 → 11 | 104       | 421       |
| 11 → 12 | 135       | 556       |
| 12 → 13 | 175       | 731       |
| 13 → 14 | 227       | 958       |
| 14 → 15 | 295       | 1253      |
| 15 → 16 | 383       | 1636      |

30% 递增速率保证:
- 前 5 级每级只需击杀 3-4 只 normal_a (3xp 每只)
- 第 10 级需要约 15-20 只怪
- 第 15 级需要约 30-40 只怪
- 一局 10 波游戏预计升到 8-15 级
```

### 规则 3：经验球拾取

与金币拾取机制相同（共享 CoinPickup 类或独立 XPPickup 类），但:
- 拾取范围相同（60px 半径 Area2D）
- 飞向速度稍慢（250 px/s vs 金币 300）——经验球应"飘"而不是"弹"
- 颜色区分：经验球为紫色/blue 球体（与金色金币视觉区分）
- lifetime 相同（5 秒）

```
XPPickup (Area2D):
    value: int = 3
    lifetime: float = 5.0s
    pickup_range: float = 60.0 px
    fly_speed: float = 250.0 px/s
    # 拾取后 add_xp(value), queue_free()
```

### 规则 4：升级触发

```
func add_xp(amount: int, source: String = "enemy_kill") -> void:
    current_xp += amount
    emit_signal("xp_changed", current_xp, xp_needed)
    
    while current_xp >= xp_needed:
        current_xp -= xp_needed
        player_level += 1
        xp_needed = calc_xp_needed(player_level)
        emit_signal("level_up", player_level)
    # while 循环处理"一次拾取跨多级"的情况
```

- MVP 升级**不允许跳过**——`level_up` → 暂停游戏 → 弹出升级面板 → 玩家选择后恢复
- 一局**无等级上限**——理论上可以无限升，但 10 波约 8-15 级为正常区间

---

## Formulas

### 公式 1：升级所需经验

```
xp_needed(level) = ceil(base_xp × (1.0 + (level - 1) × 0.3))
    base_xp = 10

示例 (5 级升 6 级):
    xp_needed = ceil(10 × (1 + 4 × 0.3))
               = ceil(10 × 2.2)
               = 22
```

### 公式 2：变量汇总

| 变量 | 类型 | 默认值 | 安全范围 | 说明 |
|------|------|--------|---------|------|
| `base_xp` | int | 10 | 5-20 | 1 级升 2 级所需经验 |
| `xp_growth_rate` | float | 0.3 | 0.15-0.5 | 每级经验需求增长率 |
| `xp_fly_speed` | float | 250.0 | 150-400 | 经验球飞向玩家速度 |
| `xp_pickup_range` | float | 60.0 | 30-120 | 拾取范围半径 |
| `xp_lifetime` | float | 5.0 | 3.0-10.0 | 掉落物自动消失时间 |

---

## Edge Cases

| 编号 | 边界情况 | 处理方式 |
|------|---------|---------|
| EC-01 | 一次拾取跨 2 级 (如当前 XP=9, 拾取 15xp) | while 循环连续触发 2 次 level_up |
| EC-02 | 升级面板弹出时又有经验拾取 | 经验继续累加到 current_xp（但暂停期间不拾取——掉落物冻结）|
| EC-03 | 经验条满了但升级面板延迟 | current_xp 保持 >= xp_needed，再次触发 level_up 时立即处理 |
| EC-04 | 游戏结束时剩余未满级经验 | 结算系统统计时计入"总获取经验"，但不触发升级 |
| EC-05 | 掉落物重叠 (多个经验球在同一位置) | 每个独立节点，玩家范围内各自飞入 |

---

## Dependencies

| 上游系统 | 依赖类型 | 接口 | 说明 |
|---------|---------|------|------|
| **敌人系统** | 上游 | `enemy_died(enemy)` | 触发经验球生成 |
| **移动系统** | 软依赖 | 玩家位置 | 拾取范围判定 |

| 下游系统 | 依赖类型 | 接口 | 说明 |
|---------|---------|------|------|
| **升级选择系统** | 硬依赖 | `level_up(new_level)` 信号 | 触发升级面板 |
| **UI 系统** | 软依赖 | `xp_changed(current, needed)` 信号 | 更新经验条 HUD |
| **结算系统** | 软依赖 | `total_xp_earned` 统计值 | 结算展示 |

---

## Acceptance Criteria

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-XP-01 | 基础经验掉落 | 击杀 normal_a | 生成 3xp 经验球掉落物 |
| AC-XP-02 | 拾取经验 | 玩家靠近经验球 | 经验球飞向玩家，current_xp +3 |
| AC-XP-03 | Boss 经验掉落 | 击杀 boss | 生成 50xp 经验球 |
| AC-XP-04 | 升级触发 | 经验累计 ≥ xp_needed | level_up 信号发出, new_level 正确 |
| AC-XP-05 | 连续升级 | 拾取大量经验（跨 2 级） | 连续 2 次 level_up, player_level 正确 |
| AC-XP-06 | xp_changed 信号 | 每次经验变化 | 信号发出, 参数(current, needed) 正确 |
| AC-XP-07 | 经验自动消失 | 5 秒不拾取 | 经验球淡出后 queue_free() |
| AC-XP-08 | 升级所需经验计算 | 查询 5→6 级 | xp_needed = ceil(10 × 2.2) = 22 |
| AC-XP-09 | 等级查询 | 游戏开始 | get_level() 返回 1 |
