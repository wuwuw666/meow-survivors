# 防御塔系统 (Tower System)

> **Status**: In Design  
> **Author**: [user + agents]  
> **Last Updated**: 2026-04-09  
> **Implements Pillar**: 策略有深度（塔位决策 + 塔间联动）+ 成长的爽感（防线逐步成型）

## Overview

防御塔系统（Tower System）管理游戏中所有已放置防御塔的运行时行为。  
在《喵族幸存者》的当前设计方向里，**塔不是辅助系统，而是局内防守的主角**。玩家角色负责移动补位、收集资源、提供自动攻击支援，而真正决定一局强度上限和节奏稳定性的，是围绕固定塔位建立起来的防线。

MVP 中，塔系统不再强调“三个完全独立的大类塔”，而是收敛为两类核心定位：

- **输出塔**：负责持续清怪，是防线的主要伤害来源
- **辅助塔**：负责强化整条线的效率或稳定性

控制效果（如减速、击退、破甲、点燃）优先作为**输出塔的效果分支、升级分支或特殊弹丸属性**存在，而不是单独作为一整类主塔定位。

**核心职责**：

- 塔数据定义
- 塔放置与占位
- 输出塔攻击循环
- 辅助塔增益联动
- 塔的成长接口

**核心接口**：

- `place_tower(tower_type: String, slot_pos: Vector2) -> Node`
- `remove_tower(tower_node: Node) -> void`
- `upgrade_tower(tower_node: Node, upgrade_type: String) -> void`
- `signal tower_placed(tower: Node, tower_type: String, slot_pos: Vector2)`
- `signal tower_removed(tower: Node)`
- `signal tower_projectile_hit(enemy: Node, damage: int, tower_type: String)`

---

## Player Fantasy

**情感目标：我布下的防线真的在工作**

玩家希望获得的不是“我角色一个人把怪全杀了”，而是：

- “这座塔放在这里很关键。”
- “这一波是靠我的防线而不是纯操作守住的。”
- “我的升级让整条线变强了，而不是只让一个数值涨了。”
- “我不是在乱放塔，我是在搭一个有结构的阵。”

玩家不应该感受到：

- “塔只是陪衬，主角自己打完一切。”
- “塔和塔之间没有配合，放哪都差不多。”
- “控制和辅助没有存在感，不如全堆伤害。”
- “放塔只是形式，真正决定胜负的只有角色 build。”

---

## Design Direction

### 塔是主防线，角色是支援层

当前版本的塔系统服务于以下定位：

- 角色负责补位、走位、拾取经验、做升级决策
- 塔负责持续输出、防线覆盖、关键区控制与联动
- 一局是否顺畅，主要取决于塔位顺序、塔之间的配合、以及升级是否让防线成型

### 不再把“控制塔”作为单独大类

控制依然重要，但不再用“控制塔 = 一个完整大类”来定义。

更适合当前项目的方式是：

- 输出塔可以有纯伤害分支
- 输出塔也可以有控制分支
- 玩家通过升级或塔类型变体，决定这座输出塔是偏清怪、偏压制还是偏功能

这样可以减少 MVP 的塔类型复杂度，同时保留策略深度。

---

## Detailed Rules

### 规则 1：MVP 塔定位

| 塔定位 | 名称示例 | 主要职责 | 基础特征 | 说明 |
| ------ | -------- | -------- | -------- | ---- |
| 输出塔 | 小鱼干发射器 | 主输出 / 主清怪 | 有攻击范围、冷却、弹丸 | 核心主力塔 |
| 输出塔（效果分支） | 毛线球发射器 | 输出 + 控制效果 | 伤害较低，但附带减速或其他效果 | 仍属于输出塔体系 |
| 辅助塔 | 猫薄荷光环塔 | 增益友方 | 不直接攻击，提供范围 buff | 负责放大已有防线效率 |

**说明**：

