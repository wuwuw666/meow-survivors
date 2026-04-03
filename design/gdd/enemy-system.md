# 敌人系统 (Enemy System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-02
> **Implements Pillar**: 可爱即正义（敌人外形可爱）+ 成长的爽感（敌人被击杀有满足感）+ 策略有深度（敌人类型差异影响决策）

---

## 1. Overview

敌人系统（Enemy System）负责管理游戏中所有敌人的运行时行为，包括：定义每种敌人类型的属性数据（HP、移动速度、伤害、碰撞半径等），驱动敌人朝向玩家英雄移动（简单追踪AI），处理敌人与英雄的碰撞检测关系，以及处理敌人死亡时的后续事件链（触发掉落物生成）。

本系统中每个敌人实例是一个 `CharacterBody2D` 节点，附加 `HealthComponent`（由生命值系统定义）管理血量。敌人没有独立的"攻击"行为——敌人通过碰撞接触英雄，由碰撞检测系统发出 `player_hit_by(enemy)` 信号，交由生命值系统处理玩家受伤。这种职责分离确保碰撞检测是单一真理源，生命值系统统一处理扣血逻辑。

MVP 包含 5 种敌人：3 种普通变体（不同 HP/速度组合）、1 种精英（高HP/中等掉落）、1 种 Boss（极高HP、简单特殊行为）。所有敌人使用圆形碰撞体，彼此之间不重叠（使用 `move_and_slide()` 实现基础分离）。

**核心职责**：定义敌人属性数据 → 每帧移动追踪英雄 → 碰撞接触时触发伤害链 → 死亡时通知下游系统 → 管理敌人生命周期。

**核心接口**：
- `signal enemy_spawned(enemy: Node)` — 敌人实例化后发出，供波次/生成系统追踪
- `signal enemy_reached_hero(enemy: Node)` — 敌人接触英雄后发出（供音效/动画订阅）
- `move_toward_hero(delta: float) -> void` — 每帧调用，驱动敌人向英雄移动
- `get_enemy_type() -> String` — 返回敌人类型标识（normal_a / normal_b / normal_c / elite / boss）
- `get_data() -> Dictionary` — 返回当前敌人的完整属性数据

---

## 2. Player Fantasy

**情感目标：可爱的威胁 + 击杀满足感 + 类型识别的清晰感**

敌人系统是**反差体验**的核心载体——外表毛茸茸、圆滚滚的可爱小怪物，却在不断逼近玩家造成紧迫的生存压力。这种"可爱但危险"的反差感是游戏最独特的体验。

**玩家应该感受到**：
- 看到敌人从屏幕边缘涌来 → "好多小可爱冲过我来了"——不恐惧，但有紧迫感。
- 不同敌人有不同移动速度——快速小兵"跑得快但脆"，重装怪"走得慢但很硬"，一眼就能识别威胁优先级。
- 击杀敌人后的掉落物飞出 + 死亡动画 → 满足感 + "清理得干干净净"。
- Boss 出场有明确视觉提示——体型大得多、有独特外观，玩家立刻意识到"这是个大家伙"。
- 敌人之间推开不重叠 → "它们是有实体的、不是纸片"的物理存在感。

**玩家不应该感受到**：
- "这些敌人长得不像怪物"（不可爱）或"这些敌人在可爱和恐怖之间摇摆不定"。
- "不知道哪个敌人威胁更大"（所有敌人看起来一样）。
- "敌人卡在彼此身上"或"敌人重叠成一大坨"（缺乏分离感）。
- "敌人移动方式很奇怪"（抖动、抽搐、或者完全笔直穿过其他敌人）。

**参考游戏**：
- **吸血鬼幸存者**：敌人种类清晰、移动方向一致、密度极高但不卡滞。
- **弹壳特攻队（Survivor.io）**：敌人区分度高（快/中型/重装），击杀音效反馈满足。
- **Stardew Valley 的怪物**：可爱但不幼稚，"有威胁的好看"。

---

## 3. Detailed Design

### 3.1 Core Rules

#### 规则 1：敌人类型定义（MVP 5 种）

MVP 阶段定义 5 种敌人，每种有独立的属性配置。所有属性数据通过字典或外部 JSON 配置表加载。

| 类型ID | 名称 | HP | 移动速度 (px/s) | 碰撞伤害 | 碰撞半径 (px) | 金币掉落 | 经验掉落 |
|--------|------|-----|----------------|----------|--------------|----------|----------|
| `normal_a` | 毛团怪（快） | 30 | 90 | 10 | 14 | 2 | 3 |
| `normal_b` | 圆墩怪（中） | 60 | 60 | 15 | 18 | 2 | 3 |
| `normal_c` | 壮壮怪（重） | 120 | 40 | 20 | 22 | 3 | 5 |
| `elite` | 精英怪 | 300 | 55 | 25 | 24 | 8 | 10 |
| `boss` | Boss 怪 | 1000 | 35 | 40 | 48 | 25 | 50 |

**说明**：
- `normal_a/b/c` 是三种普通敌人的变体，代表"快节奏 → 均衡 → 慢节奏"三个层级
- 移动速度越低，敌人移动越慢，但 HP 和伤害越高，形成"玻璃大炮 vs 移动堡垒"的权衡
- Boss 碰撞半径特别大（48px），视觉上约占 96px 直径，是普通敌人的 3-4 倍
- 所有数值为基础值，最终值受波次缩放系统影响（详见公式部分）

#### 规则 2：敌人实例化

敌人由**敌人生成系统**负责实例化。实例化流程：

```
敌人生成系统加载敌人 Scene
    ↓
实例化 Node，传入 enemy_type 参数（如 "normal_a"）
    ↓
敌人节点读取 enemy_type，从数据表加载对应属性
    ↓
设置初始位置（在地图边缘的生成点）
    ↓
添加到敌人组（"enemy" Group）
    ↓
发出 enemy_spawned(enemy) 信号
    ↓
返回敌人节点引用给调用方
```

**敌人 Scene 结构**：
```
EnemyBase (CharacterBody2D)
├── CollisionShape2D          # CircularShape2D, 半径由 body_size 决定
├── Sprite2D / AnimatedSprite2D  # 敌人视觉表现
├── HealthComponent (Node)    # 生命值组件，is_player = false
└── EnemyAI.gd                # 附加到 EnemyBase 上的 AI 脚本
```

