# 目标选择系统 (Target Selection System)

> **Status**: Approved
> **Author**: [user + agents]
> **Last Updated**: 2026-04-02
> **Implements Pillar**: 策略有深度（攻击目标的选择影响战场控制感）

---

## 1. Overview

目标选择系统是自动攻击系统和防御塔系统的共享服务层，负责回答"当前应该攻击哪个敌人"这一核心问题。系统接收攻击发起者的位置和攻击范围，调用碰撞检测系统提供的空间查询 API，按照指定的目标策略（TargetStrategy）筛选并返回最优攻击目标。

**核心职责**：
- 根据调用者的位置和射程，从碰撞检测系统查询候选敌人列表
- 按照配置的目标策略对候选列表排序，返回最优目标（单个 Node）
- 支持策略枚举扩展，但 MVP 阶段仅实现 `NEAREST`（最近敌人）策略
- 在 50-100 个同屏敌人的场景下，单次目标选择耗时不超过 0.5ms

**核心接口**：
- `get_target(origin: Vector2, range: float, strategy: TargetStrategy) -> Node` — 返回当前最优攻击目标，无目标时返回 `null`

---

## 2. Player Fantasy

目标选择系统是**隐形的智能助手**——玩家不会直接与它交互，但每一次"攻击贴脸敌人"或"塔台精准清怪"的爽感都来源于它的判定。好的目标选择体验是：

- **猫咪自动打最近的敌人** → 感觉聪明又可爱，像一只守护主人的小猫
- **防御塔打进入射程的第一个威胁** → 感觉高效又有策略感，不浪费弹药
- **无缝切换目标** → 旧目标死亡后立刻切换到下一个，流畅无停顿

**情感目标**：**可靠感 + 流畅感**
- 玩家不需要手动点目标，系统自动选择"符合直觉的那个"
- 切换目标时无感知延迟，不出现"站桩等目标"的尴尬停顿
- 敌人死亡后 1 帧内完成目标刷新，攻击节奏不断档

**玩家不应该感受到**：
- "为什么打那么远的敌人，没打眼前这个？"
- "敌人都死完了，但猫还呆站着不动"
- 攻击目标闪烁或频繁切换（在多个等距敌人之间反复抖动）

**参考游戏**：
- **吸血鬼幸存者**：始终攻击当前最近的敌人，直觉一致，玩家专注走位而非纠结目标
- **塔防类游戏（如 BTD6）**：塔台默认打进入范围的第一个敌人，可切换为"最远"或"最强"策略

---

## 3. Detailed Design

### Core Rules

#### 1. 目标策略枚举（TargetStrategy）

```gdscript
## 目标选择策略枚举
## MVP 阶段仅实现 NEAREST，其余为预留扩展接口
enum TargetStrategy {
    NEAREST,       ## 最近敌人（默认，MVP实现）
    LOWEST_HP,     ## 最低血量（v1.0扩展）
    HIGHEST_HP,    ## 最高血量（v1.0扩展）
    FASTEST,       ## 移动速度最快（v1.0扩展）
    OLDEST,        ## 最早进入射程（v1.0扩展，用于塔防感的"第一个"策略）
}
```

**MVP 实现范围**：仅 `NEAREST`。其他策略保留枚举值，调用时若传入未实现策略，系统降级回退至 `NEAREST` 并输出一条警告日志。

#### 2. 目标选择主流程

```gdscript
## 目标选择系统主函数
## origin: 攻击发起者的全局坐标
## range:  攻击范围半径（像素）
## strategy: 目标策略，默认为 NEAREST
## 返回: 最优目标 Node；射程内无敌人时返回 null
func get_target(
    origin: Vector2,
    range: float,
    strategy: TargetStrategy = TargetStrategy.NEAREST
) -> Node:
    # 1. 调用碰撞检测系统查询候选敌人
    var candidates: Array[Node] = CollisionSystem.get_enemies_in_radius(origin, range)

    # 2. 过滤无效目标（已死亡、正在离场的敌人）
    candidates = candidates.filter(func(e): return _is_valid_target(e))

    # 3. 无有效目标，返回 null
    if candidates.is_empty():
        return null

    # 4. 按策略排序，取最优目标
    match strategy:
        TargetStrategy.NEAREST:
            return _select_nearest(origin, candidates)
        _:
            push_warning("TargetSystem: 策略 %d 尚未实现，降级为 NEAREST" % strategy)
            return _select_nearest(origin, candidates)

## 检查目标是否有效（存活、未在销毁队列中）
func _is_valid_target(enemy: Node) -> bool:
    return is_instance_valid(enemy) and not enemy.is_queued_for_deletion()

## NEAREST 策略：返回距离 origin 最近的敌人
func _select_nearest(origin: Vector2, candidates: Array[Node]) -> Node:
    var nearest: Node = null
    var min_dist_sq: float = INF  # 使用平方距离避免 sqrt，性能优化
    for enemy in candidates:
        var dist_sq: float = origin.distance_squared_to(enemy.global_position)
        if dist_sq < min_dist_sq:
            min_dist_sq = dist_sq
            nearest = enemy
    return nearest
```

