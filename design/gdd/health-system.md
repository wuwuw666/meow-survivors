# 生命值系统 (Health System)

> **Status**: Approved
> **Author**: [user + agents]
> **Last Updated**: 2026-04-02
> **Implements Pillar**: 成长的爽感（生存压力可感知）+ 可爱即正义（受击反馈可爱）

---

## 1. Overview

生命值系统（Health System）负责管理游戏中所有实体（玩家猫咪英雄和敌人）的当前HP与最大HP。它是所有受伤、死亡、回复逻辑的权威来源：接收来自碰撞检测系统的 `player_hit_by` 信号以扣除玩家HP，接收来自伤害计算系统的最终伤害值以扣除目标HP，同时维护**无敌帧**机制（玩家受击后的短暂无敌窗口，防止连续扣血导致游戏体验崩溃）。当玩家HP归零时，系统触发死亡事件并通知结算系统；当敌人HP归零时，触发击杀事件并通知金币/经验系统进行掉落。此外，系统向UI系统提供HP查询接口以驱动血条显示。

**核心职责**：管理HP状态 → 处理受伤与无敌帧 → 触发死亡事件 → 提供HP查询接口。

---

## 2. Player Fantasy

生命值系统服务的是**"紧绷但不崩溃"**的紧张感，以及**"我变强了，我扛住了"**的成就感。

**情感目标**：生存压力 + 可爱受击反馈

- 玩家血量掉落时，要**感受到危险**——心跳加速，但不绝望。
- 无敌帧不是"无敌金手指"，而是给玩家**一次逃跑的机会**，体现走位技术的价值。
- 受击动画与音效必须符合**"可爱即正义"**支柱——猫咪被打了要发出"喵呜～"的声音而不是惨叫，并有可爱的受击摇晃动画。
- 升级拿到最大HP加成时，血条变长的视觉反馈要**明显且让人爽**。
- 敌人死亡要有**满足感**——HP归零后有小爆炸效果和掉落飞出动画。

**玩家应该感受到**：
- 低血量时的紧张感是刺激而非挫败。
- 无敌帧让"走位"这个技能有价值。
- HP升级后"我变硬了"的可感知变化。

**玩家不应该感受到**：
- 被一群敌人瞬间群殴至死（无敌帧不生效的体验）。
- 不知道自己是否还在无敌帧中（缺乏视觉反馈）。
- 血条变化滞后，感觉系统没响应。

---

## 3. Detailed Design

### Core Rules

#### 规则 1：HP 数据结构

每个有生命值的实体（玩家或敌人）维护以下数据：

| 字段 | 类型 | 说明 |
|------|------|------|
| `current_hp` | int | 当前生命值，范围 \[0, max_hp\] |
| `max_hp` | int | 最大生命值，来自基础值 + 升级加成 |
| `is_dead` | bool | 是否已死亡（HP归零后立即设为 true，防止重复死亡触发） |
| `is_invincible` | bool | 是否处于无敌帧（玩家专属） |
| `invincible_timer` | float | 无敌帧剩余时间（秒） |

HP限制：`current_hp` 始终保持在 `[0, max_hp]` 范围内，不允许溢出。

---

#### 规则 2：受伤流程

```
接收伤害 (damage_value)
    ↓
检查 is_dead → 若已死亡：忽略，直接返回
    ↓
检查 is_invincible → 若在无敌帧中：忽略，直接返回（仅玩家）
    ↓
扣除 HP：current_hp = max(0, current_hp - damage_value)
    ↓
发出 health_changed 信号（供 UI 血条更新）
    ↓
检查 current_hp <= 0
    ├── 是（玩家）→ 触发 player_died 信号 → 通知结算系统
    ├── 是（敌人）→ 触发 enemy_died(enemy) 信号 → 通知金币/经验系统
    └── 否（玩家）→ 激活无敌帧 + 触发受击动画/音效
```

---

#### 规则 3：无敌帧机制（核心设计）

