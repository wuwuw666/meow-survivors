# 敌人生成系统 (Enemy Spawn System)

> **Status**: In Design
> **Author**: Game Designer Agent
> **Created**: 2026-04-02
> **Implements Pillar**: 策略有深度 + 可爱即正义（刷怪仪式感）

---

## 1. Overview

敌人生成系统是《喵族幸存者》核心循环的**执行层节拍器**，负责将波次系统下达的刷怪指令转化为实际的敌人实例。它是纯执行系统：不决定刷什么、刷多少、何时刷（这些都属于波次系统的职责），只负责"按给定的预算、间隔、敌配比和刷怪点列表，正确地、有节奏地生成敌人"。

MVP 采用**简单间隔刷怪**模型：每经过 `spawn_interval_sec` 秒生成 1 个敌人，敌人类型由波次配置中 `enemy_mix` 权重表随机决定，刷怪点从地图系统提供的 8 个点中随机选取。如果刷怪间隔到期但波次预算仍未完成（如波次时长即将结束），剩余预算将以**爆发模式**在短时间内刷完。

**核心职责**：接收波次系统的刷怪指令 → 按间隔计时生成单个敌人 → 加权随机选择敌人类型 → 随机选择刷怪点 → 实例化敌人 → 追踪已生成数量 → 预算耗尽后通知波次系统。

---

## 2. Player Fantasy

### 目标美学 (MDA Aesthetics)

| 美学类型 | 优先级 | 实现方式 |
|---------|--------|---------|
| **Challenge（挑战）** | ⭐⭐⭐⭐⭐ | 敌人有节奏地涌入，压力持续递增但不窒息 |
| **Sensation（感官愉悦）** | ⭐⭐⭐ | 每次刷怪都有可爱的小动画（弹出/钻出效果） |
| **Submission（节奏感）** | ⭐⭐ | 刷怪间隔给玩家喘息和输出窗口 |

### 情感弧线

玩家在刷怪阶段应感受到：

```
刷怪开始 → "来了！" → 逐个出现 → 密度递增 → 紧张感积累
     ↑                                            │
     │         ← ← ← 最后一个敌人 ← ← ← ← ← ←     │
     │                                            ↓
     └—— 刷怪结束，进入清场 → 放松 → 成就感
```

### 玩家应该感受到

- "怪物是一个个出来的，不是突然满屏——我有反应时间。"
- "能从外观判断来的是什么类型的怪，快速决定先打哪个。"
- "波次快结束的最后一波怪刷得特别快，像高潮冲刺。"

### 玩家不应该感受到

- "怪物凭空出现，没有视觉提示"。
- "一堆怪同时刷出来，完全没有反应时间"。
- "刷怪点太近，怪物直接贴脸"。
- "同一刷怪点连续出怪，感觉像怪物都从一条缝里挤出来的"。

### 参考游戏

- **吸血鬼幸存者**：敌人从屏幕边缘持续涌来，有明显的"出现方向感"。
- **土豆兄弟（Brotato）**：每波有明确的敌人数量，刷完即止，可预期。
- **弹壳特攻队**：刷怪节奏与玩家输出节奏形成"来多少清多少"的循环快感。

---

## 3. Detailed Rules

### 3.1 系统状态机

| 状态名 | 说明 | 行为 |
|--------|------|------|
| **Idle** | 等待刷怪指令 | 不生成、不计时。等待 `start_spawning()` |
| **Active** | 正在按间隔刷怪 | 每次 `spawn_timer >= spawn_interval_sec` 时生成 1 个敌人 |
| **Burst** | 爆发模式 | 短时间内连续生成剩余预算中的敌人 |
| **Complete** | 预算已全部生成 | 发出 `spawning_finished` 信号，状态转回 Idle |
| **Stopped** | 被强制停止 | 收到 `stop_spawning()` 后清理状态，不发出 spawning_finished |

#### 状态转换图

```
┌──────┐    start_spawning(config)     ┌──────────────┐
│ Idle │ ───────────────────────────→ │    Active      │
└──────┘                              └──────┬───────┘
                                             │
                                  remaining_budget == 0
                                             │
                                             ▼
                                      ┌──────────────┐
                                      │   Complete    │ → emit spawning_finished → ┐
                                      └──────────────┘                             │
                                             ▲                                     │
                                      ── 超时/紧迫 ──┐                            │
                                                     ▼                           │
                                              ┌──────────────┐                    │
                                              │    Burst      │                    │
                                              └──────┬───────┘                    │
                                                     │                            │
                                        remaining_budget == 0                    │
                                             └────────────────────────────────────┘

任意状态中：
  stop_spawning() ──→ Stopped
  Idle ◄───────────────── Complete (spawning_finished 信号处理完后自动归位)
  Idle ◄───────────────── Stopped
```

### 3.2 详细规则

#### 规则 1：开始刷怪

```gdscript
func start_spawning(config: WaveConfig) -> void:
    assert(state == State.IDLE, "Cannot start spawning while not idle")

    wave_config = config
    total_spawned = 0
    remaining_budget = config.spawn_budget
    spawn_timer = 0.0
    burst_accumulator = 0.0
    last_spawn_point_index = -1
    _boss_guaranteed_spawned = false

    # 检查是否需要保证 Boss 生成
    if _wave_is_boss_wave(config):
        _boss_guaranteed = true
        remaining_budget = config.spawn_budget - 1  # 预留 1 个名额给 Boss
        _spawn_boss_enemy()  # 优先生成 Boss
        remaining_budget += 1  # 恢复计数，上面已 -1

    # 计算预期刷怪总时长
    expected_duration = (config.spawn_budget - 1) * config.spawn_interval_sec

    state = State.ACTIVE
    _next_enemy_type = select_enemy_type_from_mix(config.enemy_mix)
    emit_signal("spawning_started", config.spawn_budget)
```

