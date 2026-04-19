# 自动攻击系统 (Auto-Attack System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 成长的爽感（伤害提升可感知）+ 策略有深度（攻击策略影响战场控制）

## Overview

自动攻击系统是玩家猫咪英雄的**默认攻击行为控制器**。当玩家在场景中移动时，系统以固定冷却间隔自动选择射程内最优目标，调用目标选择系统获取目标，调用伤害计算系统算出伤害值，然后向目标发射弹丸。玩家不需要手动按攻击键——移动即战斗，专注走位策略。

MVP 阶段自动攻击系统实现**单一弹丸攻击**：每经过 `attack_cooldown_sec` 秒，查询射程内的敌人，选到目标后发射一颗弹丸，弹丸命中敌人后通过伤害计算系统和生命值系统完成判定。升级系统可以通过升级卡牌修改攻击频率、伤害、射程、弹丸数量等参数。

**核心职责**：攻击冷却计时 → 目标查询 → 弹丸发射 → 命中判定 → 伤害应用。

**核心接口**:
- `set_attack_data(base_damage: int, attack_range: float, attack_cooldown_sec: float) -> void`
- `signal projectile_hit_enemy(enemy: Node, damage: int)` — 命中时发出

---

## Player Fantasy

自动攻击系统服务 **"成长的爽感"** 支柱的核心部分——玩家升级伤害后，跳出来的伤害数字变大、弹丸变得更大更快更多，这些视觉反馈直接让"变强"具象化。

**情感目标**：**自动化战斗 + 成长可视化**
- 玩家专注走位，攻击自动进行——像有一只可靠的猫咪小保镖在并肩作战
- 升级时能看到攻击力面板数字明显增长，获得"我变强了"的即时反馈
- 伤害数字浮动在敌人头顶，直观反馈每次攻击的效果
- 暴击时伤害数字有特殊效果（更大、变色），制造小惊喜

**玩家应该感受到**:
- "我不需要瞄准，猫咪自己会打——我可以专注躲怪。"
- "我的猫越来越厉害了，跳的数字越来越大！"
- "偶尔来个大数字暴击，好爽！"

**玩家不应该感受到**:
- "我打的是什么？怎么没反应？"（命中延迟过高）
- "敌人就在我面前但猫咪在发呆"（目标选择失败时无声无息）
- "弹丸飞了半秒钟才中，敌人早走了"（弹丸飞行时间过长导致丢失感）

---

## Detailed Design

### Core Rules

#### 规则 1：攻击循环

```
Idle ── 攻击冷却结束 ──→ TargetQuery ── 找到目标 ──→ Firing ── 弹丸发射 ──→ Cooldown ──→ Idle
                         │                            │
                         └── 无目标 ─────────────────→ Idle (下次冷却再试)
```

| 阶段 | 说明 | 持续时间 |
|------|------|---------|
| **Cooldown** | 攻击冷却计时 | attack_cooldown_sec |
| **TargetQuery** | 调用目标选择系统查询射程内敌人 | < 0.5ms（瞬时） |
| **Firing** | 发射弹丸并设置命中回调 | 弹丸飞行时间（取决于 projectile_speed） |
| **Idle** | 等待中（无射程内敌人时停留在此） | 直到下次冷却触发 |

#### 规则 2：冷却计时

```gdscript
func _process(delta: float) -> void:
    if state == State.Cooldown:
        attack_timer += delta
        if attack_timer >= attack_cooldown_sec:
            attack_timer = 0.0
            _try_attack()
```

- 使用累加计时器，保留超额时间防止漂移。
- 游戏暂停时 `delta * time_scale = 0`，计时器自然暂停。

#### 规则 3：攻击流程

```gdscript
func _try_attack() -> void:
    var target = target_system.get_target(
        cat_global_position,
        attack_range,
        TargetSystem.TargetStrategy.NEAREST
    )
    if target == null:
        state = State.Idle
        return

    _fire_at(target)
```

- 每轮冷却结束时尝试一次攻击。
- 无目标时不发射，退回 Idle 等待下次冷却。
- 玩家不需要"确认"——只要射程内有敌人，攻击自动发生。

#### 规则 4：弹丸发射与命中

