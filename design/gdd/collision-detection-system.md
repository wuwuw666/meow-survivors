# 碰撞检测系统 (Collision Detection System)

> **Status**: Approved
> **Author**: [user + agents]
> **Last Updated**: 2026-04-01
> **Implements Pillar**: 基础设施（支撑所有物理交互）

---

## Overview

碰撞检测系统负责检测游戏世界中实体之间的空间重叠关系，并提供高效的查询API。主要检测类型包括：**玩家-敌人碰撞**（触发伤害）、**玩家-拾取物碰撞**（触发拾取）、**攻击-敌人碰撞**（触发命中）、**鼠标-区域碰撞**（触发UI交互）。

这是所有物理交互的基础设施。没有它，攻击无法命中敌人、玩家无法被伤害、金币和经验无法被拾取、塔位无法被点击放置。系统必须在支持 **50-100个同屏敌人** 的前提下保持性能，每帧碰撞检测耗时不超过 **2ms**。

**核心接口**:
- `get_enemies_in_radius(center: Vector2, radius: float) -> Array[Node]` — 区域查询敌人
- `get_nearest_enemy(center: Vector2, max_range: float) -> Node` — 查询最近敌人
- `signal player_hit_by(enemy: Node)` — 玩家被敌人碰到
- `signal pickup_collected(pickup_type: String, value: int)` — 拾取物被拾取

---

## Player Fantasy

碰撞检测系统是**透明的基础设施**——玩家不应该"意识到"碰撞检测的存在。好的碰撞体验是：

- 攻击敌人 → 命中判定准确，没有"明明打到了却没伤害"
- 被敌人碰到 → 受伤判定公平，没有"明明躲开了却被打"
- 拾取金币 → 自动吸附，不需要精确走到金币上
- 塔位点击 → 判定宽松，不需要精确点击

**情感目标**: **公平感 + 流畅感**
- 碰撞判定必须**视觉一致** — 攻击特效范围 = 实际命中范围
- 碰撞响应必须**即时** — 没有延迟或"鬼畜"判定

**玩家不应该感受到**:
- "明明打到了却没伤害"
- "明明躲开了却被打"
- 碰撞检测延迟或卡顿

**参考游戏**:
- **吸血鬼幸存者**: 碰撞判定宽松但一致，玩家专注于走位而非纠结判定
- **Brotato**: 拾取物有轻微吸附效果，不需要精确走到物品上

---

## Detailed Design

### Core Rules

#### 1. 碰撞层级定义

| 层级名称 | 用途 | 碰撞对象 |
|---------|------|---------|
| **player** | 玩家猫咪 | enemy, pickup |
| **enemy** | 敌人 | player, attack |
| **attack** | 攻击判定区域 | enemy |
| **pickup** | 拾取物（金币/经验） | player |
| **tower_slot** | 塔位区域 | mouse (通过Area2D检测) |
| **ui_area** | UI交互区域 | mouse |

#### 2. 碰撞检测类型

| 检测类型 | 触发条件 | 信号输出 | 消费系统 |
|---------|---------|---------|---------|
| **玩家-敌人** | Area2D body_entered | `player_hit_by(enemy)` | 生命值系统 |
| **攻击-敌人** | Area2D body_entered | `attack_hit_enemy(attack, enemy)` | 伤害计算系统 |
| **玩家-拾取物** | Area2D body_entered + 吸附 | `pickup_collected(pickup_type, value)` | 经验/金币系统 |
| **鼠标-塔位** | Area2D mouse_entered/exited | `hover_tower_slot(slot_id)` | 输入系统 |

#### 3. 区域查询API