- Boss 波的 Boss 生成优先于普通敌人生成。
- Boss 生成失败时不扣除 spawn_budget，并在日志告警。

- 仅在 `Idle` 状态下可调用，否则打印错误日志并返回。
- 重置所有运行时计数器。
- 在调用 `_ready_spawn()` 时预先选择第一个敌人的类型（防止第一个生成帧才选，造成时序不一致）。
- 发出 `spawning_started` 信号（可选，供 UI/音效订阅）。

#### 规则 2：间隔刷怪（Active 状态）

```gdscript
func _process(delta: float) -> void:
    if state != State.ACTIVE:
        return

    spawn_timer += delta

    if spawn_timer >= config.spawn_interval_sec:
        spawn_timer -= config.spawn_interval_sec  # 保留超额时间
        _spawn_one_enemy()
        total_spawned += 1
        remaining_budget -= 1

        if remaining_budget <= 0:
            _finish_spawning()
            return

        # 检查是否需要进入爆发模式
        if _should_burst():
            state = State.BURST
```

- 使用累加计时器（`spawn_timer`），不依赖固定帧率。
- 使用 `spawn_timer -= config.spawn_interval_sec`（而非 `= 0`），保留超额时间，防止计时漂移。
- 每生成一个敌人后，检查是否预算耗尽。
- 检查是否应切换至爆发模式（见规则 3）。

#### 规则 3：爆发模式（Burst 状态）

在以下任一条件满足时，系统从 `Active` 切换至 `Burst`：

1. **波次时长紧迫**：`elapsed_time >= config.duration_sec * 0.8`（已过 80% 的波次时长，但预算仍未完成）。
2. **波次系统强制要求**：波次系统调用 `force_burst()` 接口。

```gdscript
func _burst_process(delta: float) -> void:
    if state != State.BURST:
        return

    burst_accumulator += delta
    burst_interval = calculate_burst_interval(remaining_budget, config)

    while burst_accumulator >= burst_interval and remaining_budget > 0:
        burst_accumulator -= burst_interval
        _spawn_one_enemy()
        total_spawned += 1
        remaining_budget -= 1

    if remaining_budget <= 0:
        _finish_spawning()
```

- 爆发间隔根据剩余预算和目标完成时间动态计算。
- 使用 `while` 循环（而非 `if`），确保在同一帧内可以爆发多个。
- 爆发间隔不得小于 `MIN_BURST_INTERVAL = 0.05s`（避免单帧生成过多导致帧率骤降）。
- 爆发间隔不得大于 `config.spawn_interval_sec`（爆发应比正常更快）。

#### 规则 4：敌人类型选择（加权随机）

```gdscript
func select_enemy_type_from_mix(enemy_mix: Dictionary) -> String:
    # enemy_mix 示例: {"normal_a": 0.7, "normal_b": 0.2, "elite": 0.1}
    var total_weight: float = 0.0
    for type: String in enemy_mix:
        total_weight += enemy_mix[type]

    # 归一化（防御性编程：权重和可能 != 1.0）
    var roll: float = randf() * total_weight
    var cumulative: float = 0.0

    for type: String in enemy_mix:
        cumulative += enemy_mix[type]
        if roll < cumulative:
            return type

    # 不应到达此处，但安全回退
    return enemy_mix.keys()[0]
```

- 使用 **CDF（累积分布函数）采样**，O(n) 时间复杂度。
- MVP 敌人类型 ≤ 5 种，O(n) 性能可接受（n ≤ 5 时可忽略不计）。
- 权重和在归一化后使用，允许配置权重和 ≠ 1.0（如 `{a: 7, b: 2, c: 1}` 权重和=10，结果与 `{a: 0.7, b: 0.2, c: 0.1}` 等效）。
- 如果 `enemy_mix` 为空字典，回退到随机选择 `normal_a`。

#### 规则 5.1：Boss 保证生成（P0 修复）

```gdscript
func _wave_is_boss_wave(config: WaveConfig) -> bool:
    return config.is_milestone and config.wave_number >= 10

func _spawn_boss_enemy() -> void:
    var boss_count = 1  # 至少 1 个 Boss
    var points = map_system.get_spawn_points()
    if points.is_empty():
        push_error("Boss spawn: no spawn points available")
        return
    
    var spawn_pos = points[randi() % points.size()]
    var boss = enemy_system.spawn_enemy("boss", spawn_pos)
    
    if boss != null:
        _boss_guaranteed_spawned = true
        remaining_instantiated += 1
        emit_signal("enemy_spawned", boss)
    else:
        push_error("Boss spawn FAILED: enemy_system returned null")
```

**优先级**：Boss 生成在 `start_spawning()` 中优先于普通敌人执行，确保即使剩余预算不足以生成 Boss，Boss 也会首先出现在场上。

**依赖**：难度曲线系统第 10 波的 `elite_chance = 1.0`（所有敌人都具有精英品质），但 Boss 是通过 `_spawn_boss_enemy()` 明确生成的独立实体。