```gdscript
func _fire_at(target: Node) -> void:
    var data = AttackData.new()
    data.damage_type = "physical"
    data.base_damage = base_damage
    data.damage_multiplier = damage_multiplier
    data.crit_chance = crit_chance
    data.crit_multiplier = crit_multiplier

    # 创建弹丸并设置飞行
    var projectile = projectile_scene.instantiate()
    projectile.target = target
    projectile.speed = projectile_speed
    projectile.on_hit = _on_projectile_hit

    get_parent().add_child(projectile)
    projectile.launch(global_position, target.global_position)

    emit_signal("projectile_fired", projectile)
```

- 弹丸是独立的 Godot 节点，负责自身的飞行移动和碰撞检测。
- 弹丸命中时回调 `_on_projectile_hit(target)`。
- MVP 阶段只有一个弹丸；升级系统可以通过 `projectile_count` 参数发射多弹丸（弹幕升级）。

#### 规则 5：命中伤害计算

```gdscript
func _on_projectile_hit(target: Node) -> void:
    if not is_instance_valid(target):
        return  # 弹丸飞行期间目标已被其他攻击杀死

    var damage: int = DamageSystem.calculate_damage(self, target, attack_data)
    var health_component = target.get_node_or_null("HealthComponent")

    if health_component != null and health_component.is_alive():
        health_component.take_damage(damage)

    if damage > 0:
        emit_signal("enemy_hit", target, damage)
```

- 命中时重新验证目标仍然存活（防止弹丸飞行期间目标已死亡）。
- 伤害应用通过 **damage_calculation → health_system** 链路。
- 不处理弹丸碰撞逻辑——弹丸自身节点负责移动命中。

#### 规则 6：攻击数据变更

```gdscript
func set_attack_data(
    base_damage: int,
    attack_range: float,
    attack_cooldown_sec: float,
    projectile_speed: float = 400.0
) -> void:
    self.base_damage = base_damage
    self.attack_range = max(50.0, attack_range)
    self.attack_cooldown_sec = max(0.1, attack_cooldown_sec)
    self.projectile_speed = max(100.0, projectile_speed)

func apply_attack_speed_bonus(bonus: float) -> void:
    # bonus 为负表示更快（百分比缩减冷却时间）
    attack_cooldown_sec = max(0.1, base_cooldown * (1.0 - bonus))
```

- 所有参数有下限保护，防止设置成 0 或负数导致系统异常。
- 升级系统通过调用 `set_attack_data` 或对应的 bonus 方法修改参数。

---

### States and Transitions

| 状态 | 说明 | 进入条件 | 退出条件 | 行为 |
|------|------|---------|---------|------|
| **Idle** | 等待冷却，无有效目标 | 启动时或上次攻击无目标 | 冷却计时归零 | 不发射弹丸，不查询目标 |
| **Cooldown** | 攻击冷却中 | `_try_attack()` 成功发射或无目标时重置计时 | 计时归零 | `attack_timer` 累加 |
| **TargetQuery** | 查询最优目标 | 冷却结束时 | 找到或没找到目标 | 调用 `target_system.get_target()` |
| **Firing** | 弹丸飞行中 | 弹丸已发射 | 弹丸命中或丢失 | 等待 `projectile.on_hit` 回调 |

```
┌──────┐    cooldown done       ┌────────────┐  has target   ┌────────┐
│ Idle │ ──────────────────────→│ TargetQuery│ ─────────────→│ Firing │
└──────┘                        └─────┬──────┘               └───┬────┘
   ▲                                  │ no target               │ hit/miss
   │                                  │                         │
   │                                  ▼                         │
   │                             ┌──────┐                       │
   └────── next cooldown ────────│ Idle │ ←─────────────────────┘
                                 └──────┘
```

### Interactions with Other Systems

| 系统 | 交互方向 | 数据流 | 说明 |
|------|---------|--------|------|
| **目标选择系统** | 自动攻击 → 目标选择 | `get_target(cat_pos, attack_range)` | 每次攻击冷却结束时查询目标（硬依赖） |
| **伤害计算系统** | 自动攻击 → 伤害计算 | `calculate_damage(attacker, target, attack_data)` | 弹丸命中后计算伤害（硬依赖） |
| **生命值系统** | 自动攻击 → 生命值 | 通过 HealthComponent.take_damage(damage) | 对目标应用最终伤害（硬依赖） |
| **升级选择系统** | 升级 → 自动攻击 | `set_attack_data()`, `apply_damage_bonus()` 等 | 升级修改攻击参数（软依赖，升级时调用） |
| **UI系统** | 自动攻击 → UI | 信号 `projectile_hit_enemy`, `projectile_fired` | 伤害数字显示（软依赖） |