```gdscript
# 查询指定半径内的所有敌人（使用圆形形状查询）
func get_enemies_in_radius(center: Vector2, radius: float) -> Array[Node]:
    var enemies = []
    var space_state = get_world_2d().direct_space_state

    # 创建圆形碰撞形状
    var shape = CircleShape2D.new()
    shape.radius = radius

    # 配置查询参数
    var query = PhysicsShapeQueryParameters2D.new()
    query.shape = shape
    query.transform = Transform2D(0, center)  # 设置圆心位置
    query.collision_mask = ENEMY_LAYER  # 只检测敌人层级
    query.collide_with_areas = true
    query.collide_with_bodies = true

    # 执行形状查询，最多返回32个结果
    var results = space_state.intersect_shape(query, 32)
    for result in results:
        enemies.append(result.collider)

    return enemies

# 查询最近的敌人
func get_nearest_enemy(center: Vector2, max_range: float) -> Node:
    var enemies = get_enemies_in_radius(center, max_range)
    if enemies.is_empty():
        return null
    var nearest = enemies[0]
    var min_dist = center.distance_to(nearest.global_position)
    for enemy in enemies:
        var dist = center.distance_to(enemy.global_position)
        if dist < min_dist:
            min_dist = dist
            nearest = enemy
    return nearest
```

**Godot API 说明**:
- `PhysicsShapeQueryParameters2D` 用于形状查询（圆形、矩形等）
- `intersect_shape()` 返回重叠的所有碰撞体
- `CircleShape2D` 定义查询的圆形范围

#### 4. 拾取物吸附规则

为改善拾取体验，拾取物有**吸附效果**：

| 参数 | 值 | 说明 |
|-----|---|------|
| **pickup_radius** | 20px | 玩家进入此范围触发拾取 |
| **magnet_radius** | 60px | 玩家进入此范围拾取物开始向玩家移动 |
| **magnet_speed** | 200px/s | 吸附移动速度 |

**规则**: 拾取物在 `magnet_radius` 范围内会向玩家移动，进入 `pickup_radius` 触发拾取。

### States and Transitions

碰撞检测系统是**持续运行的基础设施**，不需要复杂状态机。但有几种运行模式：

| 状态 | 描述 | 行为 |
|-----|------|------|
| **Active** | 正常游戏进行中 | 所有碰撞检测启用 |
| **Paused** | 游戏暂停 | 碰撞检测暂停，无信号输出 |
| **UI_Only** | 升级面板/波次暂停窗口打开 | 仅UI碰撞启用，游戏世界碰撞暂停 |

**暂停引用计数机制**：

多个系统（波次系统、升级选择系统）都可以请求暂停游戏碰撞。为了避免控制权冲突，碰撞系统内部使用引用计数：

```gdscript
var _pause_ref_count: int = 0

func pause_game_collision() -> void:
    _pause_ref_count += 1
    _update_collision_state()

func resume_game_collision() -> void:
    _pause_ref_count = max(0, _pause_ref_count - 1)
    _update_collision_state()

func _update_collision_state() -> void:
    if _pause_ref_count > 0:
        # 至少有一个系统请求暂停 → 切换到 UI_Only
        get_tree().paused = true
    else:
        # 没有任何系统请求暂停 → 恢复 Active
        get_tree().paused = false
```

**调用契约**：
- 每次 `pause_game_collision()` 调用都必须有对应的 `resume_game_collision()` 调用
- 波次系统和升级选择系统各自管理自己的暂停/恢复对，互不干扰
- 如果有多个系统同时暂停碰撞，只有最后一个调用 resume 时才真正恢复

**波次系统 → 碰撞（示例）**：
```gdscript
# 波次进入升级暂停
collision_system.pause_game_collision()  # ref_count = 1
...
# 波次结束，恢复
collision_system.resume_game_collision()  # ref_count = 0 → 恢复
```

**升级选择系统 → 碰撞（示例）**：
```gdscript
# 经验满级触发升级
collision_system.pause_game_collision()  # ref_count = 1
...
# 玩家选择完升级
collision_system.resume_game_collision()  # ref_count = 0 → 恢复
```

**嵌套场景（经验满级恰好在波次暂停期间）**：
```
波次暂停: pause() → ref=1
升级暂停: pause() → ref=2
升级恢复: resume() → ref=1 → 仍暂停
波次恢复: resume() → ref=0 → 恢复
```

**状态转换**：

