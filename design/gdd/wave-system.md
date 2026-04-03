# 波次系统 (Wave System)

> **Status**: In Design
> **Author**: [user + agents]
> **Last Updated**: 2026-04-03
> **Implements Pillar**: 成长的爽感 + 策略有深度

## Overview

波次系统是核心循环的**状态机驱动者**（Core Loop Orchestrator），负责串联难度曲线系统、敌人生成系统和结算/升级流程，管理"开始一波 → 刷怪 → 清场 → 升级窗口 → 下一波"的完整循环。

波次系统不决定刷什么怪、刷多少、怎么刷——这些由难度曲线系统提供 `WaveConfig`，敌人生成系统执行刷怪。波次系统的职责是**知道当前处于循环的哪个阶段、何时触发阶段切换、何时结束当前波、何时启动下一波、以及何时因玩家死亡而结束一整局游戏**。

**核心职责**：从难度曲线系统获取波次配置 → 驱动敌人生成系统开始/停止刷怪 → 监听刷怪完成信号 → 追踪场上存活敌人 → 所有敌人清空后进入升级窗口 → 升级窗口结束后启动下一波 → 玩家死亡时结束游戏。

**核心接口**:
- `start_wave() -> void` — 启动当前波次（自动请求 WaveConfig 并驱动生成系统）
- `get_current_wave() -> int` — 返回当前波次编号
- `is_wave_active() -> bool` — 查询是否有波次正在进行
- `signal wave_started(wave_number: int)` — 新波次开始时发出
- `signal wave_completed(wave_number: int)` — 一波完全结束时发出

---

## Player Fantasy

波次系统是**隐形的节拍器**——玩家不会直接看到它，但每一次"这波怪清完了，好爽，等一下又有怪来了"的节奏感都来源于它的调度。

**情感目标**：**节奏感 + 阶段跃迁感**
- 玩家能明确感知"一波结束了"和"新一波开始了"，有清晰的呼吸节奏
- 每波之间有短暂的喘息时间，让玩家升级、恢复、思考策略
- 里程碑波（3/6/10）开始时有更强的视觉/听觉提示，让玩家感到"这局不一样"
- Boss 波（第 10 波）前有明显的"最终警告"感，形成完整的 run 高潮

**玩家应该感受到**:
- "一波接着一波，但我有时间喘口气，有时间选择升级。"
- "第 10 波来了的时候，我知道这是整局的高潮。"
- "清完了所有怪 → 奖励升级 → 下一波更强 → 我更强了 → 再来！"

**玩家不应该感受到**:
- "什么时候一波结束了？我怎么没感觉？"
- "我还在清怪呢怎么下一波就开始了？"
- "打完 Boss 直接就死了？连个结算都没有？"

---

## Detailed Design

### Core Rules

#### 规则 1：波次生命周期

每波经历以下阶段：

```
Idle → Spawning → Clearing → UpgradeWindow → (循环) → Idle
  ↑                                           │
  └──────────── 下一波 ─────────────────────────┘
```

**各阶段定义**:

| 阶段 | 说明 | 持续时间 |
|------|------|---------|
| **Idle** | 等待中，无活跃波次 | 游戏启动时或玩家死亡后 |
| **Spawning** | 敌人生成系统正在按 WaveConfig 刷怪 | WaveConfig.duration_sec 内的刷怪期 |
| **Clearing** | 刷怪预算已消耗完，场上仍有残敌需清理 | 动态，取决于清怪速度 |
| **UpgradeWindow** | 全部敌人已清零，打开升级选择窗口 | WaveConfig.upgrade_pause_sec 或玩家确认后立即继续 |

#### 规则 2：启动流程

```gdscript
func start_wave() -> void:
    if state != State.Idle:
        push_error("WaveSystem: start_wave called while %s, must be Idle" % state)
        return

    current_wave += 1
    config = difficulty_curve.get_wave_config(current_wave)

    state = State.Spawning
    wave_started.emit(current_wave)

    # 通知敌人生成系统开始刷怪
    spawn_system.start_spawning(config)
    clear_timer = 0.0
```

#### 规则 3：Spawning → Clearing 转换

当收到 `spawn_system.spawning_finished` 信号时：

```gdscript
func _on_spawning_finished(_total_spawned: int) -> void:
    state = State.Clearing
    clear_timer = 0.0
```