---

## Formulas

### 1. DPS（每秒伤害）公式

```
expected_dps = (base_damage × damage_multiplier / attack_cooldown_sec) × hit_rate × (1 + crit_chance × (crit_multiplier - 1))

其中:
    hit_rate = 弹丸命中率（0.0-1.0），MVP 假设为 1.0（弹丸追踪或速度足够快）
    crit_chance = 暴击概率
    crit_multiplier = 暴击伤害倍率
```

**示例计算（MVP 基础值）**：
```
base_damage = 10
damage_multiplier = 1.0
attack_cooldown = 1.0s
crit_chance = 0.05
crit_multiplier = 1.5
hit_rate = 1.0

expected_dps = (10 × 1.0 / 1.0) × 1.0 × (1 + 0.05 × 0.5)
             = 10 × 1.025
             = 10.25 DPS
```

### 2. 有效射程判断

```
is_in_range = distance_squared(cat_position, target_position) <= attack_range²
```

内部使用平方距离比较，避免 `sqrt()`。

### 3. 弹丸飞行时间

```
flight_time = distance(cat_position, target_position) / projectile_speed

MVP 典型值:
    distance = 150px (中等射程)
    projectile_speed = 400px/s
    flight_time = 150 / 400 = 0.375s

约束:
    max_flight_time = max_range / projectile_speed
    max_range = 200px (升级上限)
    max_flight_time = 200 / 400 = 0.5s (可接受)
```

### 4. 变量汇总

| 变量 | 类型 | 默认值 | 安全范围 | 说明 |
|------|------|--------|---------|------|
| `base_damage` | int | 10 | 1-200 | 基础伤害值 |
| `attack_range` | float | 150.0 | 50-300 | 攻击射程半径（像素） |
| `attack_cooldown_sec` | float | 1.0 | 0.1-5.0 | 攻击冷却间隔（秒） |
| `projectile_speed` | float | 400.0 | 100-800 | 弹丸飞行速度（像素/秒） |
| `damage_multiplier` | float | 1.0 | 0.1-10.0 | 伤害倍率（升级累积） |
| `crit_chance` | float | 0.05 | 0.0-0.5 | 暴击概率 |
| `crit_multiplier` | float | 1.5 | 1.2-3.0 | 暴击伤害倍率 |

---

## Edge Cases

| 编号 | 边界情况 | 触发条件 | 处理方式 |
|------|---------|---------|---------|
| EC-01 | **弹丸飞行期间目标死亡** | 其他攻击先击杀了目标 | 弹丸命中时 `_on_projectile_hit` 检查 `is_instance_valid(target)`，无效则丢弃。弹丸自动消失 |
| EC-02 | **弹丸飞行期间目标离开射程** | 目标移动导致弹丸打空 | 弹丸节点自行处理碰撞检测——未命中任何物体则飞行一段距离后自动销毁（max_flight_distance 或生命周期计时） |
| EC-03 | **冷却结束时目标刚好在边缘** | `distance ≈ attack_range` 的浮点精度问题 | 目标选择系统内部使用平方距离比较，精度足够。即使选到刚好在边缘的敌人，弹丸飞行期间敌人也可能走出去——由弹丸碰撞处理 |
| EC-04 | **攻击频率极高导致弹丸叠帧** | `attack_cooldown < projectile_flight_time` | 允许——弹丸是独立节点，每颗各自飞行。只要弹丸节点有对象池或自动清理，不会累积无限弹丸 |
| EC-05 | **游戏暂停后恢复攻击** | 冷却计时暂停，恢复后继续 | `_process(delta)` 在暂停时 delta=0，计时器不增加，自动正确恢复 |
| EC-06 | **伤害计算系统返回 0** | 目标护甲极高导致伤害为 0 | 伤害系统已保证最小伤害为 1。但防御性检查 `if damage > 0:` 确保 0 伤害不发信号 |
| EC-07 | **玩家选择角色直战升级增加攻击力** | 角色升级面板选择 "+20% 伤害" | 角色升级系统调用 `apply_damage_bonus(0.20)` → `damage_multiplier *= 1.20` |
| EC-08 | **角色升级减少攻击冷却** | 角色升级选择 "+30% 攻击速度" | `attack_cooldown_sec = base_cooldown × (1 - 0.30)`，受 0.1s 下限保护 |
| EC-09 | **玩家死亡后自动攻击** | 玩家 HP 归零 | 波次系统发出 `game_over`，自动攻击系统停止所有计时和发射。已发射的弹丸自然飞行直到命中或消失 |
| EC-10 | **多弹丸同时命中同一目标** | 多弹丸升级（v1.0） | 每次命中独立调用 `_on_projectile_hit`，分别计算伤害。生命值系统的 `is_dead` 检查防止重复死亡信号 |
| EC-11 | **攻击数据尚未初始化就触发冷却** | 系统启动时 `base_damage` 未设置 | 在 `_ready()` 中设置默认 `base_damage = 10`。若被 override 修改则以后续设置为准 |
| EC-12 | **敌人卡在不可达区域** | 弹丸追踪不到目标 | 弹丸设置最大飞行距离 `max_distance = attack_range × 2`，超出后自动销毁 |

