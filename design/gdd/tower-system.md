# 防御塔系统 (Tower System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 策略有深度（塔类型选择 + 塔位决策）+ 成长的爽感（塔升级可感知）

## Overview

防御塔系统（Tower System）管理游戏中所有已放置防御塔的运行时行为。玩家通过消耗金币在地图固定塔位上放置防御塔，塔自动攻击射程内敌人或为范围内友方提供增益。MVP 包含 3 种塔：小鱼干发射器（单体攻击）、毛线球发射器（范围减速控制）、猫薄荷光环塔（伤害加成辅助）。每座塔独立运行，拥有目标选择、冷却计时、伤害输出能力，是玩家策略的核心延伸。

**核心职责**: 塔数据定义 → 放置/移除 → 攻击循环 → 光环效果 → 升级接口

**核心接口**:
- `place_tower(tower_type: String, slot_pos: Vector2) -> Node`
- `remove_tower(tower_node: Node) -> void`
- `signal tower_placed(tower: Node, tower_type: String, slot_pos: Vector2)`
- `signal tower_projectile_hit(enemy: Node, damage: int, tower_type: String)`
- `get_tower_data(tower_type: String) -> Dictionary`

---

## Player Fantasy

**情感目标：策略延伸的安心感 + 防线成型的满足感**

塔是玩家"不在身边时的保险"——当玩家被怪追着跑远离某个区域时，塔仍在那里输出。放置位置和类型选择是策略的核心乐趣——"这里放减速、那里放输出、中间放加成"组成完整防线。

**玩家应该感受到**:
- "这个路口放攻击塔，那边放减速——我的防线开始成型了"
- "我走了但塔还在打——我的策略在自动执行"
- "两座塔配合得好强，一个减速一个群殴"
- 升级塔后射速/伤害/范围明显变化，视觉和数字上都有反馈

**玩家不应该感受到**:
- "塔打不到敌人？光发呆？"（射程或目标选择问题）
- "这塔跟那塔有什么区别？"（类型同质化）
- "塔伤害太低了，放不放都一样"（数值过低失去意义）
- "金币花完就没法继续放塔"（塔太贵导致策略无法执行）

**参考**: 植物大战僵尸（类型清晰、决策有意义）、Kingdom Rush（升级路线清晰、类型互补）

---

## Detailed Rules

### 规则 1：塔类型定义（MVP 3 种）

| 类型 ID | 名称 | 类别 | 伤害 | 射程 (px) | 攻击间隔 (s) | 特殊效果 | 放置费用 |
|---------|------|------|------|-----------|-------------|---------|---------|
| `fish_shooter` | 小鱼干发射器 | 攻击型 | 15 | 180 | 1.2 | 单体单体高伤害 | 10 金币 |
| `yarn_launcher` | 毛线球发射器 | 控制型 | 8 | 150 | 1.5 | 命中减速30%, 持续2s | 15 金币 |
| `catnip_aura` | 猫薄荷光环塔 | 辅助型 | 0 | 120 | 无 | 范围内友方伤害+15% | 20 金币 |

**说明**:
- 攻击塔（fish_shooter）: 主力输出, 高伤攻速快但只能单体
- 控制塔（yarn_launcher）: 伤害低但有减速效果, 减缓敌人推进速度
- 辅助塔（catnip_aura）: 不直接攻击, 为范围内的玩家/其他塔提供伤害增益

所有塔的属性值来自 `TOWER_DATA` 字典（MVP 内联, v1.0 移至 `assets/data/tower_data.json`）。

### 规则 2：塔放置与移除流程

```
place_tower(tower_type, slot_pos):
    验证 tower_type 有效 (在 TOWER_DATA 中存在)
    检查玩家金币 >= 放置费用
        否 → 返回 null, 不放
    扣除对应金币
    加载对应塔 Scene, 实例化 Node
    设置 global_position = slot_pos
    添加到 "tower" Group
    根据类型初始化:
        攻击/控制塔: 启动攻击循环 (state = COOLDOWN)
        辅助塔: 启动光环扫描 (state = ACTIVE)
    发出 tower_placed(tower, tower_type, slot_pos) 信号
    返回 tower 引用

remove_tower(tower_node):
    验证 tower_node 存在
    停止所有运行时逻辑 (攻击循环/光环扫描)
    发出 tower_removed(tower_node) 信号
    queue_free() 除节点
    # MVP 不返还金币；v1.0 可设计为返还 50%
```

