# 存档系统 (Save System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-15
> **Implements Pillar**: 成长的爽感 + 长期推进感

---

## Overview

存档系统负责把《Meow Survivors》中**跨局保留**的进度稳定保存下来，并在下次进入游戏时恢复。

在当前 `C-Tangy` 成长结构中，存档系统只服务于**长期进度**，不负责保存单局中的临时状态。

当前明确区分：

- 角色局内升级：**不存档**
- 塔局内改造：**不存档**
- 结算资源、解锁状态、局外成长节点：**需要存档**

---

## Design Goal

存档系统要实现三件事：

1. 让玩家的长期塔成长可靠保留
2. 不把单局临时状态错误带进下一局
3. 在 MVP 阶段保持数据结构简单、可恢复、可调试

---

## Core Loop

```text
进入游戏
-> 读取存档
-> 恢复 tower_scrap / 已解锁塔 / 已购买成长节点
-> 玩家进行单局与局外成长
-> 发生关键进度变更
-> 写入存档
```

---

## Save Scope

### 需要保存

- 当前 `tower_scrap`
- 已解锁塔列表
- 已购买的局外成长节点
- 已应用的基础强化结果
- 基础设置项（后续可扩展）

### 不需要保存

- 当前 run 的角色等级
- 当前 run 的 XP
- 当前 run 的塔改造件
- 当前 run 中已放置的塔
- 当前 run 波次进度

设计意图：

- 单局结束即清空单局状态
- 只把长期体系保留下来

---

## MVP Save Data Shape

MVP 推荐使用轻量结构：

```json
{
  "meta_version": 1,
  "tower_scrap": 35,
  "unlocked_towers": ["fish_shooter", "yarn_launcher"],
  "purchased_meta_nodes": [
    "tmp_start_fish",
    "tmp_fish_damage_1",
    "tmp_unlock_yarn"
  ]
}
```

设计要求：

- 可直接阅读
- 容易做版本迁移
- 容易在调试时人工检查

---

## Save Triggers

MVP 推荐以下时机触发保存：

### 1. 结算奖励结算完成后

保存：

- 新获得的 `tower_scrap`

### 2. 购买局外成长节点后

保存：

- 已消费资源
- 已解锁塔
- 已购买节点状态

### 3. 返回主菜单或退出游戏前

作为兜底保存点。

设计意图：

- 减少进度丢失风险
- 不要求每秒自动频繁写盘

---

## Load Rules

### 规则 1：启动时优先加载长期进度

启动游戏后，优先读取：

- `tower_scrap`
- 解锁塔状态
- 局外成长节点

这些数据加载完成后，其他系统才读取可用塔与基础强化。

### 规则 2：无存档时回退初始状态

如果没有有效存档：

- 使用默认起始塔体系
- `tower_scrap = 0`
- 仅初始节点已解锁

### 规则 3：坏档回退

若存档损坏或版本不兼容：

- 尝试读取可恢复字段
- 恢复失败则回退默认初始状态
- 记录错误并避免崩溃

---

## Dependencies

### 上游依赖

- `settlement-system`：提供结算资源变更
- `tower-meta-progression-system`：提供节点购买结果
- `unlock-system`：提供解锁状态结果

### 下游依赖

- `tower-system`：读取已解锁塔与基础强化
- `tower-placement-system`：根据解锁状态决定可建造内容
- UI 系统：展示长期资源与成长状态

---

## Tuning Knobs

| 参数 | 默认值 | 说明 |
|---|---:|---|
| `save_format_version` | 1 | 当前存档格式版本 |
| `auto_save_on_settlement` | true | 结算后自动保存 |
| `auto_save_on_meta_purchase` | true | 购买局外成长后自动保存 |

---

## Edge Cases

| 编号 | 情况 | 处理方式 |
|---|---|---|
| EC-SV-01 | 无存档文件 | 创建默认初始进度 |
| EC-SV-02 | 存档字段缺失 | 对缺失字段回退默认值 |
| EC-SV-03 | 存档版本过旧 | 做轻量迁移或回退默认值 |
| EC-SV-04 | 保存中断 | 保留上一次有效存档，避免写出半损坏数据 |

---

## Acceptance Criteria

| ID | 验证项 | Pass 标准 |
|---|---|---|
| AC-SV-01 | 初始加载 | 无存档时能正确生成默认进度 |
| AC-SV-02 | 结算资源保存 | 本局获得的 `tower_scrap` 下次启动仍存在 |
| AC-SV-03 | 解锁状态保存 | 已解锁塔在下次启动后仍可用 |
| AC-SV-04 | 节点购买保存 | 已购买的局外成长节点可正确恢复 |
| AC-SV-05 | 单局状态不泄漏 | 新开一局时不会带入上一局角色等级或塔改造 |