---

## Dependencies

### 上游依赖（自动攻击系统依赖的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **目标选择系统** | 硬依赖 | `get_target(origin, range, strategy) -> Node` | 每次攻击冷却结束时调用 |
| **伤害计算系统** | 硬依赖 | `calculate_damage(attacker, target, attack_data) -> int` | 弹丸命中后调用 |
| **生命值系统** | 硬依赖 | `health_component.take_damage(damage)` | 对目标应用伤害 |

### 下游依赖（依赖自动攻击系统的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **升级选择系统** | 软依赖 | `set_attack_data()`, `apply_damage_bonus()`, `apply_attack_speed_bonus()` | 角色升级修改自动攻击参数 |
| **UI系统** | 软依赖 | 信号 `projectile_hit_enemy(target, damage, is_crit)` | 伤害数字飘字显示 |
| **音频系统** | 软依赖 | 信号 `projectile_fired`, `projectile_hit` | 发射/命中音效 |

### GDScript 接口定义

```gdscript
# ============================================================
# AutoAttackSystem.gd
# 猫咪英雄的自动攻击控制器
# 挂载在猫咪 Hero 节点上
# ============================================================
class_name AutoAttackSystem
extends Node

# ---------- 信号 ----------
signal projectile_fired(projectile: Node)
signal projectile_hit_enemy(enemy: Node, damage: int, is_crit: bool)

# ---------- 导出变量 ----------
## 基础伤害值
@export var base_damage: int = 10

## 攻击射程（像素）
@export var attack_range: float = 150.0

## 基础攻击冷却间隔（秒）
@export var base_cooldown: float = 1.0

## 弹丸飞行速度（像素/秒）
@export var projectile_speed: float = 400.0

## 弹丸场景路径
@export var projectile_scene: PackedScene

# ---------- 运行时状态 ----------
enum State { Idle, Cooldown, TargetQuery, Firing }
var state: State = State.Idle
var attack_timer: float = 0.0
var attack_cooldown_sec: float = 1.0
var damage_multiplier: float = 1.0
var crit_chance: float = 0.05
var crit_multiplier: float = 1.5

# ---------- 系统引用 ----------
var target_system: Node = null

# ---------- 公开 API ----------
func _try_attack() -> void
func set_damage_bonus(bonus: float) -> void
func set_attack_speed_bonus(bonus: float) -> void
func set_crit_chance(new_chance: float) -> void
func set_crit_multiplier(new_mult: float) -> void
func get_current_dps() -> float
```

---

## Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 影响的游戏体验 |
|--------|------|--------|---------|--------------|
| `base_damage` | int | 10 | 1-200 | 前期击杀时间的基准值。过低导致前几波打怪像刮痧；过高导致前几波太简单 |
| `attack_range` | float | 150.0 | 50-300 | 猫咪攻击覆盖范围。过小导致"贴脸才打"的不爽感；过大覆盖半个地图导致策略失去意义 |
| `base_cooldown` | float | 1.0 | 0.1-5.0 | 攻击节奏感的核心参数。过慢（>2s）玩家感觉猫在发呆；过快（<0.3s）弹丸满天飞性能爆炸 |
| `projectile_speed` | float | 400.0 | 100-800 | 弹丸飞行手感。过低弹丸"飘"像纸片；过高弹丸像激光看不到飞行过程 |
| `crit_chance` | float | 0.05 | 0.0-0.5 | 惊喜感频率。0=没惊喜；0.5=太频繁失去惊喜感 |
| `crit_multiplier` | float | 1.5 | 1.2-3.0 | 暴击爽感量。越低越平淡；越高越不平衡 |