### 规则 3：攻击循环（攻击塔/控制塔）

**状态机**:
```
Idle ←── 无目标 ─── TargetQuery ←── cooldown 归零 ── Cooldown
  │                                    │
  │ 有目标                              │ 再次冷却
  ▼                                    │
Firing ── 弹丸命中/丢失 ──→ Cooldown ──┘
```

```gdscript
# 伪代码: 塔攻击循环 (同自动攻击系统, 但归属塔节点独立运行)
func _try_attack() -> void:
    var target = target_system.get_target(
        global_position,
        tower_range,
        target_strategy  # 由塔类型定义
    )
    if target == null:
        state = State.Idle
        return
    _fire_at(target)
```

**目标选择策略** (由塔类型定义):
- `fish_shooter`: `NEAREST` (打最近的怪, 减少溢出伤害浪费)
- `yarn_launcher`: `HIGHEST_HP` (优先减速肉盾, 减缓推进速度)

### 规则 4：减速效果 (yarn_launcher)

```
弹丸命中敌人后:
    slow_factor = min(current_slow, 0.7)   # 取更小值 (减速叠加不乘积)
    slow_duration = 2.0s
    slow_timer = 2.0s  (刷新计时)
    敌人移动速度 = base_move_speed × slow_factor
slow_timer <= 0:
    slow_factor = 1.0  (恢复)
```

- 多座毛线球塔命中同一敌人: 取最小 slow_factor (不会无限减速)
- 减速效果由塔节点记录在 debuff 字典中, 敌人系统查询并应用

### 规则 5：光环效果 (catnip_aura)

```
catnip_aura 塔启动后持续:
    查找 AuraZone(Area2D) 内所有目标:
        - 玩家英雄 -> damage_buff += 15%
        - 其他塔 -> damage_buff += 15%
    目标离开 AuraZone -> 立即移除增益(恢复原有伤害)

多座 catnip_aura 塔覆盖同一目标:
    damage_buff 加法叠加 (2座=+30%, 3座=+45%)
    上限: +60% (即最多4座有效)
```

光环增益通过信号通知:
- `emit aura_buff_applied(target: Node, buff_type: String, value: float)`
- `emit aura_buff_removed(target: Node, buff_type: String)`

伤害计算系统读取目标的当前 buff 值计算最终伤害。

### 规则 6：塔升级

```
每座塔 level = 0-3:
    level 0 -> 1: 伤害 +20%, 费用 5 金币
    level 1 -> 2: 攻速 +15% 或射程 +10% (二选一), 费用 8 金币
    level 2 -> 3: 特殊效果增强, 费用 12 金币
        fish_shooter: 附加弹道变为散射2颗
        yarn_launcher: 减速 30% -> 40%
        catnip_aura: 光环 +15% -> +20%

升级调用:
    upgrade_tower(tower_node, upgrade_type: String) -> void
    upgrade_type: "damage" / "attack_speed" / "range" / "effect"
```

---

## Formulas

### 公式 1：塔 DPS

```
tower_dps = base_damage / attack_interval × (1 + damage_buff_from_aura)

示例 (fish_shooter, 无光环):
    = 15 / 1.2 × 1.0 = 12.5 DPS

示例 (fish_shooter, 1座光环塔覆盖):
    = 15 / 1.2 × 1.15 = 14.375 DPS

示例 (fish_shooter, 2座光环塔覆盖):
    = 15 / 1.2 × 1.30 = 16.25 DPS
```

### 公式 2：减速叠加

```
effective_move_speed = base_move_speed × min(all_slow_factors)

2座 yarn_launcher 同时命中: min(0.7, 0.7) = 0.7 (不叠加)
敌人实际速度降至 70%
```

### 公式 3：光环叠加

```
damage_multiplier = 1.0 + sum(aura_values)
上限: damage_multiplier <= 1.60
```

### 公式 4：变量汇总

| 变量 | 类型 | 默认值 | 安全范围 | 说明 |
|------|------|--------|---------|------|
| `base_damage` | int | 15 | 1-100 | 塔基础伤害 |
| `attack_interval` | float | 1.2 | 0.3-5.0 | 击间隔(秒) |
| `tower_range` | float | 180.0 | 50-300 | 射程(像素) |
| `slow_factor` | float | 0.7 | 0.3-1.0 | 减速乘数(越小越慢) |
| `slow_duration` | float | 2.0 | 0.5-5.0 | 减速持续时间(秒) |
| `aura_buff_value` | float | 0.15 | 0.05-0.30 | 光环伤害加成 |
| `aura_range` | float | 120.0 | 50-250 | 光环范围(像素) |

