# 移动系统 (Movement System)

> **Status**: Approved
> **Author**: [user + agents]
> **Last Updated**: 2026-04-02
> **Implements Pillar**: 成长的爽感（速度升级可感知）、策略有深度（走位是核心决策）

---

## 1. Overview

移动系统负责驱动猫咪英雄在地图上的物理位移。它消费来自输入系统的 `movement_direction: Vector2`，将归一化方向向量乘以当前速度，每帧将猫咪推进到新位置，并在边界处将猫咪限制在地图范围内，绝不允许英雄走出地图。

系统管理两层速度：**基础速度**（固定配置值）和**升级加成**（可叠加的百分比加成），二者共同决定每帧的实际位移量。当输入系统进入 UI_Open 状态时，输出方向自动变为 `(0, 0)`，移动系统直接响应该零向量，无需感知 UI 状态，保持职责单一。

移动系统是玩家唯一可直接掌控的位置信息来源——地图边界碰撞、敌人追逐目标、攻击射程锚点，全部以英雄位置为基准。移动手感的好坏直接影响玩家对"掌控感"的认知，是核心玩法体验的地基。

**输出接口**：
- `hero_position: Vector2` — 当前帧结束后的全局坐标，供敌人系统和自动攻击系统查询

---

## 2. Player Fantasy

**情感目标：掌控感 + 流畅感 + 速度升级的爽感**

移动手感应当"即时、轻盈、精准"——玩家按下按键，猫咪立刻响应，松开按键，猫咪立刻停止，零惯性、零加速度曲线。这种设计让玩家专注于"往哪儿走"的策略决策，而非"怎么走"的操作技巧，符合"不做复杂操作"的反支柱原则。

**玩家应该感受到**：
- 按键 → 猫咪立即移动，响应无延迟
- 拿到速度升级 → 明显感觉"快了一截"，不只是数字变化
- 走到地图边缘 → 猫咪被挡住，但不会卡死或抖动
- 斜向移动 → 与正向移动完全一样的速度，不会有"斜向加速"的不公平感

**玩家不应该感受到**：
- 滑步、惯性、起步延迟
- 斜向比正向快（会破坏平衡）
- 被地图边界弹飞或穿透地图
- 速度升级后手感变"重"或变"漂"

---

## 3. Detailed Design

### Core Rules

#### 规则 1：即时响应，无惯性

移动系统不模拟加速度或摩擦力。每帧的位移完全由当前帧的输入方向决定：

- 输入方向非零 → 按当前速度立即移动
- 输入方向为零 → 立即停止，位移为 0

这是 Survivors 类游戏的标准手感，让玩家在密集敌群中能精确掌控位置。

#### 规则 2：斜向速度归一化

输入系统已对 `movement_direction` 做归一化处理，但移动系统自身也须在使用前再次调用 `.normalized()`，以防止上游异常输入（如调试模式、未来的新输入源）导致斜向速度超标。

- 正向移动：方向长度 = 1.0，速度 = base_speed × speed_multiplier
- 斜向移动：方向长度归一化至 1.0，速度 = base_speed × speed_multiplier（完全相同）
- 零向量：跳过移动逻辑，不计算位移

#### 规则 3：边界碰撞——钳制而非弹射

猫咪碰到地图边界后，位置被钳制（clamp）在合法范围内：

- 水平方向超出 → 水平坐标被截断，垂直方向仍可继续移动
- 垂直方向超出 → 垂直坐标被截断，水平方向仍可继续移动
- 同时超出两个方向 → 两个方向都被截断，猫咪保持在角落位置

**不使用物理反弹**：弹射会让玩家失去对位置的预期控制，触碰边界时应像"撞上了一堵墙"——自然停下，不产生意外位移。

#### 规则 4：速度升级叠加方式

速度升级使用**加法叠加百分比**，而非乘法叠加：

```
speed_multiplier = 1.0 + Σ(speed_upgrade_bonus_i)
```

例如：拿了 2 次 "+20% 速度" 升级 → speed_multiplier = 1.0 + 0.20 + 0.20 = 1.40