| 触发事件 | 状态变化 |
|---------|---------|
| `_pause_ref_count` 从 0 变为 1 | Active → UI_Only |
| `Engine.time_scale = 0`（全局暂停） | Active → Paused |
| `_pause_ref_count` 从 1 变为 0 | UI_Only → Active |
| 全局暂停解除 | Paused → Active |

### Interactions with Other Systems

| 系统 | 交互方向 | 数据流 | 说明 |
|-----|---------|--------|------|
| **生命值系统** | 碰撞 → 生命值 | `player_hit_by(enemy)` 信号 | 玩家被敌人碰到时触发受伤 |
| **目标选择系统** | 目标选择 → 碰撞 | 调用 `get_enemies_in_radius()` | 查询攻击范围内的敌人 |
| **经验系统** | 碰撞 → 经验 | `pickup_collected("xp", value)` 信号 | 拾取经验球 |
| **金币系统** | 碰撞 → 金币 | `pickup_collected("coin", value)` 信号 | 拾取金币 |
| **输入系统** | 碰撞 → 输入 | `hover_tower_slot(slot_id)` 信号 | 鼠标悬停塔位区域 |
| **波次系统** | 波次 → 碰撞 | `pause_game_collision()` / `resume_game_collision()` | 升级面板打开时暂停游戏碰撞 |

---

## Formulas

### 1. 距离计算

```gdscript
distance = sqrt((x2 - x1)² + (y2 - y1)²)
```

Godot内置: `position_a.distance_to(position_b)`

### 2. 拾取物吸附移动

每帧更新拾取物位置：

```gdscript
# 吸附速度随距离衰减
var dist = pickup.position.distance_to(player.position)
if dist < magnet_radius and dist > pickup_radius:
    var direction = (player.position - pickup.position).normalized()
    var speed = magnet_speed * (1.0 - dist / magnet_radius)  # 越近越快
    pickup.position += direction * speed * delta
```

**吸附速度公式**: `actual_speed = magnet_speed × (1 - distance / magnet_radius)`

| 距离 | 速度倍率 |
|-----|---------|
| 60px (边缘) | 0% |
| 45px | 25% |
| 30px | 50% |
| 20px (拾取) | 67% |

### 3. 碰撞检测性能预算

| 指标 | 目标值 |
|-----|-------|
| 同屏敌人数 | 50-100 |
| 每帧碰撞检测耗时 | < 2ms |
| 区域查询返回上限 | 32个结果 |

---

## Edge Cases

| 边界情况 | 处理方式 |
|---------|---------|
| 敌人堆叠（多个敌人同一位置） | 每个敌人独立碰撞，分别触发伤害信号 |
| 玩家无敌帧期间被碰撞 | 不触发伤害信号，但碰撞检测继续运行 |
| 拾取物堆叠（金币+经验重叠） | 分别拾取，先进入先拾取 |
| 攻击同时命中多个敌人 | 对每个敌人都触发命中信号，由攻击系统决定伤害分配 |
| 敌人移出屏幕边界 | 碰撞检测继续，敌人仍存在 |
| 区域查询返回结果超限 | 返回最近的32个，忽略远处敌人 |
| 玩家在吸附范围内死亡 | 拾取物停止吸附，保持在当前位置 |
| 帧率下降导致碰撞检测延迟 | 使用物理帧 `_physics_process()` 而非渲染帧，保证一致性 |

---

## Dependencies

### 上游依赖（碰撞检测系统依赖的系统）

**无上游依赖** — 碰撞检测系统是 Foundation 层，不依赖任何其他游戏系统。

**Godot 引擎依赖**:
- `Area2D` — 用于碰撞区域检测
- `PhysicsDirectSpaceState2D` — 用于空间查询
- `CollisionShape2D` — 用于定义碰撞形状

### 下游依赖（依赖碰撞检测的系统）

| 系统 | 依赖类型 | 数据接口 | 说明 |
|-----|---------|---------|------|
| **生命值系统** | 硬依赖 | `player_hit_by(enemy)` 信号 | 检测玩家被敌人碰到 |
| **目标选择系统** | 硬依赖 | `get_enemies_in_radius()` API | 查询范围内敌人 |
| **经验系统** | 硬依赖 | `pickup_collected("xp", value)` 信号 | 检测经验球拾取 |
| **金币系统** | 硬依赖 | `pickup_collected("coin", value)` 信号 | 检测金币拾取 |
| **输入系统** | 软依赖 | `hover_tower_slot(slot_id)` 信号 | 鼠标塔位检测 |