- 进入 Clearing 后不再刷怪。
- 清场阶段持续检测场上存活敌人数量（通过订阅 `health_system.enemy_died` 和 `player_died` 信号维持计数）。
- 当存活敌人计数归零且 clear_timer >= CLEARING_LEEWAY_SEC（默认 1.0 秒，确保没有延迟刷怪/生成动画中的敌人）时，自动转入 UpgradeWindow。

#### 规则 4：清场倒计时

```gdscript
func _process(delta: float) -> void:
    if state == State.Clearing:
        clear_timer += delta
        if _alive_enemies == 0 and clear_timer >= CLEARING_LEEWAY_SEC:
            _start_upgrade_window()

    if state == State.UpgradeWindow:
        upgrade_window_timer -= delta
        # 玩家点击跳过或超时自动继续
        if _should_proceed():
            _end_upgrade_window()
```

#### 规则 5：Clearing → UpgradeWindow → Spawning（下一波）

```gdscript
func _start_upgrade_window() -> void:
    state = State.UpgradeWindow
    upgrade_window_timer = config.upgrade_pause_sec
    upgrade_panel_opened.emit(current_wave)

func _end_upgrade_window() -> void:
    upgrade_panel_closed.emit()
    state = State.Idle
    wave_completed.emit(current_wave)

    # 如果玩家选择继续（非无尽模式且玩家未死亡）
    if should_continue:
        call_deferred("start_wave")  # 下一波
```

- `should_continue` 在 MVP 阶段始终为 `true`（自动继续下一波）。
- v1.0 可扩展为：第 10 波完成后弹出"继续无尽模式？"确认面板。

#### 规则 6：玩家死亡处理

```gdscript
func _on_player_died() -> void:
    spawn_system.stop_spawning()
    state = State.GameOver
    game_over.emit(current_wave)  # 通知结算系统
```

- 收到 `player_died` 信号后立即停止所有刷怪。
- 进入 GameOver 状态，不再自动推进波次。
- 由结算系统消费 `game_over` 信号展示结果。

#### 规则 7：无尽模式衔接

第 10 波完成后：

```gdscript
if current_wave == 10 and player_chose_continue:
    # 切换到无尽模式
    state = State.Idle
    current_wave = 10  # 保持为10，但用 endless_depth 追踪
    endless_depth += 1
    start_endless_wave()

func start_endless_wave():
    config = difficulty_curve.get_endless_wave_config(current_wave, endless_depth)
    state = State.Spawning
    wave_started.emit(current_wave)
    spawn_system.start_spawning(config)
```

- 无尽模式下 `current_wave` 保持为 10。
- `endless_depth` 递增（第 1 轮无尽 = depth 1, 第 2 轮 = depth 2）。
- `endless_wave_completed` 信号与 `wave_completed` 复用同一接口，但附带 `is_endless=true` metadata。

#### 规则 8：存活敌人计数器

波次系统维护 `_alive_enemies: int`：

- **增加**：订阅 `spawn_system.enemy_spawned` 信号，每刷一个敌人 `_alive_enemies += 1`。
- **减少**：订阅 `health_system.enemy_died` 信号，每死一个敌人 `_alive_enemies -= 1`（确保不 < 0）。
- **归零判定**：`_alive_enemies == 0` 且状态为 Clearing → 触发升级窗口。

---

### States and Transitions

| 状态 | 进入条件 | 退出条件 | 行为 |
|------|---------|---------|------|
| **Idle** | 游戏启动、Wave 完成、升级窗口关闭 | `start_wave()` 调用 | 空闲等待，不驱动任何系统 |
| **Spawning** | `start_wave()` 执行完毕后 | 收到 `spawning_finished` 信号 | 驱动 enemy_spawn_system 刷怪 |
| **Clearing** | `spawning_finished` 信号收到后 | `_alive_enemies == 0` 且 clear_timer >= 1.0s | 等待场上敌人全部死亡 |
| **UpgradeWindow** | 清场完成且存活敌人为零 | 玩家确认或计时器超时 | 打开升级面板，等待选择 |
| **GameOver** | 收到 `player_died` 信号 | 无（本局结束） | 停止一切，等待结算系统接管 |