**选用加法而非乘法的理由**：加法叠加使每次升级的边际收益线性递减（第5次加20%的体感不如第1次明显），避免后期速度失控。

#### 规则 5：碰撞体与渲染分离

移动系统操作的是 `CharacterBody2D` 的物理位置（`global_position`），而非精灵的渲染位置。精灵跟随碰撞体位置，不独立移动。移动系统不直接操作任何 `Sprite2D` 或 `AnimatedSprite2D` 节点。

---

### States and Transitions

移动系统本身是无状态的（Stateless）——它不维护状态机，每帧只根据输入向量和速度参数执行计算。"移动/停止"状态由输入决定，"速度加成"状态由升级系统外部修改。

| 外部条件 | 移动系统行为 | 说明 |
|---------|------------|------|
| `movement_direction == (0, 0)` | 原地静止，不产生位移 | 包括 UI_Open 状态、无按键输入 |
| `movement_direction != (0, 0)` | 按归一化方向和当前速度移动 | 正常游戏状态 |
| 英雄位置在地图内 | 正常移动 | 无边界干预 |
| 英雄位置即将超出边界 | 钳制后应用位置 | 不产生反弹 |
| 英雄升级获得速度加成 | `speed_multiplier` 更新，当帧即生效 | 外部调用接口 |

**状态图**（描述输入到位置更新的单帧流程）：

```
_physics_process(delta)
        │
        ▼
movement_direction = input_system.get_direction()
        │
        ├─[== (0,0)]──→ 跳过位移计算 → 保持原位置
        │
        └─[!= (0,0)]──→ 归一化方向
                              │
                              ▼
                        计算速度 = base_speed × speed_multiplier
                              │
                              ▼
                        计算目标位置 = position + direction × speed × delta
                              │
                              ▼
                        钳制目标位置到地图边界
                              │
                              ▼
                        应用位置 → move_and_collide() 或直接赋值 global_position
```

---

### Interactions with Other Systems

| 系统 | 交互方向 | 数据流 | 说明 |
|-----|---------|--------|------|
| **输入系统** | 输入 → 移动 | `movement_direction: Vector2` | 每帧读取，驱动位移方向 |
| **地图系统** | 地图 → 移动 | `map_bounds: Rect2` | 初始化时读取一次，用于边界钳制 |
| **升级选择系统** | 升级 → 移动 | `add_speed_bonus(float)` | 玩家选择速度升级时调用，累加 speed_multiplier |
| **敌人系统** | 移动 → 敌人 | `hero_position: Vector2`（只读） | 敌人系统每帧查询英雄全局位置以追踪目标 |
| **自动攻击系统** | 移动 → 攻击 | `hero_position: Vector2`（只读） | 攻击以英雄位置为原点，查询最近敌人 |
| **UI 系统** | UI → 移动 | 无直接调用 | UI_Open 状态由输入系统将 direction 置为 (0,0) 来间接停止移动 |

---

## 4. Formulas

### 公式 1：每帧位移计算

```
velocity = movement_direction.normalized() × base_speed × speed_multiplier
new_position = current_position + velocity × delta
```

**变量定义**：

| 变量 | 类型 | 单位 | 说明 |
|-----|------|------|------|
| `movement_direction` | Vector2 | 无量纲 | 来自输入系统，已归一化，范围 `[-1, 1] × [-1, 1]` |
| `base_speed` | float | 像素/秒 | 基础移动速度，不可升级修改的固定值 |
| `speed_multiplier` | float | 无量纲 | 速度倍率，初始值 1.0，升级后叠加 |
| `delta` | float | 秒 | 帧时间，60FPS 时约为 0.01667 |
| `velocity` | Vector2 | 像素/秒 | 本帧实际速度向量 |
| `new_position` | Vector2 | 像素 | 应用边界钳制之前的目标位置 |