#### 规则 3：敌人移动 AI（追踪英雄）

敌人每帧在 `_physics_process(delta)` 中执行以下移动逻辑：

```
获取英雄当前位置（移动系统提供的 hero_position）
    ↓
计算方向向量：direction = (hero_position - current_position).normalized()
    ↓
检查前方是否有其他敌人（简单分离逻辑）
    ↓
如果没有阻挡：
    目标位置 = current_position + direction × move_speed × delta
否则：
    目标位置 = current_position + direction × move_speed × delta × 0.5  # 减速通过
    ↓
应用位置：move_and_slide()（Godot 4 的物理移动）
    ↓
如果 move_and_slide() 检测到碰撞（碰到英雄或其他敌人）：
    停止继续推进，保持当前位置
```

**设计要点**：
- 所有敌人的移动目标是英雄当前位置——不做路径规划，不绕障碍物
- MVP 地图无内部障碍物（只有矩形边界），所以简单追踪足够
- 敌人的 `move_speed` 属性独立于移动系统的 `base_speed`——敌人不使用移动系统组件
- 敌人使用 `CharacterBody2D.move_and_slide()` 自动处理与其他 CharacterBody2D 的碰撞分离

#### 规则 4：敌人-英雄碰撞处理

敌人与英雄的碰撞处理由**碰撞检测系统**负责，敌人系统不直接处理伤害：

```
EnemyBase 的 CollisionShape2D 与英雄的 CollisionShape2D 重叠
    ↓
碰撞检测系统的 Area2D 发出 player_hit_by(enemy) 信号
    ↓
生命值系统接收到信号 → 检查玩家是否无敌帧 → 扣除玩家 HP
    ↓
敌人系统接收 enemy_reached_hero(enemy) 信号 → 播放敌人攻击动画（可选）
```

**关键**：敌人本身**不主动调用 take_damage() 攻击玩家**，而是作为"碰撞触发器"。真正的伤害逻辑在生命值系统和伤害计算系统中处理。

#### 规则 5：敌人-敌人碰撞分离

敌人之间**不允许重叠**。每个敌人使用 `CharacterBody2D` 并设置正确的碰撞层级：

- 敌人的 `collision_layer` = enemies 层
- 敌人的 `collision_mask` = player 层 + enemies 层
- 当两个敌人重叠时，`move_and_slide()` 自动将它们推开

**分离力**：Godot 4 的 `move_and_slide()` 对于 CharacterBody2D 之间的碰撞会自动产生滑移响应。敌人互相卡住时会自动沿切线方向滑动，不会产生强力推开（不会像磁铁互斥那样弹开）。

#### 规则 6：敌人死亡处理

敌人HP归零时（由生命值系统的 `HealthComponent` 处理），触发以下流程：

```
HealthComponent.current_hp <= 0
    ↓
HealthComponent._on_died() 执行：
    is_dead = true
    emit enemy_died(enemy: Node) 信号
    ↓
[金币系统监听] → 在敌人位置生成金币掉落物
[经验系统监听] → 在敌人位置生成经验掉落物
    ↓
播放敌人死亡动画（消散/爆炸特效，符合可爱风格）
    ↓
等待动画完成（通常 0.3-0.5 秒）
    ↓
queue_free() 移除敌人节点
```

**设计要点**：
- 敌人死亡后**不会立即移除**——需要等待掉落物生成和死亡动画
- `queue_free()` 由敌人自己调用（在 `_on_enemy_died()` 回调中）
- 死亡动画期间，敌人的碰撞体应禁用（防止"已经死了但还挡住路"）

#### 规则 7：Boss 简单行为

MVP 阶段 Boss 不做复杂 AI，只做以下简化：

| 行为 | Boss 特有逻辑 |
|------|--------------|
| 移动 | 与普通敌人相同（直线追踪英雄），但速度更慢 |
| 碰撞伤害 | 比普通敌人高（40点基础伤害） |
| 体型 | 碰撞半径 48px，视觉上占据更大空间 |
| HP | 1000基础HP，需要大量攻击才能击杀 |
| 死亡特效 | 更华丽的爆炸/消散动画（比死亡动画更醒目） |

**v1.0 扩展**：Boss 可加入冲锋攻击（周期性加速冲向英雄）、阶段转换（HP=50%时变身）等复杂行为。MVP 不需要。

---

### 3.2 States and Transitions

#### 敌人运行时状态机

```
               ┌─────────────────────────────┐
               │         SPAWNING            │
               │ （生成动画播放中）           │
               │ 不可移动，不可被攻击         │
               └──────────────┬──────────────┘
                              │
                       生成动画完成
                              ↓
               ┌─────────────────────────────┐
               │          ACTIVE             │
               │ （正常移动 + 可被攻击）       │
               │                             │
               │  每帧执行 move_toward_hero   │
               │  碰撞检测正常                │
               └──────────────┬──────────────┘
                              │
                        current_hp <= 0
                              ↓
               ┌─────────────────────────────┐
               │          DYING              │
               │ （死亡动画播放中）           │
               │ 碰撞体禁用，不移动           │
               │ 掉落物已生成                 │
               └──────────────┬──────────────┘
                              │
                        动画完成
                              ↓
                          queue_free()
```

| 状态 | 描述 | 可移动 | 可被攻击 | 碰撞检测 |
|------|------|--------|---------|---------|
| **SPAWNING** | 生成动画播放中（0.2秒） | 否 | 否 | 碰撞体禁用 |
| **ACTIVE** | 正常运行中 | 是 | 是 | 全部启用 |
| **DYING** | 死亡动画播放中 | 否 | 否 | 碰撞体禁用 |

**状态转换触发**：
- SPAWNING → ACTIVE：生成动画时长结束（定时器回调）
- ACTIVE → DYING：`HealthComponent.enemy_died` 信号触发
- DYING → 删除：动画时长结束（定时器回调 → `queue_free()`）

---

### 3.3 Interactions with Other Systems