无敌帧（Invincibility Frames，简称 i-frames）是生命值系统最重要的防御性设计，也是玩家走位技术的奖励机制。

**触发条件**：玩家 HP 扣减成功后（即不在无敌帧中且未死亡），立即进入无敌帧。

**无敌帧期间行为**：
- 玩家的 `is_invincible = true`，所有来自敌人的伤害信号被**忽略**（不触发 `take_damage`）。
- 碰撞检测系统继续运行（`player_hit_by` 信号仍然被发出），但生命值系统在收到信号时检查 `is_invincible` 标志并拒绝处理。
- 玩家角色播放**无敌帧闪烁动画**（每隔 0.1 秒交替显示/隐藏，给玩家视觉反馈）。

**无敌帧结束**：
- `invincible_timer` 倒计时归零后，`is_invincible = false`，停止闪烁动画，恢复正常受击状态。

**无敌帧不适用于**：
- 敌人（敌人没有无敌帧，每次被攻击命中都独立扣血）。
- 特殊地图伤害（毒地、陷阱等，若未来引入）可通过 `damage_flags` 标记为穿透无敌帧（v1.0 扩展点，MVP 不实现）。

**设计意图**：
- 防止玩家走进一堆敌人时，多个敌人同帧触发 `player_hit_by` 导致瞬间死亡。
- 无敌时长约 1.0-1.5 秒，足够玩家走位脱离危险，但不足以在敌群中横冲直撞。
- 无敌帧时长 MVP 不随升级改变，保持设计确定性；仅特定升级卡牌可延长（v1.0 扩展点）。

---

#### 规则 4：玩家死亡流程

```
current_hp <= 0 (玩家)
    ↓
is_dead = true（防止重复触发）
    ↓
is_invincible = false（无敌帧强制结束）
    ↓
停止所有游戏物理处理（Physics pause）
    ↓
播放死亡动画（猫咪倒地，爱心消散特效）
    ↓
emit player_died 信号 → 结算系统接收，展示结算面板
```

---

#### 规则 5：敌人死亡流程

```
current_hp <= 0 (敌人)
    ↓
is_dead = true（防止同帧多次攻击重复触发死亡）
    ↓
播放死亡动画（小爆炸 / 消散特效，符合可爱风格）
    ↓
emit enemy_died(enemy: Node) 信号
    ↓
金币/经验系统接收信号 → 在敌人位置生成掉落物
    ↓
敌人节点从场景树移除（queue_free）
```

---

#### 规则 6：HP 回复

MVP 阶段的回复来源：
- **升级加成**：某些升级卡牌直接恢复固定量 HP（立即生效，不超过 `max_hp`）。
- **敌人死亡回血**（特定升级卡牌，v1.0 扩展）：敌人死亡时触发小量回血。

回复公式：`current_hp = min(max_hp, current_hp + heal_amount)`

**不回血的情况**：`is_dead = true` 时无法回血。

---

### States and Transitions

#### 玩家生命值状态机

```
                ┌─────────────────────────────┐
                │          ALIVE               │
                │  (is_dead = false)           │
                │                             │
                │    ┌──────────────────┐     │
                │    │   VULNERABLE     │     │
                │    │ (is_invincible   │     │
                │    │  = false)        │     │
                │    └────────┬─────────┘     │
                │             │               │
                │        受击成功             │
                │             ↓               │
                │    ┌──────────────────┐     │
                │    │  INVINCIBLE      │     │
                │    │ (is_invincible   │     │
                │    │  = true)         │     │
                │    │ 闪烁动画播放中  │     │
                │    └────────┬─────────┘     │
                │             │               │
                │      invincible_timer        │
                │           = 0.0             │
                │             ↓               │
                │    回到 VULNERABLE           │
                └──────────────┬──────────────┘
                               │
                       current_hp <= 0
                               ↓
                ┌─────────────────────────────┐
                │          DEAD               │
                │  (is_dead = true)           │
                │  emit player_died           │
                └─────────────────────────────┘
```

