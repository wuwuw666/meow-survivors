# 解锁系统 (Unlock System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-15
> **Implements Pillar**: 成长的爽感 + 策略有深度

---

## Overview

解锁系统负责统一管理“玩家现在到底可以用什么”的长期状态。

在当前 `C-Tangy` 成长结构中，解锁系统本身不产生资源，也不负责购买节点，而是作为一层清晰的判定与查询边界，回答：

- 哪些塔已经可用
- 哪些局外成长节点已解锁
- 哪些后续节点可以显示为可购买

它是 `tower-meta-progression-system` 和运行时系统之间的桥梁。

---

## Design Goal

解锁系统要实现三件事：

1. 把“已获得什么”统一表达出来
2. 让运行时系统不必直接理解完整科技树
3. 让 UI 可以清晰展示已解锁 / 可购买 / 未解锁状态

---

## Core Loop

```text
读取存档
-> 得到已购买节点
-> 计算当前解锁状态
-> 提供给塔系统 / 局外成长界面 / 放置系统查询
```

---

## Unlock Scope

MVP 解锁系统优先覆盖：

### 1. 塔类型解锁

示例：

- `fish_shooter`
- `yarn_launcher`
- `catnip_aura`

### 2. 局外成长节点可见性

示例：

- 某节点是否已购买
- 某节点是否满足前置条件
- 某节点是否可购买

### 3. 后续扩展入口

未来可扩展：

- 额外改造槽解锁
- 改造件候选池扩展
- 特殊塔分支解锁

---

## State Model

每个可解锁对象建议至少有三种状态：

| 状态 | 含义 |
|---|---|
| `Locked` | 不可用，不满足前置条件或尚未购买 |
| `Available` | 已满足前置条件，可购买 / 可解锁 |
| `Unlocked` | 已购买或已永久拥有 |

设计意图：

- UI 不只要知道“有没有”
- 还要知道“是否该展示为下一步目标”

---

## Query Interface

MVP 建议提供以下查询能力：

- `is_tower_unlocked(tower_type: String) -> bool`
- `is_meta_node_unlocked(node_id: String) -> bool`
- `is_meta_node_available(node_id: String) -> bool`
- `get_unlocked_towers() -> Array[String]`
- `get_available_meta_nodes() -> Array[String]`

---

## Dependencies

### 上游依赖

- `save-system`：提供已保存的长期状态
- `tower-meta-progression-system`：提供节点定义与前置关系

### 下游依赖

- `tower-system`：判断某塔是否能被创建
- `tower-placement-system`：限制塔位选择面板中可见内容
- UI 系统：显示节点状态与解锁结果

---

## UI Rules

局外成长界面中，解锁系统应支持如下展示：

- `Unlocked`：正常高亮，可显示已拥有标记
- `Available`：正常显示，可购买
- `Locked`：置灰，并显示前置条件

设计意图：

- 玩家要知道“我下一步离什么最近”
- 不只是看到一堆灰节点

---

## Edge Cases

| 编号 | 情况 | 处理方式 |
|---|---|---|
| EC-UL-01 | 节点已购买但前置关系数据缺失 | 仍视为 `Unlocked`，并记录数据错误 |
| EC-UL-02 | 存档中有未知塔 ID | 忽略该项并记录错误 |
| EC-UL-03 | 节点前置未解锁但被错误写入已购买 | 以存档已购买为准，并在下次保存时清洗 |

---

## Acceptance Criteria

| ID | 验证项 | Pass 标准 |
|---|---|---|
| AC-UL-01 | 塔解锁查询 | 已解锁塔能被正确识别为可用 |
| AC-UL-02 | 节点状态查询 | 已购买 / 可购买 / 未解锁状态能被正确区分 |
| AC-UL-03 | 放置面板过滤 | 未解锁塔不会出现在可建造列表中 |
| AC-UL-04 | UI 状态表达 | 局外成长界面能清楚显示节点状态 |