| 系统 | 交互方向 | 接口 | 说明 |
|------|---------|------|------|
| **生命值系统** | 上游 ↔ 敌人 | `HealthComponent` 节点附加到敌人上；接收 `enemy_died(enemy)` 信号 | 敌人挂载 `HealthComponent` 管理 HP；死亡时发出信号通知下游 |
| **伤害计算系统** | 伤害 → 敌人 | 调用 `calculate_damage(attacker, enemy, data)` | 玩家/塔攻击敌人时调用，返回值传入 `HealthComponent.take_damage()` |
| **移动系统** | 移动 → 敌人 | 查询英雄 `global_position` | 敌人每帧读取英雄位置作为移动目标 |
| **碰撞检测系统** | 碰撞 → 敌人 | 监听 `player_hit_by(enemy)`；设置正确的 `collision_layer` | 碰撞检测系统通知敌人接触英雄；敌人需要正确的物理层配置 |
| **敌人生成系统** | 上游 → 敌人 | 调用 `spawn_enemy(type, position)` | 生成系统创建敌人实例并放置到指定位置 |
| **金币系统** | 敌人 → 下游 | 监听 `enemy_died(enemy)` 信号 | 在敌人死亡位置生成金币掉落物 |
| **经验系统** | 敌人 → 下游 | 监听 `enemy_died(enemy)` 信号 | 在敌人死亡位置生成经验掉落物 |
| **自动攻击系统** | 敌人 ↔ 下游 | 敌人加入 "enemy" Group | 自动攻击系统通过 Group 查询或直接调用 `get_enemies_in_radius()` 获取目标 |
| **波次系统** | 上游 → 敌人 | 提供 HP/速度/伤害缩放乘数 | 波次系统根据当前波次动态调整敌人属性 |
| **UI系统** | 敌人 → 下游 | 提供 `get_enemy_type()`, `get_hp_ratio()` | 用于 Boss 血条显示 |

---

## 4. Formulas

### 公式 1：敌人每帧移动位移

```
direction = (hero_position - enemy_position).normalized()
actual_speed = base_move_speed × wave_speed_multiplier
movement = direction × actual_speed × delta
new_position = enemy_position + movement
```

**变量定义**：

| 变量 | 类型 | 单位 | 范围 | 说明 |
|------|------|------|------|------|
| `hero_position` | Vector2 | 像素 | 地图范围内 | 英雄当前帧的世界坐标 |
| `enemy_position` | Vector2 | 像素 | 地图范围内 | 敌人当前帧的世界坐标 |
| `base_move_speed` | float | 像素/秒 | 35-90（因类型而异） | 敌人基础移动速度，由敌人类型数据定义 |
| `wave_speed_multiplier` | float | 无量纲 | 0.8~1.5 | 波次缩放系数，由波次系统提供 |
| `delta` | float | 秒 | ~0.01667（60FPS） | 物理帧时间 |
| `movement` | Vector2 | 像素 | — | 本帧理论位移向量 |

**示例计算**（normal_a 敌人追踪英雄，60FPS）：
```
hero_position = (640, 360)
enemy_position = (200, 100)
direction = (640-200, 360-100).normalized()
         = (440, 260).normalized()
         = (440, 260) / sqrt(440² + 260²)
         = (440, 260) / 511.1
         = (0.861, 0.509)

actual_speed = 90 × 1.0 = 90 px/s
movement = (0.861, 0.509) × 90 × 0.01667
         = (1.29, 0.76) 像素/帧

new_position = (200, 100) + (1.29, 0.76) = (201.29, 100.76)
```

---

### 公式 2：敌人属性波次缩放

敌人属性随波次动态增长，缩放乘数由**难度曲线系统**统一提供。敌人系统不独立定义任何波次缩放公式，所有乘数从难度曲线系统的 WaveConfig 中读取。

```
effective_hp = base_hp × WaveConfig.hp_multiplier
effective_speed = base_move_speed × WaveConfig.speed_multiplier
effective_damage = base_damage × WaveConfig.damage_multiplier
```

**变量定义**：

| 变量 | 类型 | 默认值 | 范围 | 说明 |
|------|------|--------|------|------|
| `WaveConfig.hp_multiplier` | float | 1.0 | 0.8~3.5 | HP 波次缩放系数，来自难度曲线系统 |
| `WaveConfig.speed_multiplier` | float | 1.0 | 0.8~1.5 | 速度波次缩放系数，来自难度曲线系统 |
| `WaveConfig.damage_multiplier` | float | 1.0 | 0.8~3.0 | 伤害波次缩放系数，来自难度曲线系统 |

**缩放值示例**（来源于难度曲线系统 difficulty-curve-system.md §8 的 1-10 波示例表）：

| 波次 | HP倍率 | 速度倍率 | 伤害倍率 | 来源说明 |
|------|--------|----------|----------|---------|
| 1 | 1.00 | 1.00 | 1.00 | 基础值 |
| 2 | 1.12 | 1.00 | 1.10 | 线性增长 |
| 3 | 1.49 | 1.03 | 1.44 | 小里程碑（+20% bonus） |
| 4 | 1.36 | 1.03 | 1.30 | — |
| 5 | 1.48 | 1.06 | 1.40 | — |
| 6 | 1.92 | 1.06 | 1.92 | 中里程碑（+20% bonus） |
| 7 | 1.72 | 1.09 | 1.60 | — |
| 8 | 1.84 | 1.09 | 1.70 | — |
| 9 | 1.96 | 1.12 | 1.80 | — |
| 10 | 3.50 | 1.23 | 3.19 | 大里程碑 Boss（+68% bonus） |

> 以上数值均引用自 difficulty-curve-system.md "8. 1-10 波示例表"。敌人系统不对这些值做任何独立定义。

**示例计算**（第 5 波，normal_b 敌人）：
```
base_hp = 60
wave_hp_multiplier = WaveConfig.hp_multiplier = 1.48（来自难度曲线）
effective_hp = 60 × 1.48 = 88.8 ≈ 89

base_move_speed = 60
wave_speed_multiplier = WaveConfig.speed_multiplier = 1.06
effective_speed = 60 × 1.06 = 63.6 px/s

base_damage = 15
wave_damage_multiplier = WaveConfig.damage_multiplier = 1.40
effective_damage = 15 × 1.40 = 21
```

> **注意**：旧版本使用硬编码公式 `1.0 + (wave-1)×0.2`，导致第 5 波 HP 算出 1.8 而非 1.48，偏高 22%。已修正为引用难度曲线权威值。

**设计意图**：
- 难度曲线是唯一数值真理源（Single Source of Truth），所有属性乘数由其统一计算
- 敌人系统只做应用（Application），不做定义（Definition）
- 调参设计师只需修改 difficulty-curve-system 的调参旋钮，敌人属性自动适配
- 里程碑波的额外倍率（+20% / +68%）由难度曲线的 `milestone_bonus` / `boss_bonus` 处理