| 状态 | 描述 | 可受伤 |
|------|------|--------|
| **VULNERABLE** | 正常状态，可被伤害 | 是 |
| **INVINCIBLE** | 无敌帧激活，免疫伤害 | 否 |
| **DEAD** | 已死亡，不接受任何输入 | 否 |

#### 敌人生命值状态机（简化）

| 状态 | 描述 |
|------|------|
| **ALIVE** | `current_hp > 0`，正常接受伤害 |
| **DEAD** | `current_hp <= 0`，触发死亡事件，等待移除 |

敌人无无敌帧机制，每次命中独立扣血。

---

### Interactions with Other Systems

| 系统 | 交互方向 | 数据流 | 说明 |
|------|---------|--------|------|
| **碰撞检测系统** | 上游 → 生命值 | `player_hit_by(enemy)` 信号 | 玩家被敌人碰到，触发玩家受伤流程 |
| **伤害计算系统** | 上游 → 生命值 | 调用 `take_damage(target, damage)` | 传入最终伤害值，生命值系统执行扣血 |
| **UI系统** | 生命值 → 下游 | `health_changed(current, max)` 信号 | 驱动玩家血条实时更新 |
| **结算系统** | 生命值 → 下游 | `player_died` 信号 | 玩家死亡，触发游戏结算面板 |
| **金币/经验系统** | 生命值 → 下游 | `enemy_died(enemy)` 信号 | 敌人死亡，通知生成掉落物 |
| **升级选择系统** | 上游 → 生命值 | 调用 `apply_hp_upgrade(bonus_max, bonus_current)` | 升级时修改 `max_hp` 或立即回血 |

---

## 4. Formulas

### 公式 1：受伤后当前HP计算

```
current_hp_after = max(0, current_hp_before - damage_value)
```

**变量定义**：

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `current_hp_before` | int | \[1, max_hp\] | 受伤前的当前HP |
| `damage_value` | int | \[1, +∞) | 由伤害计算系统返回的最终伤害值 |
| `current_hp_after` | int | \[0, max_hp\] | 受伤后的当前HP |

**示例计算**：
- 玩家当前HP=30，受到伤害=15 → `max(0, 30-15) = 15`
- 玩家当前HP=5，受到伤害=20 → `max(0, 5-20) = 0`（死亡触发）

---

### 公式 2：无敌帧时长公式

```
invincible_duration = BASE_INVINCIBLE_DURATION + invincible_bonus
```

**变量定义**：

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `BASE_INVINCIBLE_DURATION` | float（常量） | 1.2 秒 | 基础无敌帧时长，Inspector 可调 |
| `invincible_bonus` | float | 0.0 秒 | 升级卡牌附加无敌时长，MVP 无此类升级，默认0 |
| `invincible_duration` | float | — | 实际无敌帧时长，系统限制范围 \[0.5, 3.0\] 秒 |

**无敌帧倒计时（逐物理帧更新）**：

```gdscript
invincible_timer -= delta
if invincible_timer <= 0.0:
    is_invincible = false
    invincible_timer = 0.0
```

**示例计算（MVP）**：
- 玩家受击，激活无敌帧：`invincible_timer = 1.2`
- 经过 0.5 秒：`invincible_timer = 0.7`，仍在无敌帧
- 经过 1.2 秒：`invincible_timer = 0.0`，`is_invincible = false`，无敌帧结束

---

### 公式 3：最大HP升级加成公式

```
max_hp_new = max_hp_old + bonus_max_hp
current_hp_new = min(max_hp_new, current_hp_old + bonus_current_hp)
```

**变量定义**：

| 变量 | 类型 | 说明 |
|------|------|------|
| `max_hp_old` | int | 升级前的最大HP |
| `bonus_max_hp` | int | 升级卡牌提供的最大HP增量，范围 \[10, 50\] |
| `bonus_current_hp` | int | 升级时立即回复的HP量，MVP 与 `bonus_max_hp` 相同 |
| `max_hp_new` | int | 升级后的最大HP |
| `current_hp_new` | int | 升级后的当前HP（封顶于 `max_hp_new`） |

