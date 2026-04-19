# 升级池系统 (Upgrade Pool System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-10
> **Implements Pillar**: 成长的爽感 + 策略有深度

---

## Overview

升级池系统是角色局内升级的候选内容库。它负责定义：

- 哪些角色升级可以出现在单局中
- 什么时候出现
- 哪些升级互斥
- 哪些升级可以重复
- 候选生成时如何保证方向和质量

在当前 `C-Tangy` 成长结构中，升级池系统是**角色升级池**，不再承担塔升级内容。塔的局内变化由 `tower-mod-system` 负责，塔的长期成长由局外成长系统负责。

---

## Design Goal

升级池系统要保证一件事：

**每次角色升级都在帮助玩家塑造本局的角色支援风格，而不是把塔成长、塔改造和角色成长混成一个大池子。**

---

## Upgrade Categories

所有升级分为四类：

### 1. Hero Support

作用：

- 强化角色对塔阵的支援价值
- 提高 debuff、辅助、联动能力

示例：

- 对被减速目标造成更多伤害
- 英雄命中后施加易伤
- 英雄在辅助塔范围内获得额外增益

### 2. Hero Mobility

作用：

- 提高补位、赶路、救火效率

示例：

- 移速提升
- 冲刺刷新
- 靠近漏怪时获得加速

### 3. Hero Survival

作用：

- 提高容错和持续站场能力

示例：

- 最大生命提高
- 受击减伤
- 紧急恢复

### 4. Hero Direct Combat

作用：

- 提高角色本人的输出表现

示例：

- 伤害提高
- 攻速提高
- 投射物变化

约束：

- 该类升级应少于支援与机动类
- 不能长期把角色推成默认主 C

---

## Category Weight Rules

MVP 建议默认权重：

| 类别 | 默认占比倾向 |
|---|---:|
| Hero Support | 35% |
| Hero Mobility | 25% |
| Hero Survival | 25% |
| Hero Direct Combat | 15% |

设计意图：

- 让角色升级更偏支援、防线运营与补位
- 保留一定直接战斗爽感
- 避免 XP 升级把玩家导向“角色单刷”

---

## Candidate Generation Rules

每次请求候选时，按以下顺序处理：

1. 筛出当前合法升级
2. 去除已达上限或前置条件未满足的升级
3. 去除冲突项
4. 按分类权重与当前 run 状态加权
5. 返回默认 `3` 个候选

### 保底规则

- 每次升级至少出现 `1` 个非纯输出项
- 前期升级优先保证 `Support / Mobility / Survival` 至少有其一
- 连续两次升级中，`Hero Direct Combat` 不应高频重复刷屏
- 如果当前角色明显缺生存或机动，相关项权重上升

---

## Run-State Bias

升级池应根据局内状态调整权重。

### 当角色频繁补漏时

提高：

- Hero Mobility
- Hero Support

### 当角色生存压力过高时

提高：

- Hero Survival

### 当角色支援链已经形成时

允许提高：

- Hero Support 的高阶联动项
- 少量 Hero Direct Combat 收束项

---

## Duplicate And Conflict Rules

升级按重复规则分三类：

| 类型 | 规则 |
|---|---|
| Single Pick | 本局只能拿一次 |
| Stackable | 可重复拿，直到层数上限 |
| Branch | 需要前置升级才能出现 |

冲突示例：

- 两种互相排斥的攻击形态不能同时出现
- 明显对立的支援分支不能并存

---

## Example MVP Upgrade Set

| ID | 名称 | 类别 | 类型 | 说明 |
|---|---|---|---|---|
| U01 | 灵巧步伐 | Hero Mobility | Stackable | 提升角色移速 |
| U02 | 紧急补位 | Hero Mobility | Single Pick | 漏怪附近获得短时加速 |
| U03 | 软垫护身 | Hero Survival | Stackable | 提高最大生命 |
| U04 | 猫咪韧性 | Hero Survival | Single Pick | 低血时获得减伤 |
| U05 | 缠敌标记 | Hero Support | Stackable | 命中后附加易伤 |
| U06 | 协防意识 | Hero Support | Single Pick | 处于塔覆盖区时支援效率提升 |
| U07 | 追击爪击 | Hero Direct Combat | Stackable | 对残血敌人增伤 |
| U08 | 快速连击 | Hero Direct Combat | Stackable | 提升角色攻速 |

---

## Core Interface

- `get_upgrade_candidates(run_state: Dictionary, request_count: int = 3) -> Array[UpgradeDefinition]`
- `mark_upgrade_taken(upgrade_id: String, run_state: Dictionary) -> void`
- `get_upgrade_definition(upgrade_id: String) -> UpgradeDefinition`

---

## Dependencies

### 上游依赖

- 游戏设计规则：定义角色在本局内的定位
- XP 系统：提供升级时机

### 下游依赖

- 升级选择系统：消费候选列表
- 自动攻击 / 移动 / 生存系统：消费升级效果
- UI 系统：显示升级名称、描述、分类、稀有度

---

## Tuning Knobs

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `support_weight` | 0.35 | 支援项基础权重 |
| `mobility_weight` | 0.25 | 机动项基础权重 |
| `survival_weight` | 0.25 | 生存项基础权重 |
| `direct_combat_weight` | 0.15 | 直战项基础权重 |
| `candidate_count` | 3 | 默认候选数 |
| `repeat_penalty` | 0.25 | 最近出现过的候选惩罚 |

---

## Edge Cases

| 编号 | 情况 | 处理方式 |
|---|---|---|
| EC-01 | 合法候选不足 3 个 | 返回全部合法候选 |
| EC-02 | 当前 run 极端偏科 | 适度提升缺失类别权重，不强行重置 build |
| EC-03 | 数据定义缺字段 | 该升级不进入候选池 |
| EC-04 | 单一输出流过强 | 降低直战类权重或提高前置条件 |

---

## Acceptance Criteria

| ID | 验证项 | Pass 标准 |
|---|---|---|
| AC-UP-01 | 角色专属升级池 | 候选只包含角色成长项 |
| AC-UP-02 | 分类分布合理 | Support / Mobility / Survival 为主 |
| AC-UP-03 | 非纯输出保底 | 每次升级至少有 1 个非纯输出项 |
| AC-UP-04 | build 倾向存在 | 不同 run 能形成不同角色支援风格 |
| AC-UP-05 | 不抢塔主角位 | XP 升级默认不把角色推成主输出核心 |