---

### 公式 3：敌人-敌人分离处理

Godot 4 的 `move_and_slide()` 自动处理 CharacterBody2D 之间的碰撞。但为确保分离效果，敌人使用以下配置：

```gdscript
# 敌人碰撞配置
collision_layer = ENEMY_LAYER      # 敌人层（可被其他敌人检测到）
collision_mask = PLAYER_LAYER | ENEMY_LAYER  # 可检测英雄和其他敌人

# 移动时 Godot 自动处理分离
move_and_slide()  # 碰到其他敌人时产生滑移而非穿透
```

**额外分离力（可选增强）**：当敌人密度很高时，`move_and_slide()` 默认行为可能导致敌人"堆叠"。可增加主动分离逻辑：

```gdscript
# 主动分离增强：对 nearby 的敌人施加微小的推开力
func _apply_separation(delta: float) -> void:
    var nearby_enemies = _get_nearby_enemies(separation_radius)
    for other in nearby_enemies:
        var push_dir = (global_position - other.global_position).normalized()
        var push_strength = separation_force × (1.0 - dist / separation_radius)
        position += push_dir × push_strength × delta
```

| 参数 | 默认值 | 范围 | 说明 |
|------|--------|------|------|
| `separation_radius` | 40px | 30-60px | 分离检测半径 |
| `separation_force` | 50px/s | 30-100px/s | 分离推力速度 |

MVP 阶段**不使用主动分离**——`move_and_slide()` 足够处理常规密度的敌人分离。如果 playtest 发现敌人"成团"现象严重，再启用主动分离。

---

### 公式 4：生成到地图边缘的距离计算

地图系统提供 8 个生成点（Spawn Points）。为增加变化，从生成点向地图内侧偏移一段距离：

```
spawn_point = SPAWN_POINTS[spawn_index]  # 8 个点之一
offset_distance = random(30, 80)  # 向地图内偏移
direction = (map_center - spawn_point).normalized()
actual_spawn_position = spawn_point + direction × offset_distance
```

| 参数 | 默认值 | 范围 | 说明 |
|------|--------|------|------|
| `SPAWN_POINTS[]` | 8 个 Vector2 | — | 地图边缘 8 个固定生成点 |
| `offset_distance` | 55px（均值） | 30-80px | 防止敌人在屏幕最边缘生成（玩家看不到） |

---

### 公式 5：存活时间上限估算

根据敌人属性和速度，计算敌人从地图边缘到达英雄中心的最长时间：

```
max_travel_time = max_distance / effective_speed

其中 max_distance ≈ 地图对角线的一半 ≈ sqrt(map_width² + map_height²) / 2
```

**示例**（1280×720 地图，normal_a 敌人）：
```
max_distance = sqrt(1280² + 720²) / 2 ≈ 1468 / 2 ≈ 734px
effective_speed = 90 px/s
max_travel_time = 734 / 90 ≈ 8.2 秒
```

**设计意图**：
- 快速敌人（90px/s）约 8 秒穿越全地图
- 重装敌人（40px/s）约 18 秒穿越全地图
- 这给玩家足够的反应时间进行走位和策略调整

---

## 5. Edge Cases

| # | 边界情况 | 触发条件 | 处理方式 |
|---|---------|---------|---------|
| EC-01 | **英雄移动到地图外** | 理论上不应发生（移动系统钳制了英雄位置） | 若发生，敌人继续朝英雄最后已知位置移动；不崩溃、不停止 |
| EC-02 | **敌人在生成动画期间被攻击** | 生成系统创建敌人后立即有攻击命中（极端时序） | SPAWNING 状态期间 `is_active = false`，`take_damage()` 检查此标志并忽略 |
| EC-03 | **敌人死亡后再次收到伤害** | 同帧内多次攻击命中同一个已死敌人 | `HealthComponent.is_dead = true` 检查阻止重复伤害；`take_damage()` 直接返回 |
| EC-04 | **敌人卡在地图边界** | 敌人生成点恰好在地图边界上 | 敌人生成后立即执行一次边界钳制，确保敌人完全在地图内；移动逻辑中的目标指向英雄（英雄在地图内），因此敌人会自动向内移动 |
| EC-05 | **大量敌人同时朝向英雄** | 100 个敌人同时追踪，形成"人流拥堵" | 使用 `move_and_slide()` 处理碰撞分离；如 playtest 发现严重拥堵，启用主动分离力；每个敌人的移动计算 < 0.05ms，100 个 < 5ms，在帧预算内 |
| EC-06 | **英雄死亡后敌人继续移动** | 玩家HP=0，结算面板尚未弹出 | 敌人继续正常运行（包括移动、碰撞检测）直到结算面板确认暂停；这允许结算面板"冻结"场景时敌人保持静止 |
| EC-07 | **敌人移动目标为零向量** | `hero_position - enemy_position` 的模长 < 0.01（英雄和敌人重叠） | 跳过归一化，不产生移动；这是正常情况（敌人已接触英雄） |
| EC-08 | **敌人 HP 为负数** | 伤害远超剩余 HP（如 HP=10 受到 100 伤害） | `HealthComponent` 使用 `max(0, current_hp - damage)` 确保 HP 不小于 0 |
| EC-09 | **敌人实例化失败（场景加载问题）** | `load("res://...enemy.tscn")` 返回 null | 记录 `push_error` 日志，返回 null 给调用方；敌人生成系统负责重试或跳过 |
| EC-10 | **敌人被生成到英雄位置上** | 生成点与英雄位置极度接近 | 检测距离 < 50px 时，在生成点切线方向随机偏移 50-100px；确保玩家有反应时间 |
| EC-11 | **游戏暂停/升级面板打开期间敌人的行为** | 升级面板弹出，游戏世界暂停 | 敌人节点 `process_mode = PROCESS_MODE_PAUSABLE`（默认），升级面板弹出时自动暂停移动和碰撞。视觉上保持冻结状态 |
| EC-12 | **敌人数量超过性能预算** | 极端场景同时存在超过 100 个敌人 | 敌人系统不主动限制数量（数量由生成系统控制）；每帧移动计算预算上限 5ms（100 敌人 × 0.05ms），超出时在 profiler 中警告 |
| EC-13 | **敌人 type 不在数据表中** | 生成系统传入了未知 enemy_type | 记录 `push_error` 日志，使用默认 normal_a 属性作为回退值，不崩溃 |