> **设计说明**：HP升级不按比例换算，而是直接补满差值——符合"成长的爽感"支柱，玩家感受到"升级不仅上限高了，还立刻回了血"。

**示例计算**：
- 当前HP=40，max_hp=100，选择"猫咪强化"（bonus_max_hp=25，bonus_current_hp=25）
- `max_hp_new = 100 + 25 = 125`
- `current_hp_new = min(125, 40 + 25) = 65`

---

### 公式 4：HP回复公式

```
current_hp_after = min(max_hp, current_hp_before + heal_amount)
```

**变量定义**：

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `heal_amount` | int | \[1, max_hp\] | 回复量，由升级卡牌或技能定义 |
| `current_hp_before` | int | \[0, max_hp\] | 回复前当前HP |
| `current_hp_after` | int | \[0, max_hp\] | 回复后当前HP，封顶于 `max_hp` |

**示例计算**：
- 玩家HP=70，max_hp=100，heal=25 → `min(100, 70+25) = 95`
- 玩家HP=90，max_hp=100，heal=25 → `min(100, 90+25) = 100`（封顶）

---

## 5. Edge Cases

| 边界情况 | 处理方式 |
|---------|---------|
| 同一帧多个敌人同时触发 `player_hit_by` | 第一次受击成功，激活无敌帧；后续同帧信号因 `is_invincible=true` 被忽略，仅扣1次血 |
| 玩家在无敌帧期间 HP 回复到满血 | 无敌帧正常倒计时，不提前结束；HP 回复独立处理，不影响无敌帧状态 |
| 敌人被同一帧内两个攻击同时命中 | 两次 `take_damage` 均独立扣血；若第一次已导致 `current_hp=0`，则设置 `is_dead=true`，第二次调用检测到 `is_dead=true` 后直接返回，不重复触发 `enemy_died` |
| `take_damage(damage=0)` 被调用 | 忽略，不触发受伤流程，不激活无敌帧（0伤害不应产生任何副作用） |
| 玩家死亡动画播放期间再次被击中 | `is_dead=true` 时所有 `take_damage` 调用被忽略，死亡流程不重复触发，`player_died` 信号仅发出1次 |
| 敌人死亡后同帧收到第二次伤害 | `is_dead=true` 检查阻止重复死亡，`enemy_died` 信号仅发出1次，不重复掉落 |
| `heal_amount` 为负数（程序错误） | 记录 `push_warning` 日志并忽略此次调用；不当作伤害处理，不崩溃 |
| 无敌帧倒计时在游戏暂停时是否继续 | 无敌帧 timer 在游戏暂停时**暂停倒计时**（节点使用 `PAUSE_MODE_STOP`），恢复游戏后继续计时 |
| 玩家HP已满时选择带回血的升级 | `current_hp` 保持在 `max_hp`，`max_hp` 正常增加；不报错，回血部分被 `min()` 截断 |
| `max_hp` 在 v1.0 中被降低（去除升级） | MVP 中升级不可撤销，暂不处理；预留规则：若 `max_hp` 下降导致 `current_hp > max_hp`，则强制 `current_hp = max_hp` |

---

## 6. Dependencies

### 上游依赖

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **碰撞检测系统** | 硬依赖 | `signal player_hit_by(enemy: Node)` | 玩家与敌人发生碰撞时，碰撞检测系统发出此信号；生命值系统订阅后触发玩家受伤流程 |
| **伤害计算系统** | 硬依赖 | `calculate_damage() -> int` 返回值 | 攻击命中后，调用方先调用伤害计算系统得到最终伤害值，再调用生命值系统的 `take_damage()` |
| **升级选择系统** | 软依赖 | `apply_hp_upgrade(bonus_max_hp, bonus_current_hp)` 调用 | 玩家选择HP相关升级时，调用生命值系统的升级应用接口 |