#### 规则 5：刷怪点选择

```gdscript
func select_spawn_point() -> Vector2:
    var points: Array[Vector2] = map_system.get_spawn_points()
    var index: int = 0

    if points.size() <= 1:
        index = 0
    else:
        # 避免连续两次选择同一刷怪点
        index = _random_excluding_last(points.size())

    last_spawn_point_index = index
    return points[index] + _random_offset()
```

- 使用 `_random_excluding_last()` 避免同一刷怪点连续出怪。
- 添加 `_random_offset()`（±40px 随机偏移），防止敌人全部精准叠在同一像素点。
- 如果地图系统只返回 1 个刷怪点（防御性），则不使用排除逻辑。

#### 规则 6：敌人实例化

```gdscript
func _spawn_one_enemy() -> void:
    var enemy_type: String = _next_enemy_type
    _next_enemy_type = select_enemy_type_from_mix(config.enemy_mix)

    var spawn_pos: Vector2 = select_spawn_point()

    # 通知敌人系统实例化
    var enemy = enemy_system.spawn_enemy(enemy_type, spawn_pos)

    if enemy != null:
        remaining_instantiated += 1
        emit_signal("enemy_spawned", enemy)
```

- 敌人实例化职责委托给**敌人系统**（`enemy_system.spawn_enemy(type, pos)`）。
- 在生成当前敌人的同时，预先选择下一个敌人的类型（`_next_enemy_type`），避免在 `_spawn_one_enemy()` 中同时进行两项工作。
- 如果实例化返回 `null`（敌人系统报错），仍然扣除预算，记录日志。

#### 规则 7：完成刷怪

```gdscript
func _finish_spawning() -> void:
    state = State.COMPLETE
    spawn_timer = 0.0
    burst_accumulator = 0.0
    emit_signal("spawning_finished", total_spawned)
    # 信号被波次系统消费后，状态自动归位为 Idle
```

- 发出 `spawning_finished` 信号，通知波次系统"刷怪预算已全部消耗"。
- 波次系统收到此信号后，将状态切换为 `WaveClearing`（清场尾声）。
- 短暂延迟后（0.5s 或信号被处理完），`state` 自动回 `Idle`，准备接收下一波指令。

#### 规则 8：强制停止

```gdscript
func stop_spawning() -> void:
    state = State.STOPPED
    spawn_timer = 0.0
    burst_accumulator = 0.0
    remaining_budget = 0
    emit_signal("spawning_stopped", total_spawned)
    # 延迟后归为 Idle
```

- 由波次系统调用（如玩家死亡、游戏结束、场景切换时）。
- 不发出 `spawning_finished`，而是发出 `spawning_stopped`。
- 不清除已生成的敌人——敌人的生命周期由敌人系统管理。

---

## 4. Formulas

### 4.1 变量定义

| 变量 | 含义 | 类型 | 单位 | MVP 值/范围 |
|------|------|------|------|-------------|
| `state` | 当前刷怪状态 | enum | — | Idle/Active/Burst/Complete/Stopped |
| `total_spawned` | 本波已生成敌人总数 | int | 个 | 0 ~ spawn_budget |
| `remaining_budget` | 剩余待生成敌人数 | int | 个 | spawn_budget ~ 0 |
| `spawn_timer` | 间隔计时器累加值 | float | 秒 | 0.0 ~ spawn_interval_sec |
| `burst_accumulator` | 爆发阶段计时累加值 | float | 秒 | 0.0 ~ burst_interval |
| `_next_enemy_type` | 下一个要生成的敌人类型 | String | — | 预选值 |
| `last_spawn_point_index` | 上次使用刷怪点的索引 | int | — | -1 ~ 7 |

### 4.2 刷怪间隔计时

```text
每帧更新：
    spawn_timer += delta * time_scale

当 spawn_timer >= spawn_interval_sec 时：
    spawn_timer -= spawn_interval_sec  // 保留超额时间
    执行生成

time_scale: 游戏全局时间缩放，MVP 默认 1.0
```

**设计意图**：使用减法而非清零，防止因帧间隔不均匀导致的计时漂移（drift）。例如 spawn_interval_sec = 1.0s，delta 在 55-65 FPS 间波动为 0.015~0.018s，60 帧后若用清零会累计约 60×(0.01667-0.015) ≈ 0.1s 偏差。

### 4.3 加权随机选择（CDF 采样）

```text
给定 enemy_mix = {type_1: w_1, type_2: w_2, ..., type_n: w_n}

total_weight = Σ w_i          (i = 1 to n)
roll = randf() * total_weight  (均匀分布 [0, total_weight))

选择第一个满足以下条件的 type_k：
    cumulative_w_k >= roll
其中 cumulative_w_k = Σ w_i  (i = 1 to k)
```

**示例计算**（WaveConfig.enemy_mix = {"normal_a": 70, "normal_b": 20, "elite": 10}）：

```text
total_weight = 70 + 20 + 10 = 100
roll = randf() * 100 = 42.7  (假设)

cumulative:
    normal_a: 70  →  42.7 < 70 → ✓ 选中 "normal_a"
```

```text
roll = 85.3  (假设)

cumulative:
    normal_a: 70  →  85.3 >= 70  ✗ 继续
    normal_b: 90  →  85.3 < 90   ✓ 选中 "normal_b"
```