---

## 6. Dependencies

### 上游依赖（敌人系统依赖的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **生命值系统** | 硬依赖 | `HealthComponent` 节点 + `enemy_died(enemy)` 信号 | 每个敌人附加 `HealthComponent(is_player=false)` 管理 HP；死亡时发出信号 |
| **伤害计算系统** | 硬依赖 | `calculate_damage(enemy, player, attack_data) -> int` | 敌人碰到英雄时，调用伤害计算系统得到伤害值 |
| **移动系统** | 软依赖 | 查询英雄的 `global_position` | 每帧读取英雄世界坐标作为移动目标 |
| **碰撞检测系统** | 硬依赖 | 设置正确的 `collision_layer` 和 `collision_mask` | 敌人需要正确的物理层配置以检测对玩家的碰撞 |
| **波次系统** | 软依赖 | 读取波次缩放乘数 | 敌人属性受当前波次的缩放系数影响 |

### 下游依赖（依赖敌人系统的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **敌人生成系统** | 硬依赖 | `spawn_enemy(type, position)` | 调用敌人系统创建实例 |
| **金币系统** | 软依赖 | 监听 `enemy_died(enemy)` 信号 | 在敌人死亡位置生成金币掉落物 |
| **经验系统** | 软依赖 | 监听 `enemy_died(enemy)` 信号 | 在敌人死亡位置生成经验掉落物 |
| **自动攻击系统** | 软依赖 | 敌人加入 "enemy" Group | 通过 Group 查询所有敌人作为攻击目标 |
| **UI系统** | 软依赖 | `get_enemy_type()`, `get_hp_ratio()` | Boss 血条显示 |

### GDScript 接口定义

```gdscript
# ============================================================
# EnemyBase.gd
# 所有敌人的基类场景脚本
# 场景路径: assets/scenes/enemies/enemy_base.tscn
#
# 挂载到 CharacterBody2D 根节点
# HealthComponent 作为子节点挂载在 Inspector 中配置
# ============================================================
class_name EnemyBase
extends CharacterBody2D

# ---------- 信号（对外发出）----------

## 敌人实例化并添加到场景后发出
signal enemy_spawned(enemy: Node)

## 敌人接触到英雄后发出（供音效/动画系统订阅）
signal enemy_reached_hero(enemy: Node)

# ---------- 导出变量（数据驱动）----------

## 敌人类型标识（正常/精英/Boss）
@export var enemy_type: String = "normal_a"

## 生成动画时长（秒）
@export var spawn_animation_duration: float = 0.2

## 死亡动画时长（秒）
@export var death_animation_duration: float = 0.4

# ---------- 运行时状态（内部）----------

## 当前状态：SPAWNING / ACTIVE / DYING
var _state: String = "SPAWNING"

## 敌人属性数据（从数据表加载）
var _data: Dictionary = {}

## 对英雄的引用（_ready 时初始化）
var _hero: Node = null

# ---------- 敌人数据表（应从外部 JSON 加载，MVP 可内联）----------

const ENEMY_DATA: Dictionary = {
    "normal_a": {
        "name": "毛团怪",
        "base_hp": 30,
        "base_move_speed": 90.0,
        "base_damage": 10,
        "body_size": 14.0,       # 碰撞半径
        "coin_value": 2,
        "xp_value": 3,
    },
    "normal_b": {
        "name": "圆墩怪",
        "base_hp": 60,
        "base_move_speed": 60.0,
        "base_damage": 15,
        "body_size": 18.0,
        "coin_value": 2,
        "xp_value": 3,
    },
    "normal_c": {
        "name": "壮壮怪",
        "base_hp": 120,
        "base_move_speed": 40.0,
        "base_damage": 20,
        "body_size": 22.0,
        "coin_value": 3,
        "xp_value": 5,
    },
    "elite": {
        "name": "精英怪",
        "base_hp": 300,
        "base_move_speed": 55.0,
        "base_damage": 25,
        "body_size": 24.0,
        "coin_value": 8,
        "xp_value": 10,
    },
    "boss": {
        "name": "Boss 怪",
        "base_hp": 1000,
        "base_move_speed": 35.0,
        "base_damage": 40,
        "body_size": 48.0,
        "coin_value": 25,
        "xp_value": 50,
    },
}

# ---------- 碰撞层级常量 ----------
const ENEMY_LAYER: int = 2
const PLAYER_LAYER: int = 1


# ---------- 生命周期 ----------

func _ready() -> void:
    _load_enemy_data()
    _setup_health()
    _setup_collision()
    _find_hero()
    _start_spawn_animation()


func _physics_process(delta: float) -> void:
    if _state == "SPAWNING":
        return  # 生成动画期间不移动

    if _state == "DYING":
        return  # 死亡动画期间不移动

    if _state == "ACTIVE":
        _move_toward_hero(delta)


# ---------- 公开接口 ----------

## 每帧移动敌人朝向英雄
## delta: 物理帧时间
## 使用 Godot 4 的 move_and_slide() 实现移动与碰撞
func _move_toward_hero(delta: float) -> void:
    if _hero == null or not is_instance_valid(_hero):
        # 英雄不存在时向地图中心移动
        return

    var direction: Vector2 = (_hero.global_position - global_position).normalized()
    if direction.is_zero_approx():
        return

    # 获取波次缩放后的速度
    var effective_speed: float = _data.base_move_speed * _get_wave_speed_multiplier()

    # 设置速度并移动
    velocity = direction * effective_speed
    move_and_slide()


## 返回敌人类型标识
func get_enemy_type() -> String:
    return enemy_type


## 返回敌人完整属性数据（含波次缩放后的值）
func get_data() -> Dictionary:
    return {
        "type": enemy_type,
        "name": _data.get("name", "Unknown"),
        "hp": _get_effective_hp(),
        "move_speed": _data.base_move_speed * _get_wave_speed_multiplier(),
        "damage": _data.base_damage * _get_wave_damage_multiplier(),
        "body_size": _data.get("body_size", 16.0),
        "coin_value": _data.get("coin_value", 1),
        "xp_value": _data.get("xp_value", 1),
    }


## 触发敌人死亡流程（由 HealthComponent.enemy_died 信号回调调用）
func _on_enemy_died() -> void:
    _state = "DYING"
    # 禁用碰撞体
    $CollisionShape2D.disabled = true
    # 播放死亡动画
    # TODO: 播放 death_animation_duration 时长的动画
    await get_tree().create_timer(death_animation_duration).timeout
    queue_free()


# ---------- 私有方法 ----------

## 从数据表加载敌人属性
func _load_enemy_data() -> void:
    if not ENEMY_DATA.has(enemy_type):
        push_error("EnemyBase: unknown enemy_type '%s', falling back to normal_a" % enemy_type)
        enemy_type = "normal_a"
    _data = ENEMY_DATA[enemy_type].duplicate()


## 配置 HealthComponent 并连接到死亡信号
func _setup_health() -> void:
    var hc: Node = get_node_or_null("HealthComponent")
    if hc == null:
        push_error("EnemyBase: HealthComponent not found!")
        return

    hc.max_hp = _get_effective_hp()
    hc.is_player = false

    var result = hc.enemy_died.connect(_on_enemy_died)
    if result != OK:
        push_error("EnemyBase: failed to connect enemy_died signal")


## 配置碰撞体和层级
func _setup_collision() -> void:
    collision_layer = ENEMY_LAYER
    collision_mask = PLAYER_LAYER | ENEMY_LAYER

    var body_size: float = _data.get("body_size", 16.0)
    if $CollisionShape2D.shape is CircleShape2D:
        $CollisionShape2D.shape.radius = body_size


## 查找英雄节点引用
func _find_hero() -> void:
    _hero = get_tree().get_first_node_in_group("hero")


## 播放生成动画（SPAWNING 状态）
func _start_spawn_animation() -> void:
    _state = "SPAWNING"
    # 禁用碰撞体
    $CollisionShape2D.disabled = true
    # 生成淡入/弹出动画（Tween）
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 1.0, spawn_animation_duration)
    tween.finished.connect(_on_spawn_finished)


## 生成动画完成，转换为 ACTIVE 状态
func _on_spawn_finished() -> void:
    _state = "ACTIVE"
    $CollisionShape2D.disabled = false
    enemy_spawned.emit(self)


## 获取波次缩放后的 HP
func _get_effective_hp() -> int:
    var multiplier = _get_wave_hp_multiplier()
    return int(_data.base_hp * multiplier)


## 获取波次 HP 缩放系数
## 来源：难度曲线系统 WaveConfig.hp_multiplier
func _get_wave_hp_multiplier() -> float:
    var wave = _get_current_wave()
    var config = _difficulty_curve.get_wave_config(wave)
    return config.hp_multiplier


## 获取波次速度缩放系数
## 来源：难度曲线系统 WaveConfig.speed_multiplier
func _get_wave_speed_multiplier() -> float:
    var wave = _get_current_wave()
    var config = _difficulty_curve.get_wave_config(wave)
    return config.speed_multiplier


## 获取波次伤害缩放系数
## 来源：难度曲线系统 WaveConfig.damage_multiplier
func _get_wave_damage_multiplier() -> float:
    var wave = _get_current_wave()
    var config = _difficulty_curve.get_wave_config(wave)
    return config.damage_multiplier


## 获取当前波次（从波次系统查询）
func _get_current_wave() -> int:
    return _wave_system.get_current_wave() if _wave_system != null else 1
```