**示例计算**（60FPS，正向移动，base_speed = 200，speed_multiplier = 1.0）：
```
movement_direction = (1, 0)
velocity = (1, 0) × 200 × 1.0 = (200, 0)
new_position.x = current_x + 200 × 0.01667 = current_x + 3.33 像素/帧
```

**示例计算**（斜向移动，参数同上）：
```
movement_direction = (0.707, 0.707)    # 已归一化，长度 = 1.0
velocity = (0.707, 0.707) × 200 × 1.0 = (141.4, 141.4)
|velocity| = sqrt(141.4² + 141.4²) = sqrt(2 × 141.4²) = 200  # 与正向相同
```

---

### 公式 2：速度叠加计算

```
speed_multiplier = 1.0 + Σ(speed_upgrade_bonus_i)
                 = 1.0 + speed_bonus_1 + speed_bonus_2 + ... + speed_bonus_n
```

**变量定义**：

| 变量 | 类型 | 范围 | 说明 |
|-----|------|------|------|
| `speed_upgrade_bonus_i` | float | `[0.05, 0.50]` 每次 | 单次速度升级的加成比例 |
| `speed_multiplier` | float | `[1.0, 2.5]` 上限钳制 | 最终速度倍率，超过上限时截断 |

**示例计算**（获得 3 次速度升级，每次 +20%）：
```
speed_multiplier = 1.0 + 0.20 + 0.20 + 0.20 = 1.60
实际速度 = 200 × 1.60 = 320 像素/秒
```

---

### 公式 3：边界钳制

地图系统提供一个 `Rect2` 表示合法区域，英雄碰撞体的半径为 `hero_radius`：

```
# 合法位置范围（考虑英雄碰撞半径，防止精灵贴边穿透）
min_x = map_bounds.position.x + hero_radius
max_x = map_bounds.position.x + map_bounds.size.x - hero_radius
min_y = map_bounds.position.y + hero_radius
max_y = map_bounds.position.y + map_bounds.size.y - hero_radius

# 钳制
clamped_x = clamp(new_position.x, min_x, max_x)
clamped_y = clamp(new_position.y, min_y, max_y)
final_position = Vector2(clamped_x, clamped_y)
```

**变量定义**：

| 变量 | 类型 | 说明 |
|-----|------|------|
| `map_bounds` | Rect2 | 地图可行走区域的矩形，由地图系统提供 |
| `hero_radius` | float | 英雄碰撞体的近似半径（像素），默认 16px |
| `final_position` | Vector2 | 钳制后的最终位置，直接赋给 `global_position` |

**示例计算**（地图尺寸 1280×720，hero_radius = 16）：
```
min_x = 0 + 16 = 16
max_x = 0 + 1280 - 16 = 1264
min_y = 0 + 16 = 16
max_y = 0 + 720 - 16 = 704

若目标位置 = (1300, 400) → 钳制为 (1264, 400)  # 右边界碰撞
若目标位置 = (-5, -5) → 钳制为 (16, 16)         # 左上角碰撞
```

---

## 5. Edge Cases

### EC-01：零向量输入（停止移动）

**场景**：无按键输入，或 UI_Open 状态，或 W+S / A+D 同时按下（输入系统已处理，输出 (0,0)）

**处理**：检测到 `movement_direction.is_zero_approx()` 时，跳过所有位移计算，`global_position` 不变。

**绝不做**：用零向量做归一化（`Vector2(0,0).normalized()` 在 Godot 中返回 `(0,0)`，不会崩溃，但代码应在前置判断中显式跳过）。

---

### EC-02：speed_multiplier 达到上限（2.5×）

**场景**：玩家多次选取速度升级，speed_multiplier 超过 2.5

**处理**：在 `add_speed_bonus()` 中对 `speed_multiplier` 执行 `clamp(value, 1.0, MAX_SPEED_MULTIPLIER)`，超过上限时截断，并向调用方返回实际生效的加成量（可能小于请求量）。

**结果**：`320 × 2.5 = 800 像素/秒` 是速度上限，防止英雄在一帧内跨越过长距离导致穿透碰撞检测。

---