**概率验证**：
| 敌人类型 | 权重 | 理论概率 | 10000 次模拟期望次数 |
|----------|------|---------|---------------------|
| normal_a | 70 | 70.0% | 7000 |
| normal_b | 20 | 20.0% | 2000 |
| elite | 10 | 10.0% | 1000 |

### 4.4 刷怪点选择

```text
可选刷怪点集合：P = {p_0, p_1, ..., p_{n-1}}  (n = 8)
上次使用的索引：last_idx

本次选择：
    如果 n <= 1: idx = 0
    否则:
        idx = random_int(0, n-1)
        while idx == last_idx:
            idx = random_int(0, n-1)

实际生成位置：
    spawn_pos = P[idx] + random_offset
    random_offset = Vector2(randf_range(-40, 40), randf_range(-40, 40))
```

**防重叠说明**：40px 偏移半径确保 8 个刷怪点附近的敌人不会全部集中在同一像素点。考虑到最小敌人碰撞半径为 14px（normal_a），28px 直径，40px 偏移足以让相邻两个敌人不完全重叠。

### 4.5 爆发间隔计算

```text
当 _should_burst() 返回 true 时：

remaining_time = max(config.duration_sec - elapsed_time, MIN_BURST_DURATION)
burst_interval = clamp(remaining_time / remaining_budget, MIN_BURST_INTERVAL, config.spawn_interval_sec)

其中：
    MIN_BURST_INTERVAL = 0.05s  (单帧最大安全生成间隔)
    MIN_BURST_DURATION = 1.0s   (至少保证 1 秒的爆发窗口)
```

**示例**：
```text
# 场景：第 1 波，spawn_budget=12, duration=14.4s
# 已过 12s，只刷了 8 个，还剩 4 个

remaining_time = max(14.4 - 12.0, 1.0) = max(2.4, 1.0) = 2.4s
burst_interval = clamp(2.4 / 4, 0.05, 1.2)
               = clamp(0.6, 0.05, 1.2)
               = 0.6s

# 剩余 4 个敌人以每 0.6s 一个的速度刷完，总共 2.4s
# 第 12 个敌人生成时刻 = 12 + 2.4 = 14.4s，刚好在波次时长
```

```text
# 更极端场景：已过 13.5s，还剩 4 个

remaining_time = max(14.4 - 13.5, 1.0) = max(0.9, 1.0) = 1.0s  (下限保护)
burst_interval = clamp(1.0 / 4, 0.05, 1.2)
               = clamp(0.25, 0.05, 1.2)
               = 0.25s

# 4 个敌人以 0.25s 间隔，总共 1.0s 刷完
# 第 12 个敌人生成时刻 = 13.5 + 1.0 = 14.5s
```

```text
# 极限场景：已过 14.3s，还剩 4 个

remaining_time = max(14.4 - 14.3, 1.0) = 1.0s  (下限保护触发)
burst_interval = clamp(1.0 / 4, 0.05, 1.2) = 0.25s
# 仍然安全，不会一帧生成所有
```

### 4.6 爆发触发条件

```text
_should_burst() 返回 true 当且仅当：

(波次时长已过了 80%) AND (remaining_budget > 0) AND (state == State.ACTIVE)

即：
    elapsed_time >= config.duration_sec * BURST_THRESHOLD_RATIO
    AND remaining_budget > 0
    AND state == State.ACTIVE

其中 BURST_THRESHOLD_RATIO = 0.8（调参旋钮）
```

### 4.7 预期刷怪时长

```text
expected_spawning_duration = (spawn_budget - 1) * spawn_interval_sec + spawn_animation_duration

其中 spawn_animation_duration = 0.2s（敌人从生成到可交互的动画时间）

示例（第 1 波）：
    expected = (12 - 1) * 1.2 + 0.2 = 13.4s

示例（第 5 波，21 个敌人，0.92s 间隔）：
    expected = (21 - 1) * 0.92 + 0.2 = 18.6s
```

**设计意图**：预期刷怪时长应小于波次 `duration_sec`，给清场阶段留出时间。参考波次系统数据，第 1 波 14.4s duration vs 13.4s 预期刷怪，清场窗口约 1s+。

---

## 5. Edge Cases