- `fish_shooter` 是 MVP 的标准输出塔
- `yarn_launcher` 在当前方向里被视为“带控制效果的输出塔”，而不是独立第三类
- `catnip_aura` 是辅助塔，负责强化角色与其他输出塔

### 规则 2：塔放置与移除流程

```text
place_tower(tower_type, slot_pos):
    验证 tower_type 合法
    验证 slot_pos 对应塔位为空
    检查玩家金币是否足够
        不足 -> 返回 null
    扣除金币
    实例化塔节点
    添加到对应塔位
    标记 slot 为 occupied
    初始化塔运行逻辑
    发出 tower_placed 信号
    返回 tower 引用

remove_tower(tower_node):
    验证 tower_node 存在
    停止其所有运行时逻辑
    清理关联 buff / 状态
    释放塔位占用
    发出 tower_removed 信号
    queue_free()
```

**MVP 决策**：

- 默认允许 `remove_tower()` 作为系统接口存在
- MVP 可以先不做“主动卖塔按钮”
- 即便 UI 暂时不暴露，也应保留文档级接口，以便后续扩展

### 规则 3：输出塔攻击循环

输出塔共享同一套基本循环：

```text
Idle
  ↓（有目标）
TargetQuery
  ↓（找到目标）
Firing
  ↓
Cooldown
  ↓
TargetQuery
```

伪代码：

```gdscript
func _try_attack() -> void:
    var target = target_system.get_target(
        global_position,
        tower_range,
        target_strategy
    )
    if target == null:
        state = State.Idle
        return

    _fire_at(target)
```

### 规则 4：输出塔效果分支

输出塔不只有“数值伤害”一种成长路线。  
MVP 中允许输出塔在以下方向上分化：

- **纯输出分支**：更高伤害 / 更高攻速 / 更大范围
- **控制分支**：减速、短停顿、穿透、击退等
- **覆盖分支**：散射、多目标、弹丸分裂、持续区域伤害

MVP 第一阶段不需要一次性做全，但文档方向上要明确：

**控制是输出塔的效果维度，不是独立主塔类别。**

### 规则 5：毛线球发射器的当前定位

`yarn_launcher` 当前设计为：

- 本质上是一座输出塔
- 伤害低于标准输出塔
- 命中时附带控制效果（MVP 优先使用减速）

基础示例：

| 参数 | 建议值 |
| ---- | ------ |
| `base_damage` | 8 |
| `tower_range` | 150 |
| `attack_interval` | 1.5s |
| `slow_factor` | 0.7 |
| `slow_duration` | 2.0s |

命中规则：

```text
毛线球命中敌人后：
    造成基础伤害
    施加减速 debuff
    若目标已带减速，则刷新持续时间
```

### 规则 6：辅助塔（catnip_aura）

辅助塔不直接清怪，它的价值在于**放大防线效率**。

`catnip_aura` 的设计方向：

- 不主动攻击
- 对范围内角色与友方塔提供伤害增益
- 鼓励玩家思考“这座辅助塔应该放在哪，才能覆盖关键火力区”

```text
catnip_aura 启动后持续扫描 AuraZone(Area2D)：
    玩家英雄 -> damage_buff += 15%
    范围内输出塔 -> damage_buff += 15%
    目标离开 AuraZone -> 立即移除对应 buff
```

叠加规则：

```text
damage_multiplier = 1.0 + sum(aura_values)
上限建议：1.60
```

设计意图：

- 辅助塔必须有“站位价值”
- 不能是全局被动光环
- 玩家应该通过布局获得收益，而不是只要场上存在就自动吃满

### 规则 7：塔成长接口

塔的成长优先通过以下两种路径实现：

1. **局内经验升级影响塔系统**
2. **塔自身升级接口**

MVP 不要求完整做出“塔单独升级面板”，但文档上保留接口：

```text
upgrade_tower(tower_node, upgrade_type):
    "damage"
    "attack_speed"
    "range"
    "effect"
```