#### 3. 调用规范

- **调用频率**：每个攻击者（猫咪英雄或防御塔）按各自的攻击冷却时间调用，而非每帧调用。不允许在 `_process()` 中每帧轮询。
- **调用时机**：在攻击冷却计时结束、准备发射下一次攻击时，调用一次 `get_target()`。
- **结果缓存**：调用者在攻击动画/弹丸飞行期间持有目标引用，弹丸命中前不重新查询（避免"子弹转向"怪象）。
- **目标失效检查**：弹丸命中时，自动攻击系统和防御塔系统需自行验证目标是否仍存活（`is_instance_valid` 检查），目标选择系统不保证目标在查询后的存活状态。

### States and Transitions

目标选择系统是**无状态的纯函数服务**，不持有任何持久状态，不需要状态机。每次 `get_target()` 调用都是完整、独立的一次查询。

| 系统状态 | 目标选择行为 |
|---------|-------------|
| **游戏运行中** | 正常响应 `get_target()` 调用 |
| **游戏暂停** | 调用者停止攻击冷却计时，不调用 `get_target()`，系统空闲 |
| **升级面板打开** | 同暂停，碰撞检测系统切换为 UI_Only 模式，即使调用也返回空列表 |
| **波次间隔** | 场景中无敌人，`get_enemies_in_radius()` 返回空列表，`get_target()` 返回 `null` |

### Interactions with Other Systems

| 系统 | 交互方向 | 数据流 | 说明 |
|-----|---------|--------|------|
| **碰撞检测系统** | 目标选择 → 碰撞检测 | 调用 `get_enemies_in_radius(origin, range)` | 获取候选敌人列表（上游硬依赖） |
| **碰撞检测系统** | 目标选择 → 碰撞检测 | 调用 `get_nearest_enemy(origin, range)` | 可选快捷路径（仅 NEAREST 策略） |
| **自动攻击系统** | 自动攻击 → 目标选择 | 调用 `get_target(cat_position, attack_range)` | 每次攻击冷却结束时查询目标（下游） |
| **防御塔系统** | 防御塔 → 目标选择 | 调用 `get_target(tower_position, tower_range, tower_strategy)` | 每次攻击冷却结束时查询目标（下游） |
| **敌人系统** | 敌人 → 目标选择（间接） | 敌人 Node 作为返回值传递 | 目标选择返回的 Node 即敌人实例 |

---

## 4. Formulas

### 目标优先级计算公式

**MVP（NEAREST 策略）**：

目标优先级由欧氏距离的平方决定，距离越小优先级越高：

```
priority_score = distance_squared(origin, enemy.global_position)
best_target = argmin(priority_score) over all valid candidates
```

使用平方距离而非实际距离，避免 `sqrt()` 运算，在 50-100 个候选时节省约 20-30% 计算时间。

**变量定义**：

| 变量 | 类型 | 说明 |
|-----|------|------|
| `origin` | `Vector2` | 攻击发起者全局坐标（像素） |
| `enemy.global_position` | `Vector2` | 候选敌人全局坐标（像素） |
| `priority_score` | `float` | 优先级得分（越小越优先） |
| `best_target` | `Node` | 最终选出的目标 |

**示例计算**：

```
猫咪位置: (200, 300)
候选敌人A: (250, 300) → distance_sq = (50)² + (0)²  = 2500
候选敌人B: (200, 260) → distance_sq = (0)²  + (40)² = 1600  ← 最优
候选敌人C: (240, 340) → distance_sq = (40)² + (40)² = 3200

结论: 选择敌人B（distance_sq = 1600 最小）
```

