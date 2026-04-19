# 输入系统 (Input System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-15
> **Implements Pillar**: 简化操作（Anti-Pillar: 不做复杂操作）

---

## Overview

输入系统负责接收玩家的键盘和鼠标输入，转换为游戏可用的控制信号。玩家通过 **WASD 键盘八方向移动** 控制猫咪英雄在战场上的位置，**鼠标** 用于塔位选择、升级面板交互和 UI 操作。

这是所有玩家控制的基础设施。没有它，玩家无法执行核心循环中的"移动定位"策略——找到能攻击最多敌人同时不被包围的最佳位置。输入系统必须足够简单直观，符合游戏的"不做复杂操作"原则，让玩家专注于策略决策而非操作技巧。

**输出接口**:
- `movement_direction: Vector2` — 移动系统消费，驱动猫咪位置变化
- `tower_place_signal: bool` — 塔位放置系统消费，触发塔位交互
- `ui_interaction_signal: bool` — UI系统消费，处理菜单/面板交互

---

## Player Fantasy

输入系统是透明的基础设施——玩家不应该"意识到"输入的存在。好的输入体验是：按下按键，猫咪立即流畅响应，没有延迟、没有卡顿、不需要思考操作方式。

**情感目标**: **掌控感 + 流畅感**
- 按下 WASD → 猫咪立即向对应方向移动
- 鼠标悬停塔位 → 立即显示"可放置"提示
- 所有输入响应延迟 < 16ms（一帧内处理）

**玩家不应该感受到**: 按键冲突、输入延迟、复杂的组合键操作。这与"不做复杂操作"原则一致——输入是直觉的，策略在"往哪走"而非"怎么走"。

---

## Detailed Design

### Core Rules

#### 1. 键盘输入处理 (WASD 八方向)

| 按键组合 | 输出方向 Vector2 |
|---------|-----------------|
| W 单独 | (0, -1) — 向上 |
| S 单独 | (0, 1) — 向下 |
| A 单独 | (-1, 0) — 向左 |
| D 单独 | (1, 0) — 向右 |
| W+A | (-0.707, -0.707) — 左上 |
| W+D | (0.707, -0.707) — 右上 |
| S+A | (-0.707, 0.707) — 左下 |
| S+D | (0.707, 0.707) — 右下 |
| 无按键 | (0, 0) — 停止 |

**归一化规则**: 八方向输出向量已归一化为长度 1.0，斜向使用 `sqrt(2)/2 ≈ 0.707`。

#### 2. 鼠标输入处理

| 事件 | 输出信号 |
|-----|---------|
| 鼠标悬停塔位区域 | `hover_tower_slot_signal: true` + `slot_id` |
| 鼠标点击塔位区域 | `tower_place_signal: true` + `slot_id` |
| 鼠标悬停 UI 按钮 | `hover_ui_signal: true` + `button_id` |
| 鼠标点击 UI 按钮 | `ui_click_signal: true` + `button_id` |
| 鼠标悬停游戏区域（非塔位） | 无信号输出 |

#### 3. 输入优先级

当多个输入同时触发时，按优先级处理：

| 优先级 | 输入类型 | 说明 |
|--------|---------|------|
| 1 (最高) | UI交互 | 升级选择面板打开时，键盘移动暂停 |
| 2 | 塔位放置 | 点击塔位时，移动继续但塔位交互优先处理 |
| 3 (最低) | 移动 | 默认状态，持续处理 WASD |

**规则**: UI面板打开时，移动输入**暂停**而非继续。这是为了让玩家在升级选择时专注于决策，不会意外移动到危险位置。

### States and Transitions

#### 状态定义

| 状态 | 描述 | 处理的输入 | 输出信号 |
|-----|------|----------|---------|
| **Normal** | 正常游戏状态 | WASD移动 + 鼠标塔位 | movement_direction, tower_place_signal |
| **UI_Open** | 升级选择面板打开 | 鼠标点击选择 | ui_click_signal（选择升级） |
| **Paused** | 游戏暂停（如结算） | 无输入处理 | 无输出 |
| **Tutorial** | 新手引导状态 | WASD移动（可能受限） | movement_direction（受限） |

#### 状态转换规则

| 当前状态 | 触发事件 | 目标状态 |
|---------|---------|---------|
| Normal | 升级选择触发 | UI_Open |
| Normal | 游戏暂停 | Paused |
| UI_Open | 选择升级完成 | Normal |
| UI_Open | 按ESC取消 | Normal（返回游戏） |
| Paused | 游戏恢复 | Normal |
| Tutorial | 教学完成 | Normal |

