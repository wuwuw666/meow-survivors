# 金币系统 (Coin System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 成长的爽感（金币收集满足感）+ 策略有深度（金币花费决策）

## Overview

金币系统（Coin System）管理游戏中金币的**获取、存储和消费**。金币是放置和升级防御塔的唯一货币，通过击杀敌人获得。系统的核心职责是：敌人死亡时在其位置生成金币掉落物 → 玩家靠近拾取 → 增加金币计数 → 塔位放置/升级时扣除金币 → 更新 UI 显示。

**核心职责**：金币掉落 → 拾取 → 存储 → 消费 → 信号通知

**核心接口**：
- `add_coins(amount: int, source: String) -> void`
- `deduct_coins(amount: int) -> bool`
- `signal coins_changed(amount: int, reason: String)`
- `signal coins_picked_up(amount: int)`

---

## Player Fantasy

**情感目标：拾取的满足感 + 花费的决策感**

敌人死后"嘭"地蹦出几枚金币，金币像被磁铁吸引一样飞进玩家的金币计数——这种"收集"的快感是最直接的爽感反馈。同时每一枚金币都可以用来放塔或升级，花在哪里需要权衡——"放新塔"还是"升级旧的"？

**玩家应该感受到**：
- "看到金币飞出去'叮'地跳到总数上——好爽！"
- "金币在 HUD 上一直显示着——我随时知道能放什么塔"
- "花 10 金放塔还是 15 金升级——要选"

**玩家不应该感受到**：
- "我杀了一堆怪但金币数没变"（掉落没触发）
- "我放了塔但金币数还是显示那么多"（UI 不同步）
- "金币掉在地上捡不到"（碰撞检测或范围问题）

---

## Detailed Rules

### 规则 1：金币来源（敌人掉落）

每种敌人类型定义固定的金币掉落值：

| 敌人类型 | 金币掉落 |
|---------|---------|
| normal_a (毛团怪) | 2 |
| normal_b (圆墩怪) | 2 |
| normal_c (壮壮怪) | 3 |
| elite (精英怪) | 8 |
| boss (Boss 怪) | 25 |

敌人死亡时（`enemy_died` 信号），系统在其位置生成金币掉落物：

```
enemy_died 信号触发:
    coin_value = enemy_data.coin_value (受波次缩放)
    在 enemy_position 生成 CoinPickup Node:
        显示: 金币精灵 (Sprite2D，硬币动画)
        行为: 向玩家方向飞行 (当玩家在拾取范围内) 或 停留 3s 后自动消失
    player 进入拾取范围 (Area2D overlap):
        金币飞入 → add_coins(coin_value)
        queue_free() 金币节点
```

金币掉落物的拾取范围 = 玩家周围 60px 范围内（`Area2D`, 半径 60px）。

### 规则 2：金币存储

```gdscript
var player_coins: int = 0  # 当前金币数

func add_coins(amount: int, source: String = "enemy_kill") -> void:
    var old_coins = player_coins
    player_coins += amount
    emit_signal("coins_changed", player_coins, source)
    emit_signal("coins_picked_up", amount)

func deduct_coins(amount: int) -> bool:
    if player_coins < amount:
        return false
    player_coins -= amount
    emit_signal("coins_changed", player_coins, "spend")
    return true
```

- MVP 不设金币上限（int 自然上限足够）
- 金币在会话之间**不保留**（meta progression 由解锁系统处理）

### 规则 3：金币掉落物行为

```
CoinPickut (Area2D):
    var value: int = 2
    var lifetime: float = 5.0 秒
    var pickup_range: float = 60.0 px (玩家 Area2D)
    var fly_speed: float = 300.0 px/s

每帧:
    if player 在 pickup_range 内:
        方向 = (player_position - coin_position).normalized()
        position += 方向 × fly_speed × delta
        modulate.a 保持 1.0
    else:
        lifetime -= delta
        if lifetime < 1.5s: modulate.a = lifetime / 1.5  (淡出)
        if lifetime <= 0: queue_free()

    # 碰撞体保持存在直到被拾取或消失
```

### 规则 4：波次对金币掉落的影响

金币掉落量受波次缩放影响，但不与敌人 HP 等比例增长，避免后期金币溢出：

```
effective_coin_value = base_coin_value × max(1.0, 1.0 + (wave - 1) × 0.05)

第 1 波: × 1.00 (不变)
第 5 波: × 1.20 (+20%)
第 10 波: × 1.45 (+45%)

示例 (第 5 波, normal_a):
    2 × 1.20 = 2.4 → 取整为 2
示例 (第 10 波, boss):
    25 × 1.45 = 36.25 → 取整为 36
```