### EC-03：地图边界数据尚未初始化

**场景**：地图系统尚未提供 `map_bounds`（如场景加载顺序问题）

**处理**：`MovementSystem` 在 `_ready()` 中向地图系统请求边界数据，若数据为空则使用一个保守的默认边界（整个 `Viewport` 尺寸），并在调试模式下打印警告。正式游戏不应触发此情况。

---

### EC-04：英雄已经在地图边界外（异常初始位置）

**场景**：场景初始化时英雄节点被放置在地图范围外（设计失误）

**处理**：移动系统在 `_ready()` 中执行一次边界钳制，强制将英雄校正到合法位置。这确保即使场景配置有误，运行时也能自我修复。

---

### EC-05：delta 值异常（帧卡顿）

**场景**：某一帧极度卡顿，delta 值超出正常范围（如 delta = 1.0 秒）

**处理**：对 delta 做上限钳制：`capped_delta = min(delta, MAX_DELTA)`，`MAX_DELTA = 0.05`（约等于 20FPS 等效值）。这防止单帧位移过大导致英雄"穿越"地图边界钳制区域。

---

### EC-06：速度升级在移动过程中实时触发

**场景**：升级选择系统在非 UI 状态下（理论上不应发生）触发速度加成

**处理**：`add_speed_bonus()` 接口是线程安全的简单加法，当帧即时生效。移动系统无需处理"过渡动画"——速度数值直接跳变，符合 Survivors 类游戏的设计惯例（升级后立刻感受到变化）。

---

### EC-07：负数或超范围的 speed_upgrade_bonus 输入

**场景**：升级选择系统传入负数速度加成（降速 debuff，暂未设计但需防御性编程）

**处理**：`add_speed_bonus()` 接受负数，但 `speed_multiplier` 的最低值钳制为 `MIN_SPEED_MULTIPLIER = 0.5`（最多减速到基础速度的 50%），防止速度变为零或负数。

---

## 6. Dependencies

### 上游依赖（移动系统依赖的系统）

| 系统 | 依赖类型 | 接口 | 获取时机 |
|-----|---------|------|---------|
| **输入系统** | 硬依赖 | `InputSystem.get_movement_direction() → Vector2` | 每帧 `_physics_process()` |
| **地图系统** | 硬依赖 | `MapSystem.get_map_bounds() → Rect2` | `_ready()` 时一次性读取，并监听 `map_bounds_changed` 信号 |

### 下游依赖（依赖移动系统的系统）

| 系统 | 依赖类型 | 接口 | 访问方式 |
|-----|---------|------|---------|
| **敌人系统** | 软依赖（只读） | 直接访问英雄节点的 `global_position` | 组（Group）查询：`get_tree().get_first_node_in_group("hero")` |
| **自动攻击系统** | 软依赖（只读） | 直接访问英雄节点的 `global_position` | 同上 |

> "软依赖"指下游系统读取数据但不调用函数，无需移动系统主动推送。

### GDScript 接口定义