```
┌──────┐   start_wave()     ┌──────────┐  spawning_finished  ┌──────────┐
│ Idle │ ──────────────────→│ Spawning │ ───────────────────→│ Clearing │
└──┬───┘                     └─────┬────┘                      └────┬─────┘
   │                               │                                │
   │                          player_died          alive==0 + leeway│
   │                               │                                │
   │                               ▼                                ▼
   │                        ┌──────────┐                   ┌───────────────┐
   │                        │ GameOver │                   │ UpgradeWindow │
   │                        └──────────┘                   └───────┬───────┘
   │                                ▲                               │
   │                                │        player_confirmed       │
   │                                │        or timer_expired       │
   │                                │                               │
   │          start_wave (next) ←──┘ ─────────────────────────────┘
   └────────── game_over signal
```

### Interactions with Other Systems

| 系统 | 交互方向 | 数据流 | 说明 |
|------|---------|--------|------|
| **难度曲线系统** | 波次 → 难度曲线 | `get_wave_config(wave_number)` | 每波开始前调用一次，获取 WaveConfig（硬依赖） |
| **敌人生成系统** | 波次 → 敌人生成 | `start_spawning(config)` / `stop_spawning()` | 驱动刷怪开始和强制停止（硬依赖） |
| **敌人生成系统** | 敌人生成 → 波次 | `spawning_finished`, `spawning_stopped`, `enemy_spawned` 信号 | 判断何时转 Clearing 和维护存活计数（硬依赖） |
| **生命值系统** | 生命值 → 波次 | `player_died`, `enemy_died` 信号 | 玩家死亡触发 GameOver；敌人死亡用于存活计数（硬依赖） |
| **升级选择系统** | 波次 → 升级选择 | `upgrade_panel_opened(wave_number)` / `upgrade_panel_closed` 信号 | 打开/关闭升级面板的通知（软依赖，MVP 可仅通知） |
| **结算系统** | 波次 → 结算 | `game_over(current_wave, is_endless)` 信号 | 玩家死亡时通知结算系统（硬依赖） |
| **UI系统** | 波次 → UI | `wave_started`, `wave_completed` 信号 | 波次编号显示、里程碑提示（软依赖） |

---

## Formulas

### 1. 波次总时长预估

```
expected_wave_duration = spawn_expected_duration + clearing_duration + upgrade_window_duration

其中:
    spawn_expected_duration = spawn_budget * spawn_interval_sec    (仅近似)
    clearing_duration = avg_enemy_lifetime * (enemies_remaining_at_spawning_end / players_dps)
    upgrade_window_duration = WaveConfig.upgrade_pause_sec
```

**示例计算（第 1 波）**：
```
spawn_budget = 12
spawn_interval = 1.20s
spawn_expected ≈ 12 * 1.20 = 14.4s
clearing ≈ 0.5s (敌人数量少)
upgrade_window = 5.0s (假设)

total ≈ 14.4 + 0.5 + 5.0 = 19.9s ≈ 20s
```

### 2. 全 10 波总时长预估

```
total_run_duration = Σ(wave_duration for w in 1..10)
```

按示例表各波 duration_sec 估算：

| 波次 | 估算总时长（含清场+升级） |
|------|-------------------------|
| 1 | ~20s |
| 2 | ~22s |
| 3 | ~25s |
| 4 | ~24s |
| 5 | ~27s |
| 6 | ~30s |
| 7 | ~28s |
| 8 | ~29s |
| 9 | ~30s |
| 10 | ~35s |
| **合计** | **~270s ≈ 4.5 分钟** |

> 参考 Vampire Survivors 的 30 分钟一局和 Brotato 的 3-5 分钟一局，本 MVP 单 run 约 4-5 分钟，符合"快节奏一局一尝试"的设计意图。

### 3. 存活敌人计数器公式

```
初始: _alive_enemies = 0

每帧:
    on enemy_spawned:     _alive_enemies += 1
    on enemy_died:        _alive_enemies = max(0, _alive_enemies - 1)

清场判定:
    _alive_enemies == 0 AND state == Clearing AND clear_timer >= CLEARING_LEEWAY_SEC
        → 转 UpgradeWindow
```

### 4. 无尽模式波次编号

```
显示给玩家的波次:
    if not is_endless:
        display_wave = current_wave
    else:
        display_wave = "E" + str(endless_depth)  # 如 "E1", "E2"

内部追踪:
    current_wave 在无尽模式中始终为 10
    endless_depth 每轮无尽 +1
```

---

## Edge Cases