**参数交互**：
- `base_damage` 与难度曲线系统的敌人 HP 曲线共同调试。第 1 波 basic_melee 敌人 HP 应能在约 6-8 次攻击内被击杀。
  - 第 1 波 enemy_hp = base_hp × hp_multiplier = 30 × 1.0 = 30
  - 以 base_damage = 10, damage_multiplier = 1.0 计算：3 次击杀 → 偏快
  - **建议**：初始 base_damage = 5-7，让前几波每只怪需要 5-8 次攻击，给升级留出提升感
- `base_cooldown` 与 enemy spawn_interval 共同形成攻守节奏——攻击间隔应明显短于刷怪间隔（1.0s vs 1.2s），让玩家在刷怪间隙有输出窗口。
- `projectile_speed` ≥ 300 以确保 max_range=200 下飞行时间 < 0.67s——玩家不会觉得"猫在打空气"。

---

## Visual/Audio Requirements

### 弹丸视觉
- MVP：可爱小肉球（粉色圆形，直径 8-12px），带拖尾粒子
- 暴击弹丸：变色（白色/金色）+ 更大的撞击粒子效果
- 弹丸命中敌人时：小爆散粒子 + 伤害数字飘出

### 攻击冷却反馈
- 无冷却时的"Ready"提示：猫咪攻击动画有一个蓄力动作
- 冷却期间：猫咪处于待机状态，不播放攻击动画

### 音效
- **发射音**：可爱的"喵~"或短促弹丸音效（< 0.2s）
- **命中音**：轻微的"嘭"或"噗"声（< 0.1s）
- **暴击音**：比普通命中更响/更亮的音效
- 命中音频率需要控制——当 50+ 敌人同时被打击时，音效不应洪水般堆叠（使用音量/频率限幅器）

---

## UI Requirements

| UI 元素 | 触发时机 | 内容 |
|---------|---------|------|
| 伤害飘字 | `projectile_hit_enemy` 信号 | 数字（红色普通/黄色暴击），从敌人头顶飘出，1 秒后消失 |
| 暴击特效 | `is_crit == true` | 额外闪光/星星粒子围绕命中点 |
| 攻击力面板 | HUD 统计面板（可选） | 显示当前 DPS、暴击率等 |

---

## Acceptance Criteria

### 功能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-AA-01 | 基础攻击循环 | 猫咪启动，射程内有 1 个静止敌人 | 每 1 秒发射一颗弹丸，命中敌人并造成伤害 |
| AC-AA-02 | 无目标时不发弹丸 | 射程内无任何敌人 | 冷却计时器正常走动但不发射弹丸，无弹丸实例生成 |
| AC-AA-03 | 目标选择 NEAREST | 射程内 3 个不同距离敌人 | 弹丸始终飞向最近的敌人（distance_sq 最小） |
| AC-AA-04 | 伤害计算链路 | 攻击命中敌人，检查 HP 变化 | 敌人 HP 下降值 = DamageSystem.calculate_damage() 返回值 |
| AC-AA-05 | 伤害数字显示 | 命中时观察 UI 飘字 | 红色伤害数字出现从敌人头顶飘出，数值与计算伤害一致 |
| AC-AA-06 | 暴击触发统计 | 设 crit_chance = 1.0，攻击 10 次 | 10 次全部暴击，黄色大数字暴击飘字 10 次 |
| AC-AA-07 | 角色升级修改伤害 | 调用 `apply_damage_bonus(0.50)`，攻击敌人 | 伤害从 base 10 变为 15，DPS 提升 50% |
| AC-AA-08 | 角色升级修改攻击速度 | 调用 `set_attack_speed_bonus(0.50)`，测量 10 次发射间隔 | 平均间隔 ≈ 0.5s（vs 原 1.0s），误差 < 0.05s |
| AC-AA-09 | projectile_hit_enemy 信号 | 监听信号 | 每次弹丸命中敌人时发出恰好 1 次信号，参数为 (enemy_node, damage_value, is_crit) |