**设计意图**：金币增长慢于敌人 HP 增长（5% vs 20%/波），确保后期玩家需要更高效地管理金币，增加决策压力。

---

## Formulas

### 公式 1：金币掉落波次缩放

```
effective_coins = floor(base_coins × (1.0 + (wave - 1) × 0.05))
```

### 公式 2：变量汇总

| 变量 | 类型 | 默认值 | 安全范围 | 说明 |
|------|------|--------|---------|------|
| `pickup_range` | float | 60.0 | 30-120 | 拾取范围半径（像素） |
| `fly_speed` | float | 300.0 | 150-500 | 金币飞向玩家的速度（px/s） |
| `lifetime` | float | 5.0 | 2.0-10.0 | 金币未拾取自动消失时间 |
| `coin_growth_per_wave` | float | 0.05 | 0.0-0.1 | 每波金币掉落增长比例 |

---

## Edge Cases

| 编号 | 边界情况 | 处理方式 |
|------|---------|---------|
| EC-01 | 金币掉落物生成在地图外 | 地图边界钳制确保金币生成在地图内 |
| EC-02 | 大量金币同时飞向玩家 (50+ 怪同时死亡) | 每个金币独立飞行；fly_to_player 计算 < 0.01ms/个 |
| EC-03 | 玩家死亡后金币仍可拾取 | 死亡后游戏暂停，金币停止移动；重新开始时继续 |
| EC-04 | 金币 lifetime 刚好在玩家进入范围时归零 | lifetime 检查在 `queue_free()` 之前，0.1s 宽限期 |
| EC-05 | 消费金币后金币为负 | 验证 `player_coins >= amount` 后再扣费，不会出现负数 |

---

## Dependencies

| 上游系统 | 依赖类型 | 接口 | 说明 |
|---------|---------|------|------|
| **敌人系统** | 上游 | `enemy_died(enemy)` | 触发金币掉落物生成 |
| **移动系统** | 软依赖 | 玩家当前位置 | 拾取范围判定 |
| **波次系统** | 软依赖 | `get_current_wave()` | 金币掉落缩放系数 |

| 下游系统 | 依赖类型 | 接口 | 说明 |
|---------|---------|------|------|
| **塔位放置系统** | 硬依赖 | `player_coins`, `deduct_coins()` | 放置/升级检查金币 |
| **UI 系统** | 软依赖 | `coins_changed` 信号 | 更新金币 HUD |
| **结算系统** | 软依赖 | `player_coins` 最终值 | 结算时统计金币 |
| **音频系统** | 软依赖 | `coins_picked_up` 信号 | 播放拾取音效 |

---

## Tuning Knobs

| 参数 | 默认值 | 范围 | 影响 |
|------|--------|------|------|
| normal_a/b 金币掉落 | 2 | 1-5 | 太低玩家攒不够放塔；太高金币溢出无花费决策 |
| boss 金币掉落 | 25 | 10-50 | Boss 击杀应是"大丰收"，明显多于普通怪 |
| `pickup_range` | 60px | 30-120 | 太小要追着金币走很累；太大自动吸太多失去走位 |
| `lifetime` | 5s | 2-10 | 太短来不及捡；太长场上满地金币影响视觉 |
| `coin_growth_per_wave` | 0.05 | 0.0-0.1 | 0 = 后期完全没新金币；0.1 = 金币过剩 |

---

## Acceptance Criteria

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-CE-01 | 基础金币掉落 | 击杀 normal_a 敌人 | 在敌人位置生成 2 金币掉落物 |
| AC-CE-02 | 拾取金币 | 玩家靠近金币掉落物 | 金币飞向玩家，player_coins +2 |
| AC-CE-03 | Boss 金币掉落 | 击杀 boss | 生成 25 金币掉落物 |
| AC-CE-04 | 波次缩放 | 第 5 波击杀 normal_a | 金币掉落 = floor(2 × 1.20) = 2 |
| AC-CE-05 | 扣费成功 | 放置 fish_shooter(10 金) | player_coins -10, deduct_coins 返回 true |
| AC-CE-06 | 金币不足扣费失败 | player_coins=5, deduct_coins(10) | 返回 false, coins 不变 |
| AC-CE-07 | coins_changed 信号 | 每次金币变化 | 信号发出, 参数(新值, 原因) 正确 |
| AC-CE-08 | 金币自动消失 | 5 秒不拾取金币掉落物 | 金币节点淡出后 queue_free() |
| AC-CE-09 | 大量金币同时拾取 | 10 个敌人同时死亡, 全部拾取 | player_coins 正确累加对应值, 不丢失 |