#### 状态图

```
Normal ──[升级触发]──> UI_Open ──[选择完成]──> Normal
   │                      │
   │                   [ESC]
   │                      ↓
   └──[暂停]──> Paused ──[恢复]──> Normal
   │
[Tutorial完成]
   ↓
Normal
```

### Interactions with Other Systems

| 系统 | 交互方向 | 数据流 | 说明 |
|-----|---------|--------|------|
| **移动系统** | 输入 → 移动 | `movement_direction: Vector2` | 每帧传递方向向量，移动系统计算位移 |
| **塔位放置系统** | 输入 → 塔位 | `tower_place_signal: bool + slot_id` | 点击塔位触发放置流程 |
| **UI系统** | 输入 → UI | `ui_click_signal: bool + button_id` | UI按钮点击交互 |
| **经验系统** | XP → 输入 | `level_up_requested: bool` | 角色升级触发升级面板 → 输入切换到 UI_Open 状态 |
| **塔改造系统** | 改造 → 输入 | `mod_offer_triggered: bool` | 精英 / Boss 奖励触发改造面板 → 输入切换到 UI_Open 状态 |
| **结算系统** | 结算 → 输入 | `game_paused: bool` | 结算触发暂停状态 |

---

## Formulas

### 1. 方向向量计算

**输入**: 当前帧按下的 WASD 按键组合
**输出**: 归一化的移动方向向量

```
direction_x = (D_pressed ? 1 : 0) - (A_pressed ? 1 : 0)
direction_y = (S_pressed ? 1 : 0) - (W_pressed ? 1 : 0)

if direction_x != 0 AND direction_y != 0:
    # 斜向移动，需要归一化
    movement_direction = Vector2(direction_x, direction_y).normalized()
else:
    # 正向移动，已经是单位向量
    movement_direction = Vector2(direction_x, direction_y)
```

**归一化公式**:
- 斜向向量长度 = `sqrt(direction_x² + direction_y²) = sqrt(1 + 1) = sqrt(2)`
- 归一化后: `(direction_x / sqrt(2), direction_y / sqrt(2)) ≈ (0.707, 0.707)`

### 2. 响应延迟计算

**公式**: `input_latency = frame_time + processing_time`

**目标值**:
- `input_latency < 16.67ms`（一帧内处理完成）
- Godot 的 `_process()` 或 `_input()` 回调保证在一帧内处理

### 3. 无公式计算的系统

以下系统不需要公式：
- 鼠标位置检测 — 使用 Godot 的 `get_global_mouse_position()` 和碰撞检测
- 信号触发 — 直接布尔值传递，无计算

---

## Edge Cases

### 1. 按键冲突处理

| 边界情况 | 处理方式 |
|---------|---------|
| 同时按下 W+S 或 A+D（相反方向） | 输出 (0, 0) — 停止移动，不移动 |
| 按键顺序混乱（快速切换） | 每帧重新计算，始终使用当前帧的按键状态 |
| 按键粘连（物理按键问题） | 使用 Godot 的 `is_action_pressed()` 检测，忽略重复按下 |

### 2. 鼠标边界情况

| 边界情况 | 处理方式 |
|---------|---------|
| 鼠标移出游戏窗口 | 不输出任何信号，游戏继续运行 |
| 同时点击多个塔位 | 只处理第一个点击，后续点击在当前交互完成后才处理 |
| 鼠标在塔位边缘（碰撞边界） | 使用碰撞检测的 `enclosed` 检测，需要鼠标中心进入塔位区域才触发 |

### 3. 状态边界情况

| 边界情况 | 处理方式 |
|---------|---------|
| UI_Open 状态下按 WASD | 不处理移动输入，玩家保持原地 |
| Normal 状态下按 ESC | 如果没有升级面板，ESC 暂停游戏（打开暂停菜单） |
| Tutorial 状态下尝试移动到禁止区域 | 输入系统输出方向，但移动系统限制位移范围 |

### 4. 输入滥用防护

| 滥用方式 | 防护措施 |
|---------|---------|
| 快速点击塔位（试图绕过金币检查） | 塔位放置系统检查金币，不足则拒绝放置，输入系统不负责 |
| 按键宏/脚本（自动输入） | 单人游戏，不做反作弊。玩家如果用脚本自动移动，体验会变差，不影响他人。 |

---

## Dependencies

### 上游依赖（输入系统依赖的系统）

**无上游依赖** — 输入系统是 Foundation 层，不依赖任何其他游戏系统。