---

## Edge Cases

| 编号 | 边界情况 | 处理方式 |
|------|---------|---------|
| EC-01 | 弹丸飞行期间目标死亡 | 命中时检查 `is_instance_valid(enemy)`, 无效则弹丸自毁 |
| EC-02 | 塔位上已有塔 | 地图系统确保一个slot只放一座塔; `place_tower` 前检查 slot 是否空闲 |
| EC-03 | 玩家金币不足以放置 | 返回 null, 不扣费; UI 应提示金币不足 |
| EC-04 | 目标在弹丸发出后移出射程 | 弹丸追踪(homing)或直线飞行超距后自毁 |
| EC-05 | 游戏暂停时塔 | `process_mode = PROCESS_MODE_PAUSABLE`, 升级面板弹出时停止攻击循环, 视觉冻结 |
| EC-06 | 敌人卡在塔碰撞体上 | 敌人绕过塔(物理分离); MVP 敌人不做攻击塔行为, 不造成塔损坏 |
| EC-07 | 多座塔同时瞄准同一目标 | 允许, 各自独立计算伤害; 敌方死亡后其他塔下次冷却重新选目标 |
| EC-08 | 光环覆盖区域无友方目标 | 不发出 `aura_buff_applied` 信号, 不产生计算开销 |

---

## Dependencies

### 上游依赖（塔系统依赖的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **目标选择系统** | 硬依赖 | `get_target(pos, range, strategy) -> Node` | 攻击塔/控制塔每次冷却结束时调用 |
| **伤害计算系统** | 硬依赖 | `calculate_damage(tower, enemy, attack_data) -> int` | 塔弹丸命中后调用 |
| **生命值系统** | 硬依赖 | `HealthComponent.take_damage(damage)` | 对敌人应用伤害 |
| **金币系统** | 硬依赖 | 检查/扣除玩家金币 | 放置和升级时消耗 |
| **地图系统** | 硬依赖 | 提供塔位位置列表 | 塔的放置位置由地图决定 |

### 下游依赖（依赖塔系统的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **塔位放置系统** | 硬依赖 | `place_tower()`, `remove_tower()` | 调用塔系统 API 完成放置/移除 |
| **升级选择系统** | 软依赖 | `upgrade_tower(tower, type)` | 升级卡修改塔属性 |
| **UI系统** | 软依赖 | `tower_placed`/`tower_projectile_hit` 信号 | 塔信息面板、伤害飘字 |
| **金币系统** | 软依赖 | 监听放置/升级事件 | 扣除金币, 发出金币变化信号 |

---

## Tuning Knobs

| 参数名 | 默认值 | 安全范围 | 影响 |
|--------|--------|---------|------|
| `fish_shooter.base_damage` | 15 | 5-50 | 主力塔伤害; 低于10打不动, 高于30秒杀小兵无策略 |
| `fish_shooter.attack_interval` | 1.2 | 0.5-3.0 | 攻速; <0.8弹丸满天飞, >2.0感觉塔在发呆 |
| `fish_shooter.tower_range` | 180 | 80-300 | 覆盖; 过大覆盖半个地图无放置策略, 过小容易空放 |
| `yarn_launcher.slow_factor` | 0.7 | 0.4-0.9 | 减速幅度; <0.5敌人走不动, >0.8.5几乎没感觉 |
| `yarn_launcher.slow_duration` | 2.0 | 0.5-5.0 | 减速持续; <1s 刚减速就恢复, >4s等于永久减速 |
| `catnip_aura.aura_buff_value` | 0.15 | 0.05-0.30 | 伤害加成; <8%玩家感觉不到, >35%太OP |
| 塔放置费用(3种) | 10/15/20 | 5-50 | 费用过低玩家随意放, 过高策略选择失去意义 |
| 塔升级费用梯度 | 5/8/12 | — | 每级递增但增幅不超2x |