### 下游依赖

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **UI系统** | 软依赖 | `signal health_changed(current_hp: int, max_hp: int)` | 血条实时更新 |
| **结算系统** | 硬依赖 | `signal player_died` | 玩家死亡时触发，结算系统展示游戏结算面板 |
| **金币/经验系统** | 硬依赖 | `signal enemy_died(enemy: Node)` | 敌人死亡时触发，相关系统在敌人位置生成掉落物 |

### GDScript 接口定义

```gdscript
# ============================================================
# HealthComponent.gd
# 附加到玩家和敌人节点上的生命值组件
# 用法：作为 Node 子节点挂载，在 Inspector 设置 max_hp 和 is_player
# ============================================================
class_name HealthComponent
extends Node

# ---------- 信号（对外发出）----------

## HP 发生变化时发出（受伤、回复、升级均会触发）
## 供 UI 系统订阅以实时更新血条显示
signal health_changed(current_hp: int, max_hp: int)

## 玩家死亡时发出（仅 is_player=true 的实例使用）
## 供结算系统订阅以展示结算面板
signal player_died

## 敌人死亡时发出（仅 is_player=false 的实例使用）
## 供金币/经验系统订阅以生成掉落物
## enemy 参数为敌人的父节点（即敌人 Scene 根节点）
signal enemy_died(enemy: Node)

## 进入无敌帧时发出（供动画系统订阅，播放闪烁动画）
signal invincibility_started

## 退出无敌帧时发出（供动画系统订阅，停止闪烁动画）
signal invincibility_ended

# ---------- 导出变量（数据驱动，Inspector 可调）----------

## 最大生命值基础值
@export var max_hp: int = 100

## 基础无敌帧时长（秒），仅 is_player=true 时生效
## 安全范围：0.5 ~ 3.0 秒
@export var base_invincible_duration: float = 1.2

## 是否是玩家（决定是否启用无敌帧，以及使用 player_died 还是 enemy_died 信号）
@export var is_player: bool = false

# ---------- 运行时状态（只读，不应从外部直接修改）----------

## 当前生命值，范围 [0, max_hp]
var current_hp: int

## 是否已死亡（HP归零后立即设为 true，防止重复死亡触发）
var is_dead: bool = false

## 是否处于无敌帧（玩家专属，is_player=false 时始终为 false）
var is_invincible: bool = false

## 无敌帧剩余时间（秒）
var invincible_timer: float = 0.0

# ---------- 生命周期 ----------

func _ready() -> void:
    current_hp = max_hp

func _physics_process(delta: float) -> void:
    if is_invincible:
        invincible_timer -= delta
        if invincible_timer <= 0.0:
            _end_invincibility()

# ---------- 公开接口 ----------

## 对该实体造成伤害
## damage_value: 由伤害计算系统返回的最终伤害值（正整数）
## 若 damage_value <= 0，忽略调用（不产生任何副作用）
## 若 is_dead=true，忽略调用
## 若 is_player=true 且 is_invincible=true，忽略调用
func take_damage(damage_value: int) -> void:
    if damage_value <= 0:
        return
    if is_dead:
        return
    if is_player and is_invincible:
        return

    current_hp = max(0, current_hp - damage_value)
    health_changed.emit(current_hp, max_hp)

    if current_hp <= 0:
        _on_died()
    elif is_player:
        _start_invincibility()

## 回复生命值（不超过 max_hp）
## heal_amount: 回复量（正整数）
## 若 heal_amount <= 0，记录警告并忽略
## 若 is_dead=true，忽略调用
func heal(heal_amount: int) -> void:
    if heal_amount <= 0:
        push_warning("HealthComponent.heal() called with non-positive value: %d" % heal_amount)
        return
    if is_dead:
        return
    current_hp = min(max_hp, current_hp + heal_amount)
    health_changed.emit(current_hp, max_hp)

## 应用 HP 升级加成（由升级选择系统调用）
## bonus_max_hp: 最大HP增量（正整数）
## bonus_current_hp: 立即回复的HP量（通常与 bonus_max_hp 相同）
func apply_hp_upgrade(bonus_max_hp: int, bonus_current_hp: int) -> void:
    max_hp += bonus_max_hp
    current_hp = min(max_hp, current_hp + bonus_current_hp)
    health_changed.emit(current_hp, max_hp)

## 查询当前 HP（供 UI 系统初始化使用）
func get_current_hp() -> int:
    return current_hp

## 查询最大 HP（供 UI 系统初始化使用）
func get_max_hp() -> int:
    return max_hp

## 查询是否存活
func is_alive() -> bool:
    return not is_dead

## 查询 HP 百分比（0.0 ~ 1.0），供血条渲染使用
func get_hp_ratio() -> float:
    if max_hp <= 0:
        return 0.0
    return float(current_hp) / float(max_hp)

# ---------- 私有方法 ----------

func _start_invincibility() -> void:
    is_invincible = true
    invincible_timer = base_invincible_duration
    invincibility_started.emit()

func _end_invincibility() -> void:
    is_invincible = false
    invincible_timer = 0.0
    invincibility_ended.emit()

func _on_died() -> void:
    is_dead = true
    is_invincible = false
    invincible_timer = 0.0
    if is_player:
        player_died.emit()
    else:
        enemy_died.emit(get_parent())
```