---

## 7. Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 类别 | 影响面 |
|--------|------|--------|---------|------|--------|
| `base_hp`（normal_a） | int | 30 | 15-50 | 曲线 | 最快敌人的基础生存能力；过低被玩家一击秒杀没有威胁感 |
| `base_hp`（normal_c） | int | 120 | 80-200 | 曲线 | 重装敌人的基础生存能力；过高需要太多攻击才能击杀，玩家注意力疲劳 |
| `base_hp`（elite） | int | 300 | 200-500 | 曲线 | 精英应明显比普通耐打（约 3x normal_b），体现"精英"定位 |
| `base_hp`（boss） | int | 1000 | 500-2000 | 曲线 | Boss 应该是"大肉盾"，击杀需要整场游戏 DPS 的显著投入 |
| `base_move_speed`（normal_a） | float | 90 px/s | 60-120 | 手感 | 最快敌人速度；应明显快于玩家基础速度（200）的一半，形成"追得上但甩得开"的关系 |
| `base_move_speed`（boss） | float | 35 px/s | 20-50 | 手感 | Boss 速度应足够慢，让玩家有充足走位空间 |
| `base_damage`（normal_a） | int | 10 | 5-20 | 曲线 | 最低威胁敌人的伤害；在玩家 HP=100、无敌帧=1.2s 的条件下，需要约 3 次命中才能击杀 |
| `base_damage`（boss） | int | 40 | 25-60 | 曲线 | Boss 伤害应让玩家在 2-3 次命中后就有明显 HP 下降，造成压迫感 |
| `body_size`（正常范围） | float | 14-22 px | 10-30 | 手感 | 敌人碰撞半径；需与精灵视觉大小匹配 |
| `body_size`（boss） | float | 48 px | 36-64 | 手感 | Boss 碰撞半径；应明显大于普通敌人（至少 2 倍） |
| `spawn_animation_duration` | float | 0.2s | 0.1-0.5s | 手感 | 生成弹出动画时长；过长会导致敌人"悬在空中不动"，过短无视觉提示 |
| `death_animation_duration` | float | 0.4s | 0.2-0.8s | 手感 | 死亡消散动画时长；过长拖慢节奏，过短失去满足感 |
| `wave_hp_growth` | float | 0.2/波 | 0.1-0.3/波 | 曲线 | 每波 HP 增长 20%；过低后期无压力，过高 Boss 完全打不动 |
| `wave_damage_growth` | float | 0.15/波 | 0.1-0.25/波 | 曲线 | 每波伤害增长 15%；需要与玩家 HP 升级节奏协调 |
| `wave_speed_growth` | float | 0.03/波 | 0.0-0.05/波 | 曲线 | 每波速度增长 3%；速度不应增长太快，否则后期走位空间崩溃 |