```gdscript
# ============================================================
# MovementSystem — 移动系统公开接口
# 文件: src/core/movement/movement_system.gd
# ============================================================
class_name MovementSystem
extends Node


# --- 信号 ---

## 英雄位置发生变化时广播（可选：如需事件驱动可开启）
signal position_changed(new_position: Vector2)


# --- 导出变量（Tuning Knobs，可在 Inspector 中调整）---

## 基础移动速度（像素/秒）
@export var base_speed: float = 200.0

## 速度倍率上限（防止速度失控）
@export var MAX_SPEED_MULTIPLIER: float = 2.5

## 速度倍率下限（防止降速 debuff 导致速度为零）
@export var MIN_SPEED_MULTIPLIER: float = 0.5

## delta 上限（秒），防止卡顿帧导致异常大位移
@export var MAX_DELTA: float = 0.05

## 英雄碰撞半径（像素），用于边界钳制内缩
@export var hero_radius: float = 16.0


# --- 公开只读属性 ---

## 当前速度倍率（外部只读）
var speed_multiplier: float = 1.0 :
    get:
        return speed_multiplier
    set(value):
        push_error("MovementSystem: speed_multiplier 只读，请使用 add_speed_bonus()")


# --- 公开方法 ---

## 初始化：注入地图边界数据（由地图系统在 ready 后调用）
func initialize(bounds: Rect2) -> void:
    pass


## 添加速度升级加成（百分比，如 0.20 代表 +20%）
## 返回实际生效的加成量（受上限钳制可能小于输入值）
func add_speed_bonus(bonus: float) -> float:
    pass


## 查询当前英雄世界坐标（供敌人系统、攻击系统调用）
func get_hero_position() -> Vector2:
    pass


## 重置速度倍率到初始值（用于新局开始）
func reset_speed() -> void:
    pass


# --- 内部方法（_physics_process）---

func _physics_process(delta: float) -> void:
    # 1. 读取输入方向
    # 2. 零向量提前返回
    # 3. 归一化（防御性）
    # 4. 计算位移
    # 5. 钳制 delta
    # 6. 应用边界钳制
    # 7. 更新 global_position
    pass
```

---

## 7. Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 影响 |
|-------|------|-------|---------|------|
| `base_speed` | float | 200.0 | 120 – 300 | 基础手感。低于 120 感觉"太慢沉闷"；高于 300 感觉"难以控制、频繁碰边"。推荐 180-240。 |
| `MAX_SPEED_MULTIPLIER` | float | 2.5 | 1.5 – 3.0 | 速度升级天花板。低于 1.5 使速度升级无意义；高于 3.0 英雄速度过快，敌人追不上，失去压迫感。 |
| `MIN_SPEED_MULTIPLIER` | float | 0.5 | 0.3 – 0.8 | 降速 debuff 下限（MVP 未使用）。低于 0.3 等于几乎不能移动，体验极差。 |
| `MAX_DELTA` | float | 0.05 | 0.033 – 0.1 | 卡顿帧保护。0.033 ≈ 30FPS 等效值，0.1 ≈ 10FPS 等效值。正常不触发。 |
| `hero_radius` | float | 16.0 | 8 – 24 | 边界内缩半径。需与美术精灵碰撞体尺寸匹配。过小会导致精灵超出地图可见范围；过大会导致玩家感觉被"无形墙"拦住。 |
| `speed_upgrade_bonus` | float | 0.20 (每次) | 0.05 – 0.50 (每次) | 单次速度升级的加成量（在升级池系统中配置，移动系统只消费）。低于 0.05 玩家几乎感觉不到；高于 0.50 单次升级太强，降低其他升级的吸引力。 |

**参数交互说明**：
- `base_speed × MAX_SPEED_MULTIPLIER = 200 × 2.5 = 500 像素/秒` 是英雄绝对速度上限
- `hero_radius` 须与地图系统提供的 `map_bounds` 配合——地图太小+hero_radius 太大会导致英雄无法移动
- `MAX_DELTA` 只在极端卡顿时生效，正常游玩不影响手感

**极端值测试**：
- `base_speed = 50` → 英雄移动缓慢，无法有效躲避敌人，游戏不可玩 — 不推荐
- `MAX_SPEED_MULTIPLIER = 5.0` → 全速后英雄一帧跨越大半地图，边界碰撞失效 — 不推荐
- `hero_radius = 0` → 英雄精灵可以完全贴边/半身出界，视觉效果破坏沉浸感 — 不推荐

---

## 8. Acceptance Criteria