| 编号 | 边界情况 | 触发条件 | 处理方式 |
|------|---------|---------|---------|
| EC-01 | **spawn_budget = 0** | 波次配置错误或空波 | 不进入 Active 状态，直接发出 `spawning_finished(0)` 后归位 `Idle`，日志告警 |
| EC-02 | **spawn_interval_sec = 0** | 波次配置错误 | 使用默认值 1.0s 替代，日志严重告警 |
| EC-03 | **enemy_mix 为空** | 波次配置遗漏 | 全部生成 `normal_a` 类型敌人，日志严重告警 |
| EC-04 | **enemy_mix 权重和为 0** | 波次配置错误（如所有权重=0） | 全部生成 `normal_a`，日志严重告警 |
| EC-05 | **地图系统返回 0 个刷怪点** | 地图系统未加载或配置错误 | 使用默认刷怪点 `Vector2(-32, -32)`（地图左上角外），日志严重告警 |
| EC-06 | **敌人生成返回 null** | 敌人系统实例化失败 | 扣除预算（不重试），记录 `push_error`，继续生成下一个 |
| EC-07 | **Active 状态下收到 start_spawning** | 波次系统调用时序错误 | 先调用 `stop_spawning()` 清理旧状态，再执行新 `start_spawning()`，日志警告 |
| EC-08 | **爆发模式下剩余预算极大** | 配置错误导致 budget 远超预期 | 使用 `MIN_BURST_INTERVAL = 0.05s` 作为最小间隔，每帧最多生成 `floor(0.01667 / 0.05) = 0` 个（安全限流），实际每秒最多生成 20 个 |
| EC-09 | **游戏暂停期间** | 升级面板打开，`Engine.time_scale = 0` | `spawn_timer += delta * 0` 不增加，刷怪自然暂停。无需额外处理 |
| EC-10 | **波次完成前有敌人因卡位超时被消除** | 敌人系统判定卡位 > 15s 自动消除 | 生成系统不受影响。`total_spawned` 只记录已生成数，不记录当前存活数。清场由波次系统负责 |
| EC-11 | **爆发触发后玩家立即死亡** | 触发爆发后 0.1s 内玩家HP归零 | 波次系统调用 `stop_spawning()`，生成系统立即停止所有刷怪 |
| EC-12 | **随机数种子重复导致刷怪序列相同** | 每局游戏使用相同随机种子 | 在 `_ready()` 时调用 `randomize()` 初始化随机种子，确保每局序列不同 |
| EC-13 | **刷怪点偏移后落入不可行走区域** | `random_offset` 使生成位置在障碍物上 | 敌人系统的移动逻辑使用 `move_and_slide()`，自动滑离障碍物。若偏移使敌人在地图外太远，`move_and_slide()` 仍可导向英雄 |
| EC-14 | **敌人类型不在敌人系统数据表中** | `enemy_mix` 中有未知类型 | 敌人系统回退到 `normal_a`（见 enemy-system EC-13），生成系统记录警告 |
| EC-15 | **_process 未执行导致计时器不更新** | Godot 节点 `process_mode = PROCESS_MODE_DISABLED` | 刷怪系统节点确保 `process_mode = PROCESS_MODE_INHERIT`。在 `_ready()` 中验证 |
| EC-16 | **duration_sec < expected_spawning_duration** | 波次配置中 duration 过短 | 立即触发爆发模式，使用 `MIN_BURST_DURATION = 1.0s` 下限保护，尽可能刷完 |

### 退化策略与缓解

| 退化策略 | 描述 | 缓解措施 |
|---------|------|---------|
| **全刷同一类型** | 加权随机的极端情况（如连续 12 次 roll 到 normal_a） | 这是合法的随机行为，不是 bug。参考波次设计中 enemy_mix 的权重分布，12 连 normal_a 的概率为 0.7^12 ≈ 1.4%，可接受 |
| **全刷同一方向** | 8 个刷怪点中恰好连续选择同一方向 | `_random_excluding_last()` 消除"连续同一点"，但不限制"同一方向的多个点"。如需更强分散，可增加方向轮换逻辑（v1.0 扩展） |
| **爆发模式一帧全出** | 理论上如果 burst_interval < delta 会一帧全出 | `MIN_BURST_INTERVAL = 0.05s` 且 delta ≈ 0.01667s（60 FPS），`0.05 / 0.01667 ≈ 3`，每帧最多 3 个，安全 |

---

## 6. Dependencies

### 6.1 上游依赖（生成系统依赖的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **波次系统** | 硬依赖 | `start_spawning(config: WaveConfig)` / `stop_spawning()` | 接收刷怪指令与配置，是生成系统的唯一驱动者 |
| **地图系统** | 硬依赖 | `get_spawn_points() -> Array[Vector2]` | 获取 8 个刷怪点的世界坐标 |
| **敌人系统** | 硬依赖 | `spawn_enemy(type: String, pos: Vector2) -> Node` | 实例化敌人并放置到指定位置 |
| **难度曲线系统** | 软依赖 | `WaveConfig` 中的数值来自难度曲线 | 通过波次系统间接消费，不直接调用难度曲线 API |

### 6.2 下游依赖（依赖生成系统的系统）

| 系统 | 依赖类型 | 接口 | 说明 |
|------|---------|------|------|
| **波次系统** | 硬依赖 | 监听 `spawning_finished(total_spawned)` 和 `spawning_stopped(total_spawned)` 信号 | 波次系统据此判断何时进入清场阶段 |
| **UI 系统** | 软依赖 | 监听 `spawning_started(budget)` 和 `enemy_spawned(enemy)` 信号 | 可选：显示"已生成/总计"计数器、刷怪方向指示器 |
| **音频系统** | 软依赖 | 监听 `enemy_spawned(enemy)` 信号 | 可选：刷怪音效（可爱"喵噗"声） |

### 6.3 接口契约

#### 生成系统公开接口