设计原则：

- 优先让升级强化“防线结构”
- 不要只做数字 +5 的无感提升
- 每次升级最好能回答“我的塔现在更擅长什么”

### 规则 8：塔与角色的关系

当前方向里，角色不是替代塔，而是补强塔。

因此角色升级应优先服务这几类联动：

- 提升角色补刀能力，帮助防线度过弱势波
- 提升角色清残血能力，减少漏怪
- 提升角色受辅助塔 buff 后的收益
- 提升角色在关键区的支援价值

不推荐的方向：

- 让角色伤害成长远远超过塔，导致放塔失去意义

---

## Formulas

### 公式 1：标准输出塔 DPS

```text
tower_dps = base_damage / attack_interval × damage_multiplier
```

示例（fish_shooter）：

```text
15 / 1.2 = 12.5 DPS
```

### 公式 2：带辅助塔覆盖时的 DPS

```text
tower_dps = base_damage / attack_interval × (1 + aura_bonus_sum)
```

示例（1 座 catnip_aura 覆盖）：

```text
15 / 1.2 × 1.15 = 14.375 DPS
```

### 公式 3：减速生效

```text
effective_move_speed = base_move_speed × min(all_slow_factors)
```

MVP 建议：

- 多个减速效果不乘法叠加
- 取最强减速，避免控制爆炸

### 公式 4：辅助塔价值判断

```text
aura_value_gain = covered_towers_dps_sum × aura_bonus
```

这条公式的设计意义是：

- 辅助塔的价值来自覆盖到了多少关键火力
- 它不是独立输出点，而是放大器

---

## Edge Cases

| 编号 | 边界情况 | 处理方式 |
| ---- | -------- | -------- |
| EC-01 | 玩家金币不足尝试放塔 | 返回 `null`，不扣钱 |
| EC-02 | 塔位已被占用 | 禁止放置 |
| EC-03 | 弹丸飞行期间目标死亡 | 弹丸自毁或寻找新目标，取决于实现类型 |
| EC-04 | 游戏暂停时塔仍在攻击 | `process_mode = PROCESS_MODE_PAUSABLE`，暂停时停止 |
| EC-05 | 辅助塔覆盖范围内没有友方目标 | 不产生 buff 事件 |
| EC-06 | 多个辅助塔覆盖同一目标 | 加法叠加，但受上限限制 |
| EC-07 | 移除辅助塔时 buff 残留 | 必须同步移除对应目标上的 buff |
| EC-08 | 控制效果过强导致敌人几乎停住 | 通过最小移动速度或效果上限限制 |

---

## Dependencies

### 上游依赖

| 系统 | 依赖类型 | 接口 | 说明 |
| ---- | -------- | ---- | ---- |
| **目标选择系统** | 硬依赖 | `get_target(pos, range, strategy)` | 输出塔选择目标 |
| **伤害计算系统** | 硬依赖 | `calculate_damage(...)` | 统一计算命中伤害 |
| **生命值系统** | 硬依赖 | `HealthComponent.apply_damage(...)` | 伤害落地 |
| **金币系统** | 硬依赖 | 检查/扣除金币 | 放塔与升级消耗 |
| **地图系统** | 硬依赖 | 提供塔位位置与占用状态 | 塔位放置基础 |

### 下游依赖

| 系统 | 依赖类型 | 接口 | 说明 |
| ---- | -------- | ---- | ---- |
| **塔位放置系统** | 硬依赖 | `place_tower()`, `remove_tower()` | 负责实际交互 |
| **升级系统** | 软依赖 | `upgrade_tower(...)` | 强化塔能力或分支效果 |
| **UI系统** | 软依赖 | `tower_placed`, `tower_removed`, `tower_projectile_hit` | 塔位指示、塔信息面板、飘字反馈 |

---

## Tuning Knobs