### 距离公式（参考对比）

**实际欧氏距离**（仅用于 UI 显示或需要真实距离时）：

```
distance = sqrt((x2 - x1)² + (y2 - y1)²)
```

GDScript 内置：`origin.distance_to(enemy.global_position)`

**平方距离**（目标选择内部比较，性能优先）：

```
distance_sq = (x2 - x1)² + (y2 - y1)²
```

GDScript 内置：`origin.distance_squared_to(enemy.global_position)`

**关键原则**：目标选择系统内部**只用平方距离做比较**，从不调用 `distance_to()`，除非业务上必须输出真实距离值。

### 策略扩展预留公式（v1.0，未实现）

| 策略 | 优先级公式 | 排序方向 |
|-----|-----------|---------|
| `LOWEST_HP` | `priority = enemy.current_hp` | 升序（最小优先） |
| `HIGHEST_HP` | `priority = enemy.current_hp` | 降序（最大优先） |
| `FASTEST` | `priority = enemy.move_speed` | 降序（最大优先） |
| `OLDEST` | `priority = enemy.time_in_range` | 降序（最大优先） |

---

## 5. Edge Cases

| # | 边界情况 | 触发条件 | 处理方式 |
|---|---------|---------|---------|
| EC-01 | **射程内无敌人** | 战场空旷或攻击者孤立 | `get_target()` 返回 `null`；调用者（自动攻击/防御塔）收到 `null` 后进入待机状态，不发出攻击 |
| EC-02 | **目标在查询后死亡** | 弹丸飞行期间目标被其他攻击击杀 | 目标选择系统不负责这一时序问题；由自动攻击系统/防御塔系统在命中时用 `is_instance_valid(target)` 自行验证 |
| EC-03 | **目标在查询后走出射程** | 目标查询时在范围内，弹丸到达时已离开 | 同 EC-02，弹丸命中判定由攻击系统负责；目标选择系统不跟踪目标移动 |
| EC-04 | **多个敌人完全等距** | 两个或多个敌人距 origin 的 `distance_sq` 完全相同 | 返回候选列表中遍历到的第一个（由 `get_enemies_in_radius` 的返回顺序决定）；不做随机，保证帧间稳定，防止目标在相邻帧间抖动切换 |
| EC-05 | **候选列表过大（超过查询上限）** | `get_enemies_in_radius` 最多返回 32 个结果（碰撞检测系统限制） | 在 32 个候选中选最优，接受"远处敌人不在候选池"的权衡；因 NEAREST 策略优先近距离，32 个上限在实践中不影响结果正确性 |
| EC-06 | **传入未实现的策略枚举值** | 调用者传入 `LOWEST_HP` 等 v1.0 策略 | 输出 `push_warning` 警告日志，降级为 `NEAREST` 策略执行，不抛出异常，保证运行时稳定 |
| EC-07 | **攻击范围为 0 或负数** | 调用者传入无效 `range` 参数 | `get_enemies_in_radius(origin, 0.0)` 返回空列表，`get_target()` 返回 `null`；加一条 `push_warning` 提示调用方检查参数 |
| EC-08 | **敌人 Node 存在但正在销毁中** | 敌人被标记为 `queue_free()` 但物理帧尚未实际移除 | `_is_valid_target()` 中用 `enemy.is_queued_for_deletion()` 过滤，不将该敌人纳入候选 |
| EC-09 | **游戏暂停期间被意外调用** | 调用者忘记在暂停时停止攻击计时器 | 碰撞检测系统在 `Paused` 状态下返回空列表，`get_target()` 安全返回 `null`，不造成崩溃 |

---

## 6. Dependencies

### 上游依赖（目标选择系统依赖的系统）

| 系统 | 依赖类型 | 依赖接口 | 说明 |
|-----|---------|---------|------|
| **碰撞检测系统** | 硬依赖 | `get_enemies_in_radius(center: Vector2, radius: float) -> Array[Node]` | 获取射程内所有候选敌人，是目标选择的数据来源 |
| **碰撞检测系统** | 软依赖（可选快捷路径） | `get_nearest_enemy(center: Vector2, max_range: float) -> Node` | NEAREST 策略可直接用此接口跳过手动遍历，但目前采用 `get_enemies_in_radius` + 内部遍历以保持策略扩展性 |