**参数交互说明**：
- `base_move_speed`（normal_a=90）vs `base_speed`（英雄=200）：英雄基础速度约为最快敌人的 2.2x。这意味着英雄**可以甩开所有敌人**，但需要持续移动——符合 Survivors 类游戏的走位核心循环。
- `base_damage`（normal_a=10）vs `base_invincible_duration`（1.2s）vs 敌人移动速度：在 1.2 秒无敌帧期间，即使 5 个普通敌人同时接触，玩家也只受到 10 点伤害。这保证了"被一群怪围住"的最坏情况仍有逃生机会。
- `base_hp`（boss=1000）vs 玩家基础 DPS 预估（30-50 DPS）：Boss 需要约 20-33 秒持续输出才能击杀——大约覆盖 1-3 波的时间，符合"Boss 是持久战"的设计预期。
- 波次缩放参数**不应各自独立调整**——`wave_hp_growth` 和 `wave_damage_growth` 应共同调整以保持"敌人越来越强但不至于打不动"的平衡曲线。

**极端值测试**：
- `base_move_speed = 200`（normal_a = 英雄速度）→ 敌人永远追上玩家，走位失去意义 — 不推荐
- `base_hp（boss）= 100` → Boss 与普通敌人无显著差异，失去 Boss 的仪式感和压迫感 — 不推荐
- `wave_hp_growth = 0.5/波` → 第 5 波敌人 HP 翻倍再翻倍，DPS 瓶颈严重 — 不推荐
- `base_damage = 100`（normal_a）→ 敌人一发就带走玩家 1/3 HP，生存压力过高 — 不推荐

**所有敌人属性值（ENEMY_DATA）必须移至 `assets/data/enemy_data.json` 外部配置文件，不硬编码。** 波次缩放参数移至波次系统的配置。

---

## 8. Acceptance Criteria

### 功能测试

| ID | 测试项 | 前置条件 | 操作步骤 | Pass 标准 |
|----|-------|---------|---------|----------|
| AC-EN-01 | 敌人实例化与数据加载 | 调用 `spawn_enemy("normal_a", (100,100))` | 检查返回的敌人节点属性 | 敌人节点存在，`enemy_type="normal_a"`，`get_data()` 返回正确的属性值 |
| AC-EN-02 | 敌人朝向英雄移动 | 英雄在 (640,360)，敌人在 (200,100) | 运行 1 秒后检查敌人位置 | 敌人坐标更接近 (640,360)，位移量 ≈ `move_speed × 1.0` 像素（误差 < 5%） |
| AC-EN-03 | 敌人移动方向正确 | 敌人在英雄正右方 (800, 360) | 运行 0.5 秒后检查 X 坐标 | 敌人 X 坐标 < 800（向左移动），误差 < 2 像素 |
| AC-EN-04 | 敌人-英雄碰撞触发 | 敌人移动到与英雄碰撞范围重叠 | 检查碰撞检测系统输出 | `player_hit_by(enemy)` 信号发出，信号参数正确引用敌人节点 |
| AC-EN-05 | 敌人类型识别（5种） | 分别创建 5 种敌人 | 对每个调用 `get_enemy_type()` | 返回对应类型ID：normal_a/b/c、elite、boss |
| AC-EN-06 | 属性差异验证 | 分别查询 normal_a 和 normal_c 的 `get_data()` | 比较 move_speed 和 hp | normal_a 速度 > normal_c 速度，normal_c HP > normal_a HP（约 4 倍） |
| AC-EN-07 | Boss 体型识别 | 创建 Boss 敌人 | 查询 `body_size` | Boss 的 `body_size=48`，是 normal_a（14）的 3.4 倍以上 |
| AC-EN-08 | 生成动画状态 | 敌人创建后立即检查 | 读取 `_state` 变量 | `_state = "SPAWNING"`，碰撞体 `disabled = true` |
| AC-EN-09 | 生成状态转换 ACTIVE | 敌人创建后等待 0.3 秒 | 读取 `_state` 变量和碰撞体 | `_state = "ACTIVE"`，碰撞体 `disabled = false` |
| AC-EN-10 | 死亡动画状态 | 敌人 HP 归零后检查 | 读取 `_state` 变量 | `_state = "DYING"`，碰撞体 `disabled = true` |
| AC-EN-11 | 死亡后节点移除 | 等待 death_animation_duration（0.4s） | 检查场景树 | 敌人节点已从场景中移除（`is_instance_valid()` 返回 false） |
| AC-EN-12 | 敌人死亡掉落物触发 | 敌人HP归零 | 检查金币和经验系统 | 在敌人原位置生成了金币和经验掉落物（由下游系统验证） |
| AC-EN-13 | 敌人-敌人分离 | 2 个敌人在同一位置生成 | 运行 0.5 秒后检查 | 两个敌人不再重叠，各自有独立位置（距离 > `body_size_a + body_size_b`） |
| AC-EN-14 | 敌人组（Group）注册 | 敌人创建并进入 ACTIVE 状态 | `get_tree().get_nodes_in_group("enemy")` | 列表中能找到该敌人节点 |
| AC-EN-15 | 无效类型回退 | `spawn_enemy("unknown_type", (100,100))` | 检查敌人属性和日志 | 使用 normal_a 属性作为回退值，输出 `push_error` 日志，不崩溃 |

### 波次缩放测试

| ID | 测试项 | 前置条件 | 操作步骤 | Pass 标准 |
|----|-------|---------|---------|----------|
| AC-WAVE-01 | 第 1 波属性不变 | 设置波次 = 1 | 创建 normal_b 敌人并查询 `effective_hp` | `effective_hp = 60 × 1.0 = 60`（无缩放） |
| AC-WAVE-02 | 第 5 波 HP 缩放 | 设置波次 = 5 | 创建 normal_b 敌人并查询 `effective_hp` | `effective_hp = 60 × (1 + 4×0.2) = 60 × 1.8 = 108` |
| AC-WAVE-03 | 第 5 波速度缩放 | 设置波次 = 5 | 创建 normal_b 敌人并查询 `effective_speed` | `effective_speed = 60 × (1 + 4×0.03) = 60 × 1.12 = 67.2` |
| AC-WAVE-04 | 第 5 波伤害缩放 | 设置波次 = 5 | 创建 normal_b 敌人并查询 `effective_damage` | `effective_damage = 15 × (1 + 4×0.15) = 15 × 1.6 = 24` |

### 移动性能测试

