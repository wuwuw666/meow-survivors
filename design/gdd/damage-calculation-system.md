# 伤害计算系统 (Damage Calculation System)

> **Status**: Approved
> **Author**: [user + agents]
> **Last Updated**: 2026-04-01
> **Implements Pillar**: 成长的爽感（伤害提升可感知）

---

## Overview

伤害计算系统负责计算所有伤害数值，包括玩家攻击敌人、敌人攻击玩家、防御塔攻击敌人。这是一个**纯公式系统**：输入攻击者属性和目标属性，输出伤害数值。没有状态，每次调用独立计算。

**核心职责**:
- 计算基础伤害
- 应用伤害加成/减益
- 处理暴击
- 返回最终伤害值

**核心接口**:
- `calculate_damage(attacker: Node, target: Node, attack_data: Dictionary) -> int` — 计算并返回伤害值

---

## Player Fantasy

伤害计算系统支撑 **"成长的爽感"** 支柱。玩家应该感受到：

- **数值明显增长** — 升级后伤害数字明显变大
- **暴击惊喜** — 暴击时数字跳得更高，有惊喜感
- **清晰反馈** — 伤害数字直接显示在敌人头上

**情感目标**: **成长感 + 惊喜感**
- 每次升级伤害提升 ≥15%（可感知）
- 暴击伤害 = 1.5x-2x 普通伤害（有惊喜）

**参考游戏**:
- **吸血鬼幸存者**: 伤害数字简洁，但升级后伤害明显提升
- **Brotato**: 伤害数字直接显示，成长感强烈

---

## Detailed Design

### Core Rules

伤害计算流程：

```
1. 获取攻击者基础伤害
2. 应用伤害加成 (攻击力倍率、升级加成等)
3. 计算是否暴击
4. 应用目标防御/伤害减免
5. 返回最终伤害值 (最小为1)
```

#### 伤害类型

| 伤害类型 | 来源 | 说明 |
|---------|------|------|
| **physical** | 玩家攻击、敌人攻击、防御塔 | 物理伤害，可被护甲减免 |
| **ability** | 技能伤害 | 技能伤害，通常不可减免 |
| **true** | 真实伤害 | 无视护甲 |

#### 核心计算函数

```gdscript
func calculate_damage(attacker: Node, target: Node, attack_data: Dictionary) -> int:
    var base_damage = attack_data.base_damage
    var damage_type = attack_data.get("damage_type", "physical")

    # 1. 应用攻击者伤害加成
    var damage_multiplier = 1.0
    damage_multiplier *= attacker.damage_multiplier  # 升级/装备加成

    # 2. 暴击判定
    var is_crit = randf() < attacker.crit_chance
    if is_crit:
        damage_multiplier *= attacker.crit_multiplier

    # 3. 应用目标防御
    var final_damage = base_damage * damage_multiplier
    if damage_type == "physical":
        final_damage = apply_armor_reduction(final_damage, target.armor)

    # 4. 最小伤害为1
    return max(1, int(final_damage))
```

### States and Transitions

**无状态** — 伤害计算系统是纯函数系统，每次调用独立计算，不维护任何状态。

### Interactions with Other Systems

| 系统 | 交互方向 | 数据流 | 说明 |
|-----|---------|--------|------|
| **自动攻击系统** | 攻击 → 伤害 | 攻击者属性、目标属性 → 返回伤害值 | 玩家攻击敌人时调用 |
| **敌人系统** | 敌人 → 伤害 | 敌人属性、玩家属性 → 返回伤害值 | 敌人攻击玩家时调用 |
| **防御塔系统** | 塔 → 伤害 | 塔属性、敌人属性 → 返回伤害值 | 防御塔攻击敌人时调用 |
| **生命值系统** | 伤害 → 生命值 | 最终伤害值 → 扣除目标HP | 接收伤害值并应用 |

---

## Formulas

### 1. 基础伤害公式

```
final_damage = base_damage × total_multiplier × armor_factor

其中:
- total_multiplier = damage_multiplier × (暴击时 crit_multiplier)
- armor_factor = 1 - armor/(armor + armor_scaling) (护甲减伤)
```

### 2. 伤害加成计算

```
damage_multiplier = 1.0 + sum(所有加成百分比)

示例:
- 基础攻击力: 10
- 升级增加20%: +0.2
- 装备增加15%: +0.15
- damage_multiplier = 1.0 + 0.2 + 0.15 = 1.35
```

### 3. 暴击公式

```
暴击判定: randf() < crit_chance (0.0 - 1.0)
暴击伤害: damage × crit_multiplier (默认 1.5 - 2.0)
```

| 参数 | 默认值 | 范围 | 说明 |
|-----|-------|------|------|
| `crit_chance` | 5% (0.05) | 0-50% | 暴击概率 |
| `crit_multiplier` | 1.5x | 1.2-3.0x | 暴击伤害倍率 |

### 4. 护甲减伤公式