### 边界测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-AA-10 | 弹丸飞行期间目标死亡 | 用其他攻击先击杀目标，弹丸到达目标原位置 | 弹丸不触发伤害，无崩溃，飘字不出现 |
| AC-AA-11 | 目标离开射程 | 敌人移动离开射程，弹丸追上 | 弹丸未命中任何目标后自动销毁（生命周期或距离耗尽） |
| AC-AA-12 | 游戏暂停恢复 | 冷却 0.5s 时暂停游戏 10 秒，恢复后计时 | 恢复后还需约 0.5s 才发射（而非立即发射），暂停期间不推进计时 |
| AC-AA-13 | 极高攻击频率 | 设 cooldown = 0.15s，运行 30 秒 | 不崩溃，弹丸数量可控，帧率无明显下降 |
| AC-AA-14 | 同目标被多弹丸命中 | 多弹丸升级后，3 颗弹丸几乎同时命中同一敌人 | 每次独立造成伤害，敌人死亡后后续弹丸命中不再触发伤害或信号 |
| AC-AA-15 | 攻击数据为 0 或负 | 设 base_damage = 0 | 不发射弹丸或发射但不产生伤害效果（防御性处理） |

### 性能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-AA-P01 | 目标选择耗时 | 100 敌人场景，记录 get_target() 耗时 | < 0.5ms/次 |
| AC-AA-P02 | 弹丸实例化性能 | 0.5s cooldown, 运行 60 秒 | 总弹丸数 120，所有弹丸正确销毁，帧率 ≥ 55 FPS |
| AC-AA-P03 | 密集命中场景 | 50 敌人 + 猫咪持续攻击 30 秒 | 伤害计算 + 血条更新总帧开销 < 1ms/帧 |

### 集成测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-AA-I01 | 目标系统集成 | 猫咪启动后自动攻击射程内敌人 | 弹丸准确飞向最近敌人，命中伤害正确 |
| AC-AA-I02 | 伤害系统集成 | 弹丸命中后检查敌人 HP 变化 | 伤害值 = damage_system.calculate_damage() 返回，HP 下降对应值 |
| AC-AA-I03 | 角色升级系统集成 | 通过角色升级面板选择"+30% 伤害" | 后续攻击伤害提升约 30%（向下取整差异可能 ±1） |
| AC-AA-I04 | UI 伤害数字集成 | 弹丸命中敌人 | UI 飘字出现且数值匹配，暴击时有黄色特效 |

---

## Open Questions

| # | 问题 | 影响范围 | 建议方案 | 决策时间 |
|---|------|---------|---------|---------|
| OQ-01 | 弹丸是否追踪目标（homing）还是直线飞行？ | 弹丸碰撞设计 | **MVP 直线飞行**——弹丸沿发射方向以 projectile_speed 直线移动，超出射程 ×2 后自动销毁。v1.0 可以添加追踪弹丸升级卡。 | 当前确认 |
| OQ-02 | 猫咪是否需要"攻击动画"？ | 可爱感 | **MVP 做简易攻击动画**——发射时猫咪小幅度前倾/挥爪（0.2s），增加可爱感。但不做复杂骨骼动画。 | 原型验证后 |
| OQ-03 | 多弹丸（散射/弹幕）升级到什么程度？ | 平衡性、性能 | v1.0 扩展，MVP 单一弹丸。设计上预留 `projectile_count` 参数，后续支持 2-5 弹丸散射。散射角度 15-45° 可调。 | v1.0 阶段 |
| OQ-04 | base_damage 初始值到底是 10 还是 5？ | 数值平衡 | 建议初始 5-7，让敌人击杀需要 5-8 次攻击，给升级留出 2-3 个 tier 的明显提升感。10 太快导致前几波毫无压力。需通过原型 playtest 校准。 | 原型校准 |
| OQ-05 | 弹丸碰撞使用哪种 Godot 碰撞机制？ | 技术实现 | **MVP 使用 Area2D + body_entered 信号**——简洁、适合弹丸-敌人碰撞。如果性能不足（50+ 弹丸同时存在），改用手动距离检查。 | 原型验证后 |