---

## 7. Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 影响的游戏体验 |
|-------|------|-------|---------|--------------|
| `max_hp`（玩家基础） | int | 100 | 60~200 | 基础生存能力；过低玩家开局即死，过高前期无压力感 |
| `base_invincible_duration` | float | 1.2 秒 | 0.5~3.0 秒 | 核心生存窗口；过短=被群怪瞬秒体验极差，过长=可以无脑冲敌群 |
| `hp_upgrade_bonus`（升级卡加成） | int | +25 | 10~50 | 每次HP升级的可感知幅度；过小"感觉没变强"，过大破坏难度曲线 |
| `hp_upgrade_heal`（升级顺带回血） | int | 与 bonus 相同 | 0~bonus | 升级时的即时回血量；=0则纯粹加上限，=bonus则"满状态继续" |

**参数交互说明**：
- `base_invincible_duration` 是全局最重要的"手感"参数。建议在原型阶段优先调试此值至体感合适，再锁定。
- `hp_upgrade_bonus` 应与伤害计算系统的敌人伤害数值协调：若敌人单次伤害约为20，则每次HP升级 ≥20 才能让玩家感受到"多扛住了一刀"。
- `max_hp` 基础值应与难度曲线系统的敌人伤害曲线共同调试，保证第10波在不升级HP的情况下仍有明显的死亡压力。

**极端值测试**：
- `base_invincible_duration = 0.1` → 无敌帧几乎无效，密集敌人场景下玩家体验极差
- `base_invincible_duration = 5.0` → 玩家可以无视敌人密集区，走位策略失去意义
- `hp_upgrade_bonus = 5` → 10次HP升级仅+50 HP，成长感不可感知
- `max_hp = 200`（基础）→ 前期玩家太难死，波次压力消失，挑战感丧失

---

## 8. Acceptance Criteria