| 编号 | 边界情况 | 触发条件 | 处理方式 |
|------|---------|---------|---------|
| EC-01 | **刷怪完成但场上无敌人** | spawn_budget > 0 但所有敌人生成后瞬间死亡（如玩家爆发伤害极高） | Clearing 状态下 `_alive_enemies == 0` 已为 0，clear_timer 到 1.0s 后正常进入 UpgradeWindow。无需额外处理 |
| EC-02 | **玩家死亡时正在刷怪** | spawning 阶段触发 `player_died` | 立即调用 `spawn_system.stop_spawning()`，转 GameOver。已刷出的敌人留在场上但不影响结算 |
| EC-03 | **玩家死亡时正在清场** | Clearing 阶段，场上有残敌 | 不等待清场完成，立即转 GameOver |
| EC-04 | **玩家死亡时正在升级窗口** | UpgradeWindow 阶段，面板打开中 | 关闭升级面板（`upgrade_panel_closed.emit()`），转 GameOver |
| EC-05 | **难度曲线系统返回 null 配置** | `get_wave_config(wave_number)` 返回无效值 | 输出严重错误日志，不启动刷怪，保持在 Idle 状态。这是设计配置错误而非运行时异常 |
| EC-06 | **存活计数器出现负数** | enemy_died 信号比 enemy_spawned 多（极端时序 bug） | `_alive_enemies = max(0, _alive_enemies - 1)` 钳制，防止负数。同时输出 warning 日志 |
| EC-07 | **Clearing 阶段超时** | 场上有"卡住"的敌人导致 `_alive_enemies > 0` 超过 60 秒 | 设置清场超时阈值 `CLEARING_TIMEOUT_SEC = 60s`，超时后强制进入 UpgradeWindow 并输出 warning。防止无限卡关 |
| EC-08 | **波次系统在非 Idle 状态收到 start_wave()** | 外部系统误调用 | 输出错误日志，忽略调用。不重置状态，防止打断正在进行的波次 |
| EC-09 | **游戏暂停期间清场计时** | 升级面板打开导致 `time_scale = 0` | Clearing 的 `clear_timer` 基于 `_process(delta)` 计时，`delta` 在暂停时为 0，因此计时器自然暂停，正确 |
| EC-10 | **第 10 波完成后自动进入无尽 vs 结束** | MVP 阶段未实现"是否继续"确认 | MVP 第 10 波完成后**自动结束游戏**（进入 GameOver），结算系统展示结果。v1.0 添加"继续无尽模式"确认面板 |
| EC-11 | **升级窗口期间玩家未做任何选择** | 玩家挂机 | 超时后自动关闭升级面板并进入下一波。MVP 暂不实现超时自动跳过，假设玩家至少点击"开始"按钮 |
| EC-12 | **敌人生成失败导致场上敌人数永远达不到 spawn_budget** | 敌人生成系统返回 null 但仍扣除预算 | 波次系统不关心实际生成了多少敌人，只关心 `_alive_enemies` 和 `spawning_finished` 信号。生成系统预算扣除正确即可 |

---

## Dependencies

### 上游依赖（波次系统依赖的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **难度曲线系统** | 硬依赖 | `get_wave_config(wave_number) -> WaveConfig` | 每波配置唯一来源 |
| **敌人生成系统** | 硬依赖 | `start_spawning(config)`, `stop_spawning()`, 信号 `spawning_finished`, `enemy_spawned` | 驱动刷怪、监听刷完 |
| **生命值系统** | 硬依赖 | 信号 `player_died`, `enemy_died` | 玩家死亡和游戏结束判定；敌人计数 |

### 下游依赖（依赖波次系统的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **升级选择系统** | 硬依赖 | 信号 `wave_started`, `upgrade_panel_opened` | 波次结束后打开升级面板 |
| **结算系统** | 硬依赖 | 信号 `game_over(wave_number, is_endless)` | 玩家死亡时展示结算 |
| **UI系统** | 软依赖 | 信号 `wave_started(wave_number)`, `wave_completed(wave_number)` | 波次编号、里程碑提示 |

### GDScript 接口定义