```gdscript
# ============================================================
# EnemySpawnSystem.gd
# 敌人生成系统主脚本
# 挂载到游戏场景的管理节点下
# ============================================================
class_name EnemySpawnSystem
extends Node

## 状态枚举
enum State { IDLE, ACTIVE, BURST, COMPLETE, STOPPED }

# ---------- 信号（对外发出）----------

## 刷怪开始时发出
signal spawning_started(total_budget: int)

## 每生成一个敌人时发出（参数为敌人节点引用）
signal enemy_spawned(enemy: Node)

## 所有刷怪预算已全部消耗
signal spawning_finished(total_spawned: int)

## 刷怪被强制中断（玩家死亡/场景切换等）
signal spawning_stopped(total_spawned: int)

# ---------- 导出变量 ----------

## 敌人场景基础路径
@export var enemy_scene_base_path: String = "res://assets/scenes/enemies/"

## 刷怪点随机偏移半径（像素）
@export var spawn_offset_radius: float = 40.0

## 最小爆发间隔（秒），防止单帧生成过多
@export var min_burst_interval: float = 0.05

## 最小爆发持续时间（秒），下限保护
@export var min_burst_duration: float = 1.0

## 爆发触发阈值（波次时长的百分比）
@export var burst_threshold_ratio: float = 0.8

# ---------- 运行时状态 ----------

## 当前刷怪状态
var state: State = State.IDLE

## 当前波次配置
var wave_config: WaveConfig = null

## 本波已生成敌人数
var total_spawned: int = 0

## 剩余待生成敌人数
var remaining_budget: int = 0

## 间隔计时器
var spawn_timer: float = 0.0

## 爆发计时器
var burst_accumulator: float = 0.0

## 下一个要生成的敌人类型（预选）
var _next_enemy_type: String = ""

## 上次使用的刷怪点索引
var last_spawn_point_index: int = -1

# ---------- 系统引用 ----------

var map_system: Node = null
var enemy_system: Node = null


# ---------- 公开 API（被波次系统调用）----------

## 开始按照 WaveConfig 刷怪
func start_spawning(config: WaveConfig) -> void:
    pass  # 见规则 1

## 强制停止刷怪
func stop_spawning() -> void:
    pass  # 见规则 8

## 查询当前是否正在刷怪
func is_spawning() -> bool:
    return state == State.ACTIVE or state == State.BURST

## 查询当前已生成数量
func get_total_spawned() -> int:
    return total_spawned

## 查询剩余预算
func get_remaining_budget() -> int:
    return remaining_budget

## 查询当前状态
func get_state() -> State:
    return state

## 查询生成系统的状态名称字符串（用于调试/UI）
func get_state_name() -> String:
    return State.keys()[state]


# ---------- 私有方法 ----------

## _process(delta) — 间隔刷怪逻辑
## Burst 状态下的爆发逻辑
## _spawn_one_enemy() — 生成单个敌人
## _finish_spawning() — 完成刷怪
## select_enemy_type_from_mix() — 加权随机选择
## select_spawn_point() — 刷怪点选择
## _random_excluding_last() — 避免连续同一点
## _random_offset() — 随机偏移
## _should_burst() — 判断是否进入爆发
## calculate_burst_interval() — 计算爆发间隔
```

#### 波次系统 → 生成系统（调用方视角）

```gdscript
# 波次系统调用：
spawn_system.start_spawning(wave_config)   # 开始刷怪
spawn_system.stop_spawning()               # 强制停止
spawn_system.is_spawning()                 # 查询是否正在刷怪
spawn_system.get_total_spawned()          # 查询已生成数量

# 波次系统监听：
spawn_system.spawning_started.connect(_on_spawning_started)
spawn_system.enemy_spawned.connect(_on_enemy_spawned)
spawn_system.spawning_finished.connect(_on_spawning_finished)
spawn_system.spawning_stopped.connect(_on_spawning_stopped)
```

#### 生成系统 → 地图系统

```gdscript
# 只读查询，通常在 start_spawning() 时调用一次
var spawn_points: Array[Vector2] = map_system.get_spawn_points()
```

#### 生成系统 → 敌人系统

```gdscript
# 生成单个敌人
var enemy: Node = enemy_system.spawn_enemy(enemy_type, spawn_position)
```

### 6.4 数据流

```
波次系统 ─── WaveConfig ───→ 敌人生成系统
                                │
                    select_enemy_type()  ←── enemy_mix 权重表
                    select_spawn_point() ←── map_system.get_spawn_points()
                                │
                    spawn_enemy(type, pos)
                                ▼
                           敌人系统
                                │
                         敌人实例化
                                │
                    spawn_system.enemy_spawned 信号
                                ├─→ 波次系统（追踪计数）
                                ├─→ UI 系统（可选显示）
                                └─→ 音频系统（可选音效）
```

---

## 7. Tuning Knobs

### 7.1 调参值列表

所有调参值存储在 `assets/data/spawn_system_config.json` 中，不应硬编码。

```json
{
  "spawn_offset_radius": 40.0,
  "min_burst_interval": 0.05,
  "min_burst_duration": 1.0,
  "burst_threshold_ratio": 0.8
}
```

| 参数名 | 类型 | 默认值 | 安全范围 | 类别 | 影响面 |
|--------|------|--------|---------|------|--------|
| `spawn_offset_radius` | float | 40.0px | 20-80px | feel | 刷怪点随机偏移半径。过小导致敌人叠点，过大可能偏入障碍物区域 |
| `min_burst_interval` | float | 0.05s | 0.03-0.15s | gate | 爆发时最小间隔。过小会导致单帧生成过多敌人（帧率骤降），过大则爆发缺乏紧迫感 |
| `min_burst_duration` | float | 1.0s | 0.5-3.0s | gate | 爆发最短持续时间下限。给玩家最后的反应时间。过小则"突然满屏怪"，过大则拖延节奏 |
| `burst_threshold_ratio` | float | 0.8 | 0.5-0.95 | curve | 触发爆发的波次时长百分比。过低则过早爆发破坏节奏，过高则可能来不及触发 |

### 7.2 从波次配置间接消费的旋钮

这些值不存储在生成系统的配置中，但显著影响生成行为：