| 参数名 | 默认值 | 安全范围 | 影响 |
| ------ | ------ | -------- | ---- |
| `fish_shooter.base_damage` | 15 | 5-50 | 输出塔基础强度 |
| `fish_shooter.attack_interval` | 1.2 | 0.5-3.0 | 攻速节奏 |
| `fish_shooter.tower_range` | 180 | 80-300 | 覆盖范围 |
| `yarn_launcher.base_damage` | 8 | 3-20 | 控制型输出塔的基础伤害 |
| `yarn_launcher.slow_factor` | 0.7 | 0.4-0.9 | 控制强度 |
| `yarn_launcher.slow_duration` | 2.0 | 0.5-5.0 | 控制持续时间 |
| `catnip_aura.aura_buff_value` | 0.15 | 0.05-0.30 | 增益强度 |
| `catnip_aura.aura_range` | 120 | 50-250 | 覆盖价值 |
| `tower_costs` | 10 / 15 / 20 | 5-50 | 放塔节奏 |

---

## Acceptance Criteria

### 功能测试

| ID | 测试项 | 验证方式 | Pass 标准 |
| -- | ------ | -------- | -------- |
| AC-TW-01 | 放置标准输出塔 | 调用 `place_tower("fish_shooter", pos)` | 塔成功创建，占用塔位，金币扣除 |
| AC-TW-02 | 放置带控制效果的输出塔 | 调用 `place_tower("yarn_launcher", pos)` | 塔成功创建，攻击循环正常，命中可施加减速 |
| AC-TW-03 | 放置辅助塔 | 调用 `place_tower("catnip_aura", pos)` | 塔成功创建，AuraZone 正常生效 |
| AC-TW-04 | 输出塔造成伤害 | 射程内生成敌人 | 塔发射弹丸并降低敌人 HP |
| AC-TW-05 | 控制效果生效 | 毛线球命中敌人 | 敌人速度下降，并在持续时间后恢复 |
| AC-TW-06 | 辅助塔增益生效 | 输出塔进入 aura 覆盖 | 输出塔伤害提升约 15% |
| AC-TW-07 | 辅助塔增益移除 | 输出塔离开 aura 覆盖 | 输出塔恢复基础值 |
| AC-TW-08 | 金币不足无法放置 | 玩家金币不足时放塔 | 返回 `null`，金币不变 |
| AC-TW-09 | 移除塔 | 调用 `remove_tower(tower)` | 塔节点消失，塔位恢复空闲 |
| AC-TW-10 | 塔成长接口可调用 | 调用 `upgrade_tower(...)` | 塔属性按接口定义发生变化 |

### 集成测试

| ID | 测试项 | Pass 标准 |
| -- | ------ | -------- |
| AC-TW-I01 | 塔 + 金币系统 | 放塔后金币实时变化 |
| AC-TW-I02 | 塔 + 伤害系统 | 命中伤害与计算系统一致 |
| AC-TW-I03 | 塔 + 目标系统 | 输出塔按策略锁定有效目标 |
| AC-TW-I04 | 塔 + 地图系统 | 塔只出现在有效塔位 |
| AC-TW-I05 | 塔 + 升级系统 | 升级能真实改变防线效率 |
| AC-TW-I06 | 塔 + UI 系统 | 放塔、命中、buff 变化都有可见反馈 |

### 设计验证

| ID | 问题 | Pass 标准 |
| -- | ---- | -------- |
| AC-TW-D01 | 塔是否真的是主角 | 一局胜负主要受塔阵结构影响，而不是角色单体强度 |
| AC-TW-D02 | 控制是否必须独立成类 | 即使不单列“控制塔”，玩家依然能感知控制分支存在感 |
| AC-TW-D03 | 辅助塔是否有布局意义 | 放在不同塔位时收益差异明显 |
| AC-TW-D04 | 塔与角色是否有联动 | 角色成长和塔成长同时存在，且互相放大 |