```gdscript
# ============================================================
# WaveSystem.gd
# 波次系统 — 核心循环状态机
# 挂载到游戏场景的管理节点下
# ============================================================
class_name WaveSystem
extends Node

## 状态枚举
enum State { Idle, Spawning, Clearing, UpgradeWindow, GameOver }

# ---------- 信号 ----------
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal game_over(wave_number: int, is_endless: bool)
signal upgrade_panel_opened(wave_number: int)
signal upgrade_panel_closed()

# ---------- 导出变量 ----------
## 清场阶段等待全部敌人死亡的额外等待时间（秒）
@export var clearing_leeway_sec: float = 1.0

## 清场超时上限（秒），防止永久卡关
@export var clearing_timeout_sec: float = 60.0

# ---------- 运行时状态 ----------
var state: State = State.Idle
var current_wave: int = 0
var endless_depth: int = 0
var config: WaveConfig = null
var clear_timer: float = 0.0
var upgrade_window_timer: float = 0.0
var _alive_enemies: int = 0

# ---------- 系统引用 ----------
var difficulty_curve: Node = null
var spawn_system: Node = null

# ---------- 公开 API ----------
func start_wave() -> void
func get_current_wave() -> int
func get_current_config() -> WaveConfig
func is_wave_active() -> bool
func get_alive_enemy_count() -> int
func get_state() -> State
func get_state_name() -> String
```

---

## Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 影响 |
|--------|------|--------|---------|------|
| `clearing_leeway_sec` | float | 1.0 | 0.5-2.0 | 清场后额外等待时间。过短可能导致延迟生成的敌人被意外跳过；过长拖慢节奏 |
| `clearing_timeout_sec` | float | 60.0 | 30.0-120.0 | 清场超时上限。过短时强力 build 可能还没享受清场乐趣就被强制跳过；过长时卡关永久无法通关 |
| `auto_start_next_wave` | bool | true (MVP) | true/false | 是否自动启动下一波。MVP 默认自动，v1.0 可改为手动确认 |

**参数交互**：
- `clearing_leeway_sec` 应与敌人生成系统的 `spawn_animation_duration`（0.2s）共同调试。leeway 应 ≥ animation_duration 以确保最后一批敌人完全生成后再判定清场。

---

## Visual/Audio Requirements

### 视觉提示
- **波次开始**：短暂的全屏"Wave X"文字动画（1 秒），Boss 波用更夸张的特效
- **里程碑波**：第 3/6/10 波开始时，屏幕边框有可爱的闪光/抖动特效
- **清场完成**：全部敌人死亡后，小粒子庆祝效果（1-2 秒）

### 音频提示
- **波次开始**：短促提示音（不同音高对应不同压力等级）
- **Boss 波**：特殊的低沉警告音效，与正常波次区别明显
- **清除完成**：轻松/愉快的短音效

---

## UI Requirements

| UI 元素 | 触发时机 | 内容 |
|---------|---------|------|
| 波次编号 | 始终显示（HUD） | 当前波次编号 "Wave X/10" |
| 波次开始横幅 | `wave_started` 信号 | "Wave 3" 大字 + 小字提示（如 "Fast Enemies Incoming!"） |
| 里程碑警告 | 第 3/6/10 波开始时 | Boss War / Milestone Wave 字样，颜色与正常不同 |
| 升级面板 | UpgradeWindow 期间 | 3 选 1 升级选项 + "选择" / "随机" / "跳过"按钮 |
| 结算面板 | `game_over` 信号 | 到达波次、击杀数、时长、评级等统计 |

---

## Acceptance Criteria

### 功能测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-WV-01 | 状态机完整流转 | 启动游戏 → 等待 10 波自然流转 → 记录每次状态变化 | 每波均按 `Idle → Spawning → Clearing → UpgradeWindow → Idle` 完整流转，无状态卡死 |
| AC-WV-02 | WaveConfig 正确消费 | 第 1 波，检查 `spawn_system.wave_config` | 波次系统传递的配置的 `spawn_budget`, `spawn_interval_sec`, `enemy_mix` 值与难度曲线返回的一致 |
| AC-WV-03 | 存活敌人计数准确 | 第 1 波 spawn_budget=12，手动击杀 8 个敌人后暂停 | `_alive_enemies == 4`（精确匹配） |
| AC-WV-04 | 清场阶段正确触发 | 场上所有敌人死亡后计时 | `_alive_enemies == 0` 后约 1.0s 内进入 UpgradeWindow 状态 |
| AC-WV-05 | 玩家死亡触发游戏结束 | 刷怪过程中触发 `player_died` | `state == GameOver`，`game_over` 信号发出恰好 1 次，spawn_system 停止刷怪 |
| AC-WV-06 | wave_started 信号发出 | 每波开始时监听 | `wave_started` 信号发出，wave_number 参数等于 current_wave |
| AC-WV-07 | wave_completed 信号发出 | 每波升级窗口关闭后监听 | `wave_completed` 信号发出，wave_number 参数等于刚完成的波次 |
| AC-WV-08 | current_wave 从 1 开始自增 | 记录每波开始时的 current_wave 值 | 序列为 1, 2, 3, ..., 10；不跳过、不重复 |
| AC-WV-09 | 升级面板打开/关闭信号 | 监听 `upgrade_panel_opened(3)` 和 `upgrade_panel_closed` | 每波 Clearing 完成后发出 opened，玩家确认后发出 closed |
| AC-WV-10 | 非 Idle 状态 start_wave 被拒绝 | Spawning 状态调用 start_wave() | 输出错误日志，状态不变，不启动新波次 |