```
armor_reduction = armor / (armor + armor_scaling)
final_damage = damage × (1 - armor_reduction)

其中 armor_scaling 为可调参数，默认 100.0

示例:
- 基础伤害: 100
- 目标护甲: 50
- armor_scaling: 100 (默认)
- armor_reduction = 50 / (50 + 100) = 0.333 (33.3%减免)
- final_damage = 100 × (1 - 0.333) = 67
```

**护甲收益曲线**（递减收益）：

| 护甲值 | 减伤比例 | 边际收益 |
|-------|---------|---------|
| 0 | 0% | — |
| 25 | 20% | +20% |
| 50 | 33% | +13% |
| 100 | 50% | +17% |
| 200 | 67% | +17% |
| 500 | 83% | +16% |

### 5. 最小伤害规则

```
final_damage = max(1, floor(calculated_damage))
```

**规则**: 任何攻击至少造成 1 点伤害，即使护甲极高或伤害极低。

---

## Edge Cases

| 边界情况 | 处理方式 |
|---------|---------|
| 伤害计算结果 < 1 | 返回 1（最小伤害规则） |
| 护甲为负数 | 视为 0 处理，不减伤 |
| 暴击概率 > 100% | 限制为 100%，每次必定暴击 |
| 暴击倍率 < 1.0 | 限制为 1.0，暴击不降低伤害 |
| 同时触发多个伤害加成 | 累加所有百分比，然后乘以基础伤害 |
| 目标已死亡 | 由调用方检查，伤害计算系统不负责 |
| 攻击者死亡后伤害结算 | 由调用方保证攻击者存活；系统不维护攻击者状态 |
| 伤害类型不存在 | 默认使用 "physical" 类型 |
| 同一帧内多次攻击同一目标 | 每次独立计算，分别触发暴击判定 |

---

## Dependencies

### 上游依赖

**无** — Foundation 层，纯公式系统，不依赖其他游戏系统。

### 下游依赖

| 系统 | 依赖类型 | 数据接口 | 说明 |
|-----|---------|---------|------|
| **自动攻击系统** | 硬依赖 | `calculate_damage()` | 玩家攻击敌人 |
| **敌人系统** | 硬依赖 | `calculate_damage()` | 敌人攻击玩家 |
| **防御塔系统** | 硬依赖 | `calculate_damage()` | 塔攻击敌人 |
| **生命值系统** | 硬依赖 | `apply_damage()` | 应用伤害到目标 |

### 接口定义

```gdscript
# 护甲减伤参数（可调）
const ARMOR_SCALING: float = 100.0

# 计算伤害值（纯函数）
func calculate_damage(attacker: Node, target: Node, attack_data: Dictionary) -> int:
    # attack_data 结构:
    # {
    #   base_damage: int,        # 必需
    #   damage_type: String,     # 可选，默认 "physical"
    # }
    pass

# 应用护甲减伤
func apply_armor_reduction(damage: float, armor: int) -> float:
    if armor <= 0:
        return damage
    var reduction = armor / (armor + ARMOR_SCALING)
    return damage * (1.0 - reduction)
```

---

## Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 说明 |
|-------|------|-------|---------|------|
| **base_damage** | int | 各攻击自定义 | 1-1000 | 基础伤害值，由攻击类型决定 |
| **crit_chance** | float | 0.05 (5%) | 0.0-0.5 | 暴击概率。过高导致暴击无惊喜感 |
| **crit_multiplier** | float | 1.5 | 1.2-3.0 | 暴击倍率。过低无惊喜，过高不平衡 |
| **armor_scaling** | float | 100.0 | 50-200 | 护甲公式分母。越低护甲越强，越高护甲越弱 |
| **min_damage** | int | 1 | 1-5 | 最小伤害值 |

**参数交互**:
- `armor_scaling` 影响护甲收益曲线陡峭程度
- `crit_chance` + `crit_multiplier` 影响平均DPS

**极端值测试**:
- `crit_chance = 1.0` → 每次暴击，失去惊喜感
- `crit_multiplier = 5.0` → 暴击伤害过高，平衡被破坏
- `armor_scaling = 10` → 50护甲就能减免83%伤害，玩家难以被杀死

---

## Acceptance Criteria

### 功能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-01 | 基础伤害计算 | 攻击者伤害=10，无加成/暴击/护甲 | 返回 10 |
| AC-02 | 伤害加成生效 | 加成+50% | 伤害×1.5 |
| AC-03 | 暴击触发 | crit_chance=100% | 每次暴击，伤害×crit_multiplier |
| AC-04 | 护甲减伤 | 目标护甲=100 | 减伤50% |
| AC-05 | 最小伤害 | 伤害计算结果=0.5 | 返回 1 |
| AC-06 | 真实伤害无视护甲 | damage_type="true"，目标护甲=100 | 不减伤 |

### 边界测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-07 | 护甲为负 | 护甲=-50 | 视为0，正常伤害 |
| AC-08 | 暴击概率超限 | crit_chance=1.5 | 限制为100% |
| AC-09 | 多次攻击独立暴击 | crit_chance=50%，攻击10次 | 约5次暴击（统计验证） |

### 性能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-10 | 伤害计算性能 | 连续计算1000次 | < 1ms 总耗时 |