| ID | 测试项 | 测试场景 | Pass 标准 |
|----|-------|---------|----------|
| AC-PERF-01 | 50 敌人移动计算 | 场景中 50 个敌人同时追踪英雄 | 每帧 `_move_toward_hero()` 总耗时 < 2.5ms（50 × 0.05ms），平均 60FPS 无掉帧 |
| AC-PERF-02 | 100 敌人移动计算 | 场景中 100 个敌人同时追踪英雄 | 每帧 `_move_toward_hero()` 总耗时 < 5ms，无严重卡顿（FPS > 50） |
| AC-PERF-03 | 敌人分离性能 | 50 个敌人聚集在 100px 半径内 | `move_and_slide()` 碰撞处理总耗时 < 3ms，无敌人"卡死"或"穿透" |
| AC-PERF-04 | 敌人内存管理 | 生成 100 个敌人，全部击杀后 | 所有敌人节点正确 `queue_free()`，无内存泄漏，敌人相关内存增长 < 5MB |

### 集成测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-INT-01 | 敌人 → 碰撞检测 → 生命值 | 敌人接触英雄 | `player_hit_by` 信号发出 → 生命值系统扣减玩家 HP → 无敌帧正确激活 |
| AC-INT-02 | 自动攻击 → 伤害计算 → 敌人 | 自动攻击命中敌人 | 伤害计算系统返回最终伤害值 → `HealthComponent.take_damage()` 执行 → 敌人 HP 准确下降 |
| AC-INT-03 | 敌人死亡 → 金币掉落 | Boss 敌人HP归零 | 金币系统在敌人位置生成 25 金币掉落物，视觉类型为 large |
| AC-INT-04 | 敌人死亡 → 经验掉落 | Boss 敌人HP归零 | 经验系统在敌人位置生成 50 xp 掉落物 |
| AC-INT-05 | 波次系统 → 敌人属性 | 将波次从 1 切换到 5，生成新的敌人 | 新敌人的 `effective_hp` = 基础HP × 1.8（已验证缩放生效） |
| AC-INT-06 | 敌人 → UI Boss 血条 | Boss 敌人存活期间 | UI 正确显示 Boss 血条（类型名和HP比例），HP下降时实时更新 |
| AC-INT-07 | 敌人生成 → 敌人生成系统 | 波次系统触发新一波生成 | 敌人按指定类型和生成点位置出现，`enemy_spawned` 信号发出 |
| AC-INT-08 | 敌人暂停响应 | 升级面板弹出 | 所有敌人停止移动，碰撞体保持当前状态（不位移、不触发伤害） |
| AC-INT-09 | 英雄死亡后敌人行为 | 玩家HP归零 | 敌人继续移动/碰撞直到结算面板接管暂停（不立即消失） |

---

## Open Questions

| # | 问题 | 影响范围 | 建议方案 | 决策时间 |
|---|------|---------|---------|---------|
| OQ-01 | 敌人是否需要护甲属性？（与伤害计算系统的 `armor` 参数对接） | 伤害计算、平衡性 | MVP 敌人不设护甲——所有攻击类型对敌人伤害相同。护甲增加系统复杂度，且 MVP 无"穿甲弹"等反护甲升级。v1.0 若引入护甲敌人，需在 `ENEMY_DATA` 中追加 `armor` 字段。 | v1.0 阶段 |
| OQ-02 | 敌人是否需要元素抗性/弱点？（火/冰/雷等伤害倍率） | 升级池系统、伤害计算 | MVP 无元素系统——所有伤害类型等效。若升级池设计中有"火焰弹"等元素攻击，需在 v1.0 阶段追加伤害类型倍率表。 | v1.0 阶段 |
| OQ-03 | Boss 是否需要阶段变换？（HP=50%时加速/变身/召唤小怪） | Boss 体验、波次系统 | MVP 不使用阶段变换——Boss 就是一个"大血量的移动靶"。阶段变换是 Boss 设计的核心趣味点，应在 v1.0 优先实现。 | v1.0 阶段 |
| OQ-04 | 敌人死亡后是否需要"尸体"残留物？（短时间阻挡路径） | 碰撞、策略深度 | MVP 不留尸体——死亡后立即移除碰撞体。若 playtest 发现敌人"消失得太快"没有反馈感，可增加 0.5 秒尸体残骸（不可通过，视觉上慢慢消散）。 | 原型验证后 |
| OQ-05 | 敌人是否需要有"仇恨切换"？（多个英雄时优先攻击低 HP 目标） | 多人游戏扩展 | MVP 单人游戏，始终追踪唯一英雄。多人模式需重新设计追踪逻辑——按距离/HP 选择目标。v2.0 阶段考虑。 | v2.0 阶段 |
| OQ-06 | 敌人数据表（ENEMY_DATA）是否在 MVP 就移至 `assets/data/enemy_data.json`？ | 数据驱动、工具链 | **建议 MVP 就使用外部 JSON**——虽然硬编码更快，但后续平衡调整频繁，外部数据避免改代码重新编译。且金币/经验系统已有 `COIN_DROP` 数据表的先例。 | 当前阶段确认 |
| OQ-07 | 敌人是否需要"眩晕/减速/定身"等状态效果？ | 升级池系统、伤害计算 | MVP 无状态效果——敌人只有 MOVE、ATTACK（碰撞伤害）、DEAD 三种行为。若升级池设计中有"冰冻弹"（减速敌人）或"眩晕锤"（短暂停止），需要在敌人系统中增加状态效果管理器。 | v1.0 阶段 |
| OQ-08 | 敌人移动是否应加入轻微的随机摆动（wiggle）？ | 视觉体验 | 当前设计为直线追踪，视觉上较"机械"。可加入微小的随机偏移（±10px/帧）让敌人运动更自然、更有"生物感"。成本：每个敌人多一次随机数运算。建议在原型阶段验证是否需要。 | 原型验证后 |
| OQ-09 | 敌人是否应支持"群体行为"？（ flocking / 跟随领头敌人） | AI、视觉 | MVP 不做——每个敌人独立追踪英雄。flocking 行为能增强"怪物潮"的视觉压迫感，但 AI 复杂度增加约 3x。若 playtest 发现敌人移动"太分散、没有潮流感"，可考虑在 v1.0 引入基础 flocking。 | v1.0 阶段 |
| OQ-10 | 敌人系统的波次缩放是否应与难度曲线系统的 `difficulty_curve` 联动？ | 难度曲线系统 | 当前设计中波次缩放使用独立的线性公式。难度曲线系统可能定义了非线性增长（如 S 曲线）。**建议**：敌人系统改为从难度曲线系统读取乘数，而非使用硬编码公式。这样一处调整难度曲线，所有敌人的属性自动适配。 | 下一设计迭代 |