### 边界测试

| ID | 测试项 | 验证方法 | Pass 标准 |
|----|-------|---------|----------|
| AC-WV-11 | 空波次处理（spawn_budget=0） | 难度曲线返回 spawn_budget=0 | 直接进入 Clearing → 存活敌人已为 0 → 1.0s 后进入 UpgradeWindow |
| AC-WV-12 | 清场超时强制推进 | 场上放置 1 个不会死亡的敌人 | 60 秒后强制进入 UpgradeWindow，输出 warning |
| AC-WV-13 | 存活计数不出现负数 | 模拟 enemy_died 信号在没有 enemy_spawned 的情况下触发 | `_alive_enemies` 不低于 0，输出 warning 日志 |
| AC-WV-14 | 难度曲线返回 null 时安全处理 | 修改难度曲线让 get_wave_config 返回 null | 进入 Idle 状态并输出严重错误日志，程序不崩溃 |
| AC-WV-15 | 升级窗口中玩家死亡 | 升级面板打开中触发 player_died | 关闭面板，转 GameOver，game_over 信号发出 |

### 节奏测试

| ID | 测试项 | 测试场景 | Pass 标准 |
|----|-------|---------|----------|
| AC-WV-16 | 第 1 波总时长 | 不击杀任何敌人，让波自然进行 | 从 wave_started 到下一个 wave_started 之间的总时间在 18-25 秒范围内 |
| AC-WV-17 | 第 10 波总时长 | 第 10 波自然进行 | 从 wave_started 到 game_over/升级窗口打开之间的总时间在 30-45 秒范围内 |
| AC-WV-18 | 完整 10 波运行 | 自动化测试模拟完整 run | 总游戏时长在 240-300 秒（4-5 分钟）范围内 |

---

## Open Questions

| # | 问题 | 影响范围 | 建议方案 | 决策时间 |
|---|------|---------|---------|---------|
| OQ-01 | 第 10 波完成后是否自动进入无尽模式？ | 游戏流程 | **MVP 不实现无尽模式**——第 10 波完成后直接 GameOver 进入结算。v1.0 再添加"继续无尽"确认面板。 | 当前已确认 |
| OQ-02 | 升级窗口是否支持玩家主动"跳过"升级直接进入下一波？ | 玩家体验，升级系统 | 升级选择系统需确认是否有"跳过不升级"功能。若有，波次系统监听 `upgrade_panel_closed` 后立即进入下一波，不等待超时。 | 待升级选择系统确认 |
| OQ-03 | 是否需要在波次中间（非结束时）触发升级（如 Brotato 的波中小怪掉落升级）？ | 节奏设计 | **MVP 不做波中升级**。所有升级只在波次结束后的 UpgradeWindow 中处理。 | 当前假设为否 |
| OQ-04 | 清场超时 60 秒是否合理？ | 卡关处理 | 根据原型测试调整。如果正常 build 清掉一波满场敌人平均 < 5 秒，则 60 秒绰绰有余。可以先设 30 秒做原型验证。 | 原型验证后 |
| OQ-05 | 多个敌人"同帧"死亡时 enemy_died 信号可能连发，clearing 计时器是否会有问题？ | 时序安全 | 不会。每个 enemy_died 只减少 `_alive_enemies`，clear_timer 是持续累加的独立计时器。只要最终 _alive_enemies 归零，clear_timer 已经过了足够时间就会切换。 | 技术确认可行 |