### 接口定义

```gdscript
# 碰撞检测系统输出的信号接口
signal player_hit_by(enemy: Node)
signal attack_hit_enemy(attack: Node, enemy: Node)
signal pickup_collected(pickup_type: String, value: int)

# 碰撞检测系统提供的查询API
func get_enemies_in_radius(center: Vector2, radius: float) -> Array[Node]
func get_nearest_enemy(center: Vector2, max_range: float) -> Node
func pause_game_collision()
func resume_game_collision()
```

---

## Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 说明 |
|-------|------|-------|---------|------|
| **pickup_radius** | float | 20px | 10-40px | 拾取触发半径。过小导致拾取困难，过大导致"隔空拾取" |
| **magnet_radius** | float | 60px | 30-100px | 吸附生效半径。过小无吸附效果，过大导致拾取物"飞向玩家"太远 |
| **magnet_speed** | float | 200px/s | 100-400px/s | 吸附移动速度。过慢吸附感弱，过快显得突兀 |
| **query_max_results** | int | 32 | 16-64 | 区域查询最大返回数。影响性能，过多会降低帧率 |
| **collision_cell_size** | float | 64px | 32-128px | 碰撞网格单元格大小（Godot物理设置）。影响检测精度和性能 |

**参数交互说明**:
- `magnet_radius` 必须 > `pickup_radius`，否则吸附无意义
- `query_max_results` 影响目标选择系统返回的敌人数量上限

**极端值测试**:
- `pickup_radius = 5px` → 玩家抱怨"金币捡不起来"
- `magnet_radius = 200px` → 屏幕上所有拾取物都飞向玩家，失去策略感
- `query_max_results = 128` → 大量敌人时帧率下降

---

## Visual/Audio Requirements

[To be designed]

---

## UI Requirements

[To be designed]

---

## Acceptance Criteria

### 功能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-01 | 玩家-敌人碰撞 | 敌人移动到玩家位置 | 触发 `player_hit_by` 信号 |
| AC-02 | 攻击-敌人碰撞 | 攻击判定区域与敌人重叠 | 触发 `attack_hit_enemy` 信号 |
| AC-03 | 拾取物基本拾取 | 玩家走到金币/经验上 | 触发 `pickup_collected` 信号 |
| AC-04 | 拾取物吸附 | 玩家在60px范围内 | 拾取物向玩家移动 |
| AC-05 | 区域查询 | 调用 `get_enemies_in_radius()` | 返回范围内所有敌人 |
| AC-06 | 最近敌人查询 | 调用 `get_nearest_enemy()` | 返回距离最近的敌人 |

### 性能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-07 | 50敌人碰撞检测 | 场景中放置50个敌人 + 玩家移动 | 每帧碰撞检测 < 2ms |
| AC-08 | 100敌人碰撞检测 | 场景中放置100个敌人 + 玩家移动 | 每帧碰撞检测 < 3ms |
| AC-09 | 区域查询性能 | 100敌人时调用 `get_enemies_in_radius()` | 单次查询 < 0.5ms |

### 边界测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-10 | 敌人堆叠碰撞 | 5个敌人同一位置碰撞玩家 | 每个敌人都触发独立信号 |
| AC-11 | 玩家无敌帧 | 无敌期间敌人碰撞玩家 | 不触发伤害信号 |
| AC-12 | 查询结果超限 | 范围内有50个敌人，限制返回32个 | 返回最近的32个 |

### 集成测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-13 | 生命值系统集成 | 玩家被敌人碰到 | 生命值系统正确扣血 |
| AC-14 | 目标选择系统集成 | 自动攻击范围内有敌人 | 正确选择最近敌人攻击 |
| AC-15 | 拾取系统集成 | 玩家拾取金币/经验 | 经验/金币数值正确增加 |

---

## Open Questions

[To be designed]