| 波次参数 | 类别 | 对生成系统的影响 |
|---------|------|-----------------|
| `spawn_budget` | gate | 决定总生成次数。越大 = 生成周期越长 |
| `spawn_interval_sec` | feel + gate | 决定生成节奏。越小 = 压力密度越高 |
| `enemy_mix` | curve | 决定敌人类型分布。影响每局的可预期性 |
| `duration_sec` | gate | 影响爆发触发时机。越短越容易触发爆发 |

### 7.3 极端值说明

| 参数 | 极端低值 | 极端高值 |
|------|---------|---------|
| `spawn_offset_radius < 15px` | 敌人几乎叠在同一像素，视觉上像"从洞里挤出来" | 敌人散布过大（> 80px），某些敌人可能直接生成在玩家附近 |
| `min_burst_interval < 0.02s` | 每帧可生成 ≥1 个，极端情况下一帧生成全部剩余预算，引起帧率下降 | 爆发间隔 ≥ 正常间隔，爆发失去意义 |
| `burst_threshold_ratio < 0.5` | 波次刚过一半就爆发，破坏正常节奏 | 阈值 > 0.95 时可能来不及触发爆发就波次结束了 |
| `min_burst_duration < 0.3s` | 剩余大量敌人在 0.3s 内全部刷出，玩家无反应时间 | > 3.0s 时爆发拖得太长，可能超过波次自然结束时间 |

### 7.4 调参建议

- 如果 playtest 反馈"怪物刷得太突然"，先增加 `burst_threshold_ratio`（如 0.8 → 0.9），让正常间隔阶段更长。
- 如果反馈"最后几个怪刷太慢拖节奏"，先降低 `min_burst_duration`（如 1.0 → 0.7）。
- 如果反馈"怪物都从一个点出来"，增加 `spawn_offset_radius` 至 60px。
- **不要**在 MVP 阶段调整 `min_burst_interval` 低于 0.05s——性能风险大于视觉收益。

---

## 8. Acceptance Criteria

### 功能测试

| ID | 验证项 | 测试方法 | Pass 标准 |
|----|--------|---------|----------|
| AC-01 | 状态机完整流转 | 调用 `start_spawning(config)` → 等待预算耗尽 → 检查状态 | 状态按 `Idle → Active → Complete → Idle` 流转，无状态卡死 |
| AC-02 | 间隔刷怪间隔准确 | 使用 spawn_budget=5, spawn_interval=1.0s，记录每个敌人的生成时间戳 | 相邻敌人生成间隔在 0.95s ~ 1.05s 范围内（允许 5% 帧率误差） |
| AC-03 | spawn_budget 精确执行 | spawn_budget=12，记录总共生成的敌人数量 | `total_spawned == 12`，不多不少 |
| AC-04 | 敌人类型分布符合权重 | spawn_budget=1000, enemy_mix={"a":70,"b":20,"c":10}，统计每种类型出现次数 | 各类型出现频率与权重偏差 < 5%（大数定律） |
| AC-05 | 刷怪点不连续重复 | 记录连续 20 次刷怪点的索引 | 没有连续两次相同索引 |
| AC-06 | 刷怪位置有随机偏移 | 同一刷怪点连续生成 2 个敌人，检查实际位置差 | 位置差 < `spawn_offset_radius * 2 * sqrt(2)` ≈ 113px（最大可能差值）且 > 0 |
| AC-07 | enemy_spawned 信号正确发出 | 监听信号并记录 | 每生成一个敌人，信号发出一次，参数为正确的敌人节点引用 |
| AC-08 | spawning_finished 在预算耗尽时发出 | spawn_budget=3, 等待刷完 | 第 3 个敌人生成 ≤ 0.1s 后发出 `spawning_finished(3)` |
| AC-09 | stop_spawning 正确清理 | Active 状态调用 `stop_spawning()` | 状态转为 `Stopped`，发 `spawning_stopped`，不再生成新敌人 |
| AC-10 | 空预算直接完成 | spawn_budget=0 | 直接发出 `spawning_finished(0)`，不进入 Active 状态 |
| AC-11 | 爆发模式触发 | 模拟 elapsed_time >= duration * 0.8 且 remaining_budget > 0 | 状态转为 `BURST`，生成间隔缩短 |
| AC-12 | 爆发间隔不小于下限 | 剩余预算 20 个，剩余时间 0.1s | `burst_interval = max(0.1/20, 0.05) = 0.05s`，每帧最多生成 0 个（0.05 > 0.01667），安全 |
| AC-13 | 游戏暂停期间不刷怪 | 刷怪进行中，设置 `Engine.time_scale = 0` | spawn_timer 不再增加，无新敌人生成 |
| AC-14 | 间隔漂移控制 | spawn_interval=1.0s，运行 60 秒 | 60 秒内生成次数 = 60 ± 1 次（漂移 < 2%） |

### 敌人类型测试

| ID | 验证项 | 测试方法 | Pass 标准 |
|----|--------|---------|----------|
| AC-T01 | enemy_mix 为空回退 | enemy_mix = {}，生成 10 个敌人 | 全部为 `normal_a`，日志输出告警 |
| AC-T02 | 权重和不为 1.0 | enemy_mix = {"a": 7, "b": 3}（和=10） | 概率分布等效于 {"a": 0.7, "b": 0.3} |
| AC-T03 | 未知敌人类型 | enemy_mix = {"unknown": 1.0} | 敌人系统回退到 `normal_a`，生成系统记录警告 |