**Godot 引擎依赖**（由碰撞检测系统封装，目标选择系统不直接调用）：
- `PhysicsDirectSpaceState2D.intersect_shape()` — 区域查询底层实现
- `is_instance_valid(node)` — Node 存活验证

### 下游依赖（依赖目标选择系统的系统）

| 系统 | 依赖类型 | 调用接口 | 说明 |
|-----|---------|---------|------|
| **自动攻击系统** | 硬依赖 | `get_target(cat_pos, attack_range)` | 每次攻击冷却结束时调用，获取猫咪当前攻击目标 |
| **防御塔系统** | 硬依赖 | `get_target(tower_pos, tower_range, tower_strategy)` | 每次塔台攻击冷却结束时调用，支持按塔台配置不同策略 |

### GDScript 接口定义

```gdscript
## TargetSystem.gd
## 目标选择系统 — 全局 Autoload 单例
## 挂载路径: /root/TargetSystem

## 目标选择策略枚举
## MVP 阶段仅实现 NEAREST，其余为预留扩展
enum TargetStrategy {
    NEAREST,    ## 最近敌人（默认，MVP已实现）
    LOWEST_HP,  ## 最低血量（v1.0）
    HIGHEST_HP, ## 最高血量（v1.0）
    FASTEST,    ## 最快敌人（v1.0）
    OLDEST,     ## 最久在射程内的敌人（v1.0）
}

## 主查询接口
## origin:   攻击发起者全局坐标
## range:    攻击范围半径（像素）
## strategy: 目标优先策略，默认 NEAREST
## 返回:     最优目标 Node；射程内无有效目标时返回 null
func get_target(
    origin: Vector2,
    range: float,
    strategy: TargetStrategy = TargetStrategy.NEAREST
) -> Node

## 内部辅助方法（不对外暴露）
func _is_valid_target(enemy: Node) -> bool
func _select_nearest(origin: Vector2, candidates: Array[Node]) -> Node
```

**调用示例（自动攻击系统）**：

```gdscript
## auto_attack_system.gd 调用示例
func _on_attack_cooldown_timeout() -> void:
    var target: Node = TargetSystem.get_target(
        global_position,
        attack_range,
        TargetSystem.TargetStrategy.NEAREST
    )
    if target == null:
        return  # 无目标，进入待机，等待下次冷却触发
    _fire_at(target)

## 弹丸命中时验证目标仍存活（目标选择系统不负责此检查）
func _on_projectile_hit(target: Node) -> void:
    if not is_instance_valid(target):
        return  # 目标已销毁，丢弃命中事件
    DamageSystem.apply_damage(self, target, attack_data)
```

**调用示例（防御塔系统）**：

```gdscript
## tower_system.gd 调用示例
@export var target_strategy: TargetSystem.TargetStrategy = TargetSystem.TargetStrategy.NEAREST
@export var tower_range: float = 150.0

func _on_attack_timer_timeout() -> void:
    var target: Node = TargetSystem.get_target(
        global_position,
        tower_range,
        target_strategy
    )
    if target == null:
        return
    _launch_projectile(target)
```

---

## 7. Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 影响面 | 说明 |
|-------|------|-------|---------|-------|------|
| **default_strategy** | `TargetStrategy` | `NEAREST` | 枚举值 | 全局默认行为 | 修改后影响所有未显式指定策略的调用者；MVP 期间锁定为 `NEAREST` |
| **max_candidates** | `int` | `32` | `8 - 64` | 性能 / 准确性 | 透传自碰撞检测系统的 `query_max_results`，值越高精度越高但性能越低；超过 64 在 100 敌人场景下有帧率风险 |
| **tie_break_mode** | `enum` | `FIRST_IN_LIST` | `FIRST_IN_LIST / RANDOM` | 等距目标的一致性 | `FIRST_IN_LIST`：等距取第一个，帧间稳定；`RANDOM`：等距随机，防止"永远打同一只"但会导致抖动，MVP 默认 `FIRST_IN_LIST` |
| **validity_check_enabled** | `bool` | `true` | `true / false` | 防御性编程 / 性能 | 关闭时跳过 `_is_valid_target()` 过滤，减少一轮遍历；仅在性能压测时临时关闭，生产环境必须开启 |