**参数交互**:
- `fish_shooter DPS = 12.5` vs 敌人 HP: 第1波 normal_a(HP=30) 约 2.4s 击杀(2次命中), 符合预期
- `catnip_aura +15%` × `fish_shooter DPS`: 从 12.5 → 14.4, 约+15%, 放置辅助塔的代价(不产生直接伤害)vs 其他塔+30%伤害的权衡有意义
- 塔放置费用 vs 金币收入: MVP每只怪掉落~2金币, `fish_shooter` 放置需要 5 只怪的金币; 第1波约刷10只, 玩家可以在第2波前放置1座塔

---

## Acceptance Criteria

### 功能测试

| ID | 测试项 | 验证方法 | Pass标准 |
|----|-------|---------|---------|
| AC-TW-01 | 放置攻击塔 | 调用 `place_tower("fish_shooter", (400,300))`, 玩家有足够金币 | 塔节点存在于 (400,300), 进入 COOLDOWN 状态, 金币被扣除 |
| AC-TW-02 | 放置控制塔 | 调用 `place_tower("yarn_launcher", (400,300))` | 塔节点存在, 攻击循环启动, 弹丸带减速属性 |
| AC-TW-03 | 放置辅助塔 | 调用 `place_tower("catnip_aura", (400,300))` | 塔节点存在, `AuraZone` 激活, 立即扫描范围内友方目标 |
| AC-TW-04 | 攻击塔输出伤害 | 塔射程内放入敌人, 等待冷却结束 | 塔发射弹丸, 命中敌人, 敌人HP下降=calculate_damage返回值 |
| AC-TW-05 | 控制塔减速 | yarn弹丸命中敌人 | 敌人速度降为base×0.7, 2s后恢复 |
| AC-TW-06 | 辅助塔增益 | catnip_aura范围内放入玩家/其他塔 | 范围内的玩家/塔伤害输出提升约15% |
| AC-TW-07 | 光环超出范围移除增益 | 玩家移出catnip_aura范围 | 玩家伤害恢复为基础值 |
| AC-TW-08 | 金币不足无法放置 | 玩家金币<15时尝试放置yarn_launcher | 返回null, 金币不变动 |
| AC-TW-09 | 移除塔 | `remove_tower(tower_node)` | 塔节点被queue_free, slot变回空闲 |
| AC-TW-10 | 塔升级 | `upgrade_tower(tower, "damage")` | 塔base_damage×1.2, level+1, 金币被扣除 |
| AC-TW-11 | 减速不叠加 | 2座yarn_launcher同时命中同一敌人 | slow_factor = 0.7(不叠乘), 非0.49 |
| AC-TW-12 | 光环加法叠加 | 2座catnip_aura覆盖玩家 | 玩家伤害加成 = 1.0+0.15+0.15 = 1.30(+30%) |
| AC-TW-13 | 多塔选目标策略 | fish_shooter射程内3个敌人 | 打最近的(NEAREST策略) |
| AC-TW-14 | yarn选最高HP | yarn_launcher射程内3个敌人 | 打HP最高的(HIGHEST_HP策略) |

### 集成测试

| ID | 测试项 | 验证方法 | Pass标准 |
|----|-------|---------|---------|
| AC-TW-I01 | 塔+金币系统集成 | 放置塔 | 对应金币扣除, HUD金币数实时更新 |
| AC-TW-I02 | 塔+伤害系统集成 | 塔弹丸命中 | 敌人HP下降=calculate_damage返回, 伤害飘字出现 |
| AC-TW-I03 | 塔+目标系统集成 | 攻击塔自动射 | 弹丸飞向目标选择系统返回的最优敌人 |
| AC-TW-I04 | 塔+地图系统集成 | 塔位放置系统调用place | 塔出现在地图指定slot位置, slot标记为occupied |
| AC-TW-I05 | 塔+升级系统集成 | 通过升级面板选择"塔伤害+20%" | 塔后续攻击伤害提升~20%, level从0变1 |
| AC-TW-I06 | tower_projectile_hit信号 | 监听信号 | 每次弹丸命中发出恰好1次, 参数(enemy, damage, tower_type)正确 |

### 性能测试

| ID | 测试项 | Pass标准 |
|----|-------|---------|
| AC-TW-P01 | 3座塔同时运行(50敌人) | 每帧塔计算总开销<0.5ms, 帧率≥55FPS |
| AC-TW-P02 | 弹丸实例管理 | 3座攻击塔×0.5s冷却×60s运行时弹丸总数正确, 无内存泄漏 |