### 功能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-MOV-01 | 正向移动（四方向） | 分别按下 W / S / A / D，观察猫咪移动方向 | 向上 / 向下 / 向左 / 向右，方向与按键一致，无延迟 |
| AC-MOV-02 | 斜向移动速度归一化 | 同时按下 W+D，用帧计数器记录猫咪从 A 点到 B 点的帧数；再按 D 单独走相同水平距离 | 斜向移动的实际速度（位移量/帧）等于正向速度，误差 < 1%（由归一化保证） |
| AC-MOV-03 | 松键立即停止 | 按下 D 移动后立即松开 | 猫咪在松键帧立即停止，位置不再变化，无滑步 |
| AC-MOV-04 | 地图边界阻挡（右边界） | 持续按 D 直到碰右侧边界 | 猫咪停在边界处，不穿透，垂直方向仍可移动（按 W/S 有效） |
| AC-MOV-05 | 地图边界阻挡（角落） | 移动到地图右下角后分别按 W / A | 猫咪从角落正常移出，无卡死或抖动 |
| AC-MOV-06 | UI 面板打开时移动停止 | 打开升级选择面板后按 WASD | 猫咪不产生任何位移，位置保持不变 |
| AC-MOV-07 | UI 面板关闭后移动恢复 | 关闭升级选择面板后立即按 D | 猫咪立即向右移动，响应正常 |

### 速度升级测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-MOV-08 | 速度升级生效 | 选择 "+20% 速度" 升级前后，在相同距离上记录移动时间 | 升级后到达相同位置的时间减少 ≈ 16.7%（1/1.20），误差 < 2% |
| AC-MOV-09 | 速度升级叠加（加法） | 连续选择 3 次 "+20% 速度"，验证最终速度 | 最终速度 = base_speed × 1.60（不是 × 1.728），为加法叠加 |
| AC-MOV-10 | 速度上限钳制 | 通过调试接口将 speed_multiplier 强制设为 3.0（超过上限 2.5） | 实际 speed_multiplier 被钳制为 2.5，猫咪速度为 base_speed × 2.5 |

### 边界测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-MOV-11 | 帧卡顿保护（MAX_DELTA） | 通过调试接口模拟 delta = 0.5 秒的单帧 | 该帧位移量 ≤ base_speed × speed_multiplier × 0.05（MAX_DELTA），不穿透边界 |
| AC-MOV-12 | hero_radius 内缩正确 | 将猫咪移动到右边界，截图检查精灵与地图边缘的关系 | 猫咪精灵不超出地图可见范围，视觉上完整显示在地图内 |
| AC-MOV-13 | 初始位置边界校正 | 将场景中猫咪节点手动放置在地图范围外，运行游戏 | 游戏启动时猫咪被自动校正到地图边界内，控制台输出一次警告 |

### 性能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-MOV-14 | 移动计算帧预算 | Godot Profiler 记录 `_physics_process` 中移动逻辑的耗时 | 单帧移动计算耗时 < 0.1ms（目标帧预算 16.6ms 的 < 0.6%） |
| AC-MOV-15 | 60FPS 下手感流畅 | 在 60FPS 下持续移动 30 秒，观察是否有卡顿或跳帧 | 视觉上平滑，无可感知的抖动或帧间位移不一致 |

### 集成测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-MOV-16 | 敌人系统获取英雄位置 | 运行完整游戏循环，检查敌人是否持续追踪英雄 | 所有敌人的移动目标始终与英雄当前帧位置一致，无一帧延迟 |
| AC-MOV-17 | 速度升级端到端 | 在完整游戏循环中选择速度升级，检查英雄移动速度变化 | 升级选择面板关闭后第一帧，英雄速度即反映新的 speed_multiplier |

---

## Open Questions

- [ ] **Q1**：地图是否有内部障碍物（如柱子、墙壁）？若有，移动系统需要支持非矩形碰撞，当前设计仅支持 `Rect2` 矩形边界。建议 MVP 阶段保持矩形边界，障碍物由碰撞检测系统处理。
- [ ] **Q2**：速度升级是否存在降速 debuff（如被特殊敌人减速）？若存在，需确认 `MIN_SPEED_MULTIPLIER = 0.5` 是否合适，以及 debuff 的持续时间处理逻辑（当前系统无时效性加成支持）。
- [ ] **Q3**：猫咪英雄是否需要冲刺（Dash）能力？若是，冲刺应作为独立状态加入此系统，还是作为独立系统实现？建议 v1.0 阶段评估。