**Godot 引擎依赖**:
- `Input` 类 — 用于检测键盘和鼠标输入状态
- `Viewport` 类 — 用于获取鼠标在游戏窗口中的位置

### 下游依赖（依赖输入系统的系统）

| 系统 | 依赖类型 | 数据接口 | 说明 |
|-----|---------|---------|------|
| **移动系统** | 硬依赖 | `movement_direction: Vector2` | 必须有方向输入才能移动 |
| **塔位放置系统** | 硬依赖 | `tower_place_signal: bool + slot_id` | 点击塔位触发放置流程 |
| **UI系统** | 硬依赖 | `ui_click_signal: bool + button_id` | UI按钮交互必需 |

### 横向依赖（无）

输入系统不与同层系统直接交互。

### 接口定义

```gdscript
# 输入系统输出的信号接口
signal movement_direction_changed(direction: Vector2)
signal tower_place_requested(slot_id: int)
signal ui_button_clicked(button_id: String)

# 输入系统接收的外部触发信号
signal upgrade_panel_opened()  # 从波次系统 → 切换到 UI_Open 状态
signal upgrade_panel_closed()  # 从升级选择系统 → 切换到 Normal 状态
signal game_paused()           # 从结算系统 → 切换到 Paused 状态
signal game_resumed()          # 从UI系统 → 切换到 Normal 状态
```

---

## Tuning Knobs

输入系统几乎没有需要调整的参数——这是一个相对固定的基础系统。以下是可选的调整项：

| 参数名 | 类型 | 默认值 | 安全范围 | 说明 |
|-------|------|-------|---------|------|
| **input_buffer_frames** | int | 0 | 0-3 | 输入缓冲帧数。0=即时响应，>0=轻微缓冲减少丢帧。设置过高会导致延迟感。 |
| **diagonal_threshold** | float | 0.5 | 0.3-0.7 | 斜向移动的按键同时按下阈值。低于0.3会误触发斜向，高于0.7会难以触发斜向。 |
| **mouse_edge_tolerance** | float | 5.0 | 0-20 | 鼠标点击塔位边缘的容忍像素。0=精确点击，>0=边缘附近也算点击。过高会导致误点击。 |

**参数交互说明**:
- `input_buffer_frames` 与 `diagonal_threshold` 无交互
- `mouse_edge_tolerance` 与塔位大小相关，需要与地图系统协调

**极端值测试**:
- `input_buffer_frames = 10` → 明显延迟，玩家感觉"按键不灵敏" — 不推荐
- `diagonal_threshold = 0.1` → 几乎任何按键组合都会触发斜向 — 不推荐
- `mouse_edge_tolerance = 50` → 玩家可能误点击不想要的塔位 — 不推荐

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
| AC-01 | WASD 单键移动 | 按下 W/S/A/D 单键 | 猫咪向正确方向移动 |
| AC-02 | WASD 组合斜向移动 | 同时按下 W+A / W+D / S+A / S+D | 猫咪向正确斜向移动，速度不变（归一化） |
| AC-03 | 相反按键冲突 | 同时按下 W+S 或 A+D | 猫咪停止移动，不发生位移 |
| AC-04 | 鼠标塔位悬停 | 鼠标悬停塔位区域 | 显示"可放置"提示 |
| AC-05 | 鼠标塔位点击 | 点击塔位区域 | 触发塔位放置流程 |
| AC-06 | UI面板状态切换 | 升级面板打开时按 WASD | 猫咪不移动，保持在原地 |
| AC-07 | UI面板关闭恢复 | 选择升级后关闭面板 | WASD 移动恢复正常 |

### 性能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-08 | 输入响应延迟 | 测量按键到猫咪移动的时间 | < 16.67ms（一帧内） |
| AC-09 | 连续输入处理 | 快速交替按下 WASD（每秒10次） | 所有输入正确处理，无丢帧 |

### 边界测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-10 | 鼠标移出窗口 | 鼠标移出游戏窗口后点击 | 不触发任何游戏内交互 |
| AC-11 | 暂停状态输入 | 暂停菜单打开时按 WASD | 不触发移动 |
| AC-12 | 快速点击多个塔位 | 快速连续点击两个塔位 | 只处理第一个点击 |

### 集成测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-13 | 移动系统集成 | 完整游戏循环中移动 | 移动系统正确消费 direction 信号 |
| AC-14 | 塔位系统集成 | 点击塔位放置防御塔 | 塔位放置系统正确消费信号 |
| AC-15 | UI系统集成 | 点击升级选项 | UI系统正确消费信号，升级生效 |

---

## Open Questions

[To be designed]