**参数交互说明**：
- `max_candidates` 与碰撞检测系统的 `query_max_results` 共享上限，修改需同步通知碰撞检测系统文档
- `tie_break_mode = RANDOM` 会导致等距场景下同一攻击者在连续两帧选择不同目标，产生视觉抖动，MVP 阶段禁止使用

---

## 8. Acceptance Criteria

### 功能测试

| ID | 测试项 | 前置条件 | 操作步骤 | Pass 标准 |
|----|-------|---------|---------|----------|
| AC-01 | 基本目标返回 | 射程内有 1 个敌人 | 调用 `get_target(origin, range)` | 返回该敌人 Node，非 `null` |
| AC-02 | 无敌人时返回 null | 射程内无任何敌人 | 调用 `get_target(origin, range)` | 返回 `null` |
| AC-03 | NEAREST 策略选最近目标 | 射程内有 3 个不等距敌人（A=50px, B=80px, C=30px） | 调用 `get_target(origin, range, NEAREST)` | 返回 C（distance = 30px） |
| AC-04 | 目标有效性过滤 | 射程内有 2 个敌人，其中 1 个 `queue_free()` | 调用 `get_target(origin, range)` | 返回存活的那个敌人 |
| AC-05 | 未实现策略降级 | 传入 `LOWEST_HP` 策略，射程内有 2 个敌人 | 调用 `get_target(origin, range, LOWEST_HP)` | 返回距离最近的敌人（降级为 NEAREST），且输出一条 warning 日志 |
| AC-06 | 等距目标稳定性 | 射程内有 2 个敌人与 origin 距离完全相同（`distance_sq` 相等） | 连续调用 `get_target()` 10 次 | 每次返回同一个目标（不抖动） |
| AC-07 | 范围为 0 时返回 null | 射程内有敌人，但传入 `range = 0.0` | 调用 `get_target(origin, 0.0)` | 返回 `null`，输出 warning |
| AC-08 | 自动攻击集成 | 自动攻击系统冷却结束，射程内有 3 个敌人 | 等待一次攻击冷却触发 | 自动攻击系统调用 `get_target()` 并攻击返回的最近敌人 |
| AC-09 | 防御塔集成 | 防御塔冷却结束，射程内有 2 个敌人 | 等待一次塔台攻击冷却触发 | 防御塔攻击返回的最近敌人 |
| AC-10 | 目标死亡后切换 | 攻击的目标被击杀（`queue_free`） | 等待下一次攻击冷却触发 | 攻击系统调用 `get_target()` 后返回新目标，无卡顿 |

### 性能测试

| ID | 测试项 | 测试场景 | 操作 | Pass 标准 |
|----|-------|---------|------|----------|
| AC-11 | 50 敌人场景单次查询时间 | 场景中 50 个移动敌人，猫咪位于中心 | 调用 `get_target()` 100 次，取均值 | 单次调用均值 < 0.3ms |
| AC-12 | 100 敌人场景单次查询时间 | 场景中 100 个移动敌人，猫咪位于中心 | 调用 `get_target()` 100 次，取均值 | 单次调用均值 < 0.5ms |
| AC-13 | 4 防御塔同帧并发查询 | 100 个敌人，4 座防御塔同时触发攻击冷却 | 同一物理帧内触发 4 次 `get_target()` 调用 | 4 次调用总耗时 < 1ms，帧率不低于 58 FPS |
| AC-14 | 帧率稳定性（压力） | 100 个敌人，猫咪 + 4 防御塔持续攻击 | 运行 60 秒持续战斗 | 全程帧率 ≥ 60 FPS，无单帧超过 20ms |

### 边界测试

| ID | 测试项 | 操作 | Pass 标准 |
|----|-------|------|----------|
| AC-15 | 全部候选均已 `queue_free` | 射程内 5 个敌人，全部标记 `queue_free` 后调用 `get_target()` | 返回 `null`，不崩溃 |
| AC-16 | `range` 传入负数 | 调用 `get_target(origin, -50.0)` | 返回 `null`，输出 warning，不崩溃 |
| AC-17 | 候选数量达到上限（32） | 射程内放置 40 个敌人 | `get_target()` 正常返回 32 个候选中的最近目标，不返回错误 |

---

*本文档覆盖目标选择系统 MVP 阶段的完整设计规格。v1.0 扩展策略（`LOWEST_HP`、`FASTEST` 等）在枚举中已预留，实现时需同步更新本文档第 3、4、8 章节。*