### 刷怪点测试

| ID | 验证项 | 测试方法 | Pass 标准 |
|----|--------|---------|----------|
| AC-S01 | 地图系统返回空数组 | `get_spawn_points()` 返回 `[]` | 使用默认坐标 `(-32, -32)`，日志严重告警 |
| AC-S02 | 地图系统返回 1 个点 | `get_spawn_points()` 返回 `[Vector2(100,100)]` | 所有敌人都在此点 + offset 位置生成，无错误 |
| AC-S03 | 8 个刷怪点均有使用 | spawn_budget=80（每点期望 10 次） | 每个刷怪点至少被选择 5 次（卡方检验 p > 0.05） |

### 性能测试

| ID | 验证项 | Pass 标准 |
|----|--------|----------|
| AC-P01 | 单帧生成开销 | `spawn_one_enemy()` 调用（不含敌人系统实例化）< 0.5ms |
| AC-P02 | 完整刷怪周期开销 | 从 spawning_started 到 spawning_finished 期间，生成系统自身逻辑每帧 < 0.1ms（纯计时器和计数器） |
| AC-P03 | 爆发模式帧率影响 | 剩余 20 个敌人触发爆发，60 FPS 下帧率不低于 55 FPS |
| AC-P04 | 内存管理 | 100 个敌人全部生成并死亡后，生成系统不持有任何敌人引用 |

### 集成测试

| ID | 验证项 | 验证方法 | Pass 标准 |
|----|--------|---------|----------|
| AC-I01 | 波次系统 → 生成系统 | 波次 1 开始，检查生成系统状态 | `spawn_system.state == ACTIVE`，`spawn_system.remaining_budget == WaveConfig.spawn_budget` |
| AC-I02 | 生成系统 → 波次系统 | 预算耗尽，波次系统收到 `spawning_finished` | 波次系统状态转为 `WaveClearing` |
| AC-I03 | 地图系统集成 | `start_spawning` 调用后检查使用的刷怪点 | 所有生成位置均来自 `map_system.get_spawn_points()` 的 8 个点 + offset |
| AC-I04 | 敌人系统集成 | 每个生成的敌人有正确的类型和位置 | `enemy.get_enemy_type()` 返回预期类型，`enemy.global_position` 在刷怪点附近 |
| AC-I05 | 玩家死亡中断 | 刷怪进行中触发玩家死亡 | `stop_spawning()` 被调用，生成系统不再生成新敌人 |
| AC-I06 | UI 消费信号 | UI 监听 `spawning_started` 和 `spawning_finished` | UI 正确显示/隐藏"刷怪进行中"指示器 |

---

## Open Questions

| # | 问题 | 影响范围 | 建议方案 | 决策时间 |
|---|------|---------|---------|---------|
| OQ-01 | 是否需要方向轮换策略？（避免连续 5 次从北侧刷怪） | 刷怪体验、关卡策略 | **MVP 不做方向限制**——纯随机 + 不连续同一点已足够分散。若 playtest 发现某一侧压力过大，可在 v1.0 追加方向权重平衡（如"上次刷北侧，则下次北侧概率降低 50%"）。 | v1.0 阶段 |
| OQ-02 | 爆发模式是否需要视觉提示？ | UI/UX、玩家预期 | **建议有**。爆发时屏幕边缘可以有可爱的"怪物加速涌入"提示效果（如边框加速闪动）。MVP 可以先不做，但至少需要在 wave-system 中预留信号接口。 | 原型验证后 |
| OQ-03 | 是否应限制同时存活的敌人数量上限？ | 性能、平衡 | **生成系统不限制总存活数**——存活上限应由波次系统的 spawn_budget 和 difficulty_curve 控制。如果 playtest 发现同屏 100+ 敌人导致帧率 < 30，应由 economy-designer 调整 spawn_budget/duration 的比值。 | 原型验证后 |
| OQ-04 | 刷怪音效应该在哪个阶段播放？ | 音频、UX | 建议每个敌人生成时播放一个短促的可爱音效（如"喵"或"噗"），但在爆发模式下合并为一个连续音效（避免音效洪水）。音频设计师确认 MVP 是否需要刷怪音效。 | 待音频设计师确认 |
| OQ-05 | 敌人生成位置是否应该在刷怪点外更远/更近的位置有特殊配置？ | 关卡设计 | MVP 统一 ±40px 随机偏移。v1.0 可以支持每个刷怪点独立的"offset_range"配置，某些点偏移更大（模拟怪物从更远处涌来）。 | v1.0 阶段 |
| OQ-06 | 如果波次系统的 `duration_sec` 比 `expected_spawning_duration` 短很多（配置不一致），生成系统是否应主动告警？ | 数值一致性 | **建议有**。在 `start_spawning()` 时计算 expected_duration，如果 `expected_duration > duration_sec * 1.2`（超出 20%），输出设计警告日志。这能帮助数值策划尽早发现配置冲突。 | 当前阶段确认 |
| OQ-07 | 生成系统是否需要"预加载"敌人场景资源？ | 加载性能 | MVP 不预加载——`load()` 调用在首次生成时按需加载。如果 playtest 发现第一个敌人生成时有微卡顿，可在 `_ready()` 中预载所有敌人场景（`preload()` 或 `ResourceLoader.load()`）。 | 原型验证后 |