### 功能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-HP-01 | 基础受伤扣血 | 对玩家（HP=100）调用 `take_damage(30)` | `current_hp` 变为 70；`health_changed(70, 100)` 信号发出1次 |
| AC-HP-02 | HP下限保护 | 对玩家（HP=10）调用 `take_damage(50)` | `current_hp` 变为 0，不出现负值 |
| AC-HP-03 | 玩家死亡信号 | 对玩家（HP=5）调用 `take_damage(10)` | `player_died` 信号发出恰好1次，`is_dead=true` |
| AC-HP-04 | 敌人死亡信号 | 对敌人（HP=10）调用 `take_damage(15)` | `enemy_died(enemy)` 信号发出恰好1次，信号携带正确的父节点引用 |
| AC-HP-05 | 无敌帧激活 | 玩家受击成功后立即检查状态 | `is_invincible=true`，`invincible_timer` 约等于 1.2（误差 < 0.05） |
| AC-HP-06 | 无敌帧阻挡伤害 | 无敌帧激活中，再次对玩家调用 `take_damage(20)` | HP 不变，`health_changed` 信号不发出，`is_invincible` 仍为 true |
| AC-HP-07 | 无敌帧自动解除 | 等待 1.3 秒后检查状态 | `is_invincible=false`，`invincible_timer=0.0`，`invincibility_ended` 信号已发出 |
| AC-HP-08 | 无敌帧信号发出 | 无敌帧激活时检查信号序列 | `invincibility_started` 信号在受击时发出；`invincibility_ended` 信号在约1.2秒后发出 |
| AC-HP-09 | 基础回复 | 玩家（HP=60，max=100）调用 `heal(20)` | `current_hp=80`，`health_changed(80, 100)` 信号发出1次 |
| AC-HP-10 | 回复上限保护 | 玩家（HP=90，max=100）调用 `heal(50)` | `current_hp=100`，不超过 `max_hp` |
| AC-HP-11 | HP升级应用 | 玩家（HP=70，max=100）调用 `apply_hp_upgrade(25, 25)` | `max_hp=125`，`current_hp=95`，`health_changed(95, 125)` 信号发出1次 |
| AC-HP-12 | HP百分比查询 | 玩家HP=50，max=100 | `get_hp_ratio()` 返回 `0.5`（精确） |
| AC-HP-13 | 死亡后无法受伤 | 玩家死亡（is_dead=true）后再次调用 `take_damage(50)` | HP不变，`player_died` 信号不重复发出，`is_dead` 仍为 true |
| AC-HP-14 | 死亡后无法回复 | 玩家死亡（is_dead=true）后调用 `heal(30)` | HP不变，`health_changed` 信号不发出 |
| AC-HP-15 | 零伤害忽略 | 调用 `take_damage(0)` | HP不变，无敌帧不激活，任何信号均不发出 |
| AC-HP-16 | 负数回复警告 | 调用 `heal(-10)` | 输出 `push_warning` 日志，HP不变，程序不崩溃 |

### 无敌帧专项测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-INV-01 | 同帧多敌人碰撞只扣一次血 | 5个敌人同时对玩家（HP=100）各调用 `take_damage(10)` | `current_hp=90`（仅扣1次），`is_invincible=true`，`health_changed` 信号仅发出1次 |
| AC-INV-02 | 无敌帧期间不重置计时器 | 无敌帧激活（timer=1.2）后0.3秒再次触发受伤逻辑 | `invincible_timer` 约为 0.9（未被重置为1.2） |
| AC-INV-03 | 无敌帧在游戏暂停时停止计时 | 激活无敌帧后立即暂停游戏等待1.5秒，恢复游戏后立即检查 | `invincible_timer` 减少量 < 0.05 秒（近似未计时） |
| AC-INV-04 | 敌人没有无敌帧 | 对敌人（HP=100，is_player=false）连续快速调用3次 `take_damage(10)` | `current_hp=70`（每次独立扣血），`is_invincible` 始终为 false |

### 集成测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-INT-01 | 碰撞检测→生命值集成 | 敌人移动至玩家位置，碰撞检测系统发出 `player_hit_by` 信号 | 生命值系统正确响应，玩家HP下降，`is_invincible=true` |
| AC-INT-02 | 伤害计算→生命值集成 | 攻击命中敌人，伤害计算系统返回值后调用 `take_damage()` | 敌人HP按伤害计算结果准确下降 |
| AC-INT-03 | 生命值→UI集成 | 玩家受伤后检查血条 | UI血条在同帧或下一帧内反映新的HP值，视觉上可见变化 |
| AC-INT-04 | 生命值→结算集成 | 玩家HP归零后计时 | 结算面板在 `player_died` 信号触发后的2秒内展示（包含死亡动画时间） |
| AC-INT-05 | 生命值→掉落集成 | 敌人HP归零后检查场景 | 金币/经验掉落物在 `enemy_died` 信号触发后出现在敌人原始位置（误差 < 5px） |
