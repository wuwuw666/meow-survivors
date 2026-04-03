# 难度曲线系统 (Difficulty Curve System)

> **Status**: Approved
> **Author**: [user + agents]
> **Last Updated**: 2026-04-02
> **Implements Pillar**: 成长的爽感 + 策略有深度

---

## Overview

难度曲线系统是一个纯配置驱动的数值系统，用来定义每一波敌人的压力如何增长。它不直接生成敌人，也不处理战斗逻辑，而是向波次系统和敌人生成系统提供 `WaveConfig`，其中包含敌人数量、敌人组成、属性倍率、生成间隔、波次时长以及是否为里程碑波等信息。

这个系统存在的意义，是把“玩家变强”和“敌人变强”维持在一个持续拉扯的节奏里。前期让玩家快速进入状态，中期逼出走位与塔位决策，后期让玩家感到局势紧张但仍有翻盘空间。如果没有这一层，波次系统只能机械刷怪，无法稳定支撑 10 波 MVP 的体验目标，也无法为后续无尽模式提供可调的成长框架。

**核心接口**:
- `get_wave_config(wave_number: int) -> WaveConfig`
- `get_endless_wave_config(loop_wave_number: int, endless_depth: int) -> WaveConfig`
- `is_milestone_wave(wave_number: int) -> bool`

---

## Player Fantasy

难度曲线系统服务的不是“复杂操作”，而是“越来越危险，但我也越来越离谱”的生存爽感。玩家在每一波中都应该感到自己刚拿到的升级和塔位决策立刻产生效果，但系统也会不断抬高压力，让玩家不能只靠原地站桩。

**情感目标**:
- **前期 1-3 波**: 安全感和掌控感。玩家迅速理解移动、自动攻击、塔位和升级循环。
- **中期 4-7 波**: 压力上升。玩家开始明显感受到敌人数增加、精英敌人登场、站位失误会付出代价。
- **后期 8-10 波**: 紧张与爆发并存。玩家 build 已经很强，但怪潮也开始逼近极限，形成“差一点扛不住，但还能靠正确选择打回来”的高潮。
- **无尽波**: 不是全新规则，而是把已经建立的压力关系继续往上推，考验 build 的上限和调参是否健康。

**玩家应该感受到**:
- “我每次升级后，下一波都更能打。”
- “每隔几波会有一个明显台阶，让我重新评估站位和塔位。”
- “第 10 波像一场小 Boss 战，是一局完整 run 的高潮。”

**玩家不应该感受到**:
- 某一波突然失控，像被数值硬杀。
- 前几波过于无聊，像教学拖时间。
- 后几波只是堆血堆怪，没有新的决策压力。

---

## Detailed Design

### Core Rules

#### 1. 波次结构

MVP 固定为 **10 波主流程 + 可选无尽模式**。

| 波段 | 波次 | 设计目的 | 主要压力来源 |
|------|------|----------|--------------|
| **建立期** | 1-3 | 教玩家系统、建立成长反馈 | 少量敌人、低属性、低密度 |
| **施压期** | 4-6 | 开始要求走位和塔位配合 | 数量上升、精英敌人引入 |
| **考核期** | 7-9 | 检验 build 是否成型 | 密度提升、属性提升、敌种混合 |
| **高潮期** | 10 | 一局收束点 | 里程碑波，敌人强度和节奏显著提高 |

#### 2. 三维度增长

每一波的难度由三个维度共同增长：

1. **数量增长**: 该波总敌人数增加，形成更高场面压力。
2. **属性增长**: 敌人生命、攻击、移动速度按波次增长，避免只有“更多杂兵”。
3. **敌种解锁**: 随波次引入新的敌人类型，让压力来源发生变化，而不是单纯堆数值。

三者的优先级为：
- 前期以数量增长为主，让玩家更容易读懂变化。
- 中期同时提升数量和敌种复杂度。
- 后期以混合敌种和属性倍率为主，制造决策压力。

#### 3. 里程碑波规则

第 `3`、`6`、`10` 波为里程碑波，其中第 `10` 波是最高级别里程碑波。

| 波次 | 类型 | 规则 |
|------|------|------|
| 3 | 小里程碑 | 敌人数量小幅减少，但引入第一种高威胁敌人 |
| 6 | 中里程碑 | 生成节奏更紧，精英敌人占比提高 |
| 10 | 大里程碑 | 视为本局高潮波，使用最高属性倍率和最复杂敌群组合 |

里程碑波的目标不是单纯变难，而是让玩家明确感受到“新的阶段开始了”。

#### 4. 波次节奏规则

- 每波有固定持续时间和固定刷怪预算。
- 一波结束的条件为：
  - 达到该波计划刷怪预算，且场上敌人全部被清空。
- 若计划刷怪预算已经刷完，但场上仍有敌人，则进入 **清场尾声阶段**，不再继续刷新，等待玩家处理残局。
- 每波结束后给出固定的 **结算/升级窗口**，让玩家能在高压和决策之间形成清晰节奏切换。

#### 5. 无尽模式规则

- 玩家通过第 10 波后，可选择继续。
- 无尽模式沿用第 8-10 波的敌种池，但继续提高数量预算、属性倍率和精英占比。
- 无尽模式不再引入全新基础规则，只做“已知规则的持续加压”。
- 为避免数值爆炸，无尽模式增长率必须低于主流程后段的跃迁幅度。

### States and Transitions

难度曲线系统本身是无状态配置系统，但它输出的数据会被波次系统按阶段消费。可以把它视为以下四个使用状态：

| 状态 | 描述 | 进入条件 | 输出 |
|------|------|----------|------|
| **PreRun** | 开局准备阶段 | 新 run 开始 | 提供第 1 波配置 |
| **MainRun** | 主流程阶段 | 波次 1-10 进行中 | 提供标准 `WaveConfig` |
| **Endless** | 无尽阶段 | 第 10 波后玩家选择继续 | 提供 `EndlessWaveConfig` |
| **Finished** | 本局结束 | 玩家死亡或主动退出 | 不再输出新配置 |

**状态切换规则**:

| 当前状态 | 触发事件 | 目标状态 |
|----------|----------|----------|
| PreRun | run_start | MainRun |
| MainRun | wave_complete 且 wave_number < 10 | MainRun |
| MainRun | wave_10_complete 且 player_continue = true | Endless |
| MainRun | wave_10_complete 且 player_continue = false | Finished |
| MainRun / Endless | player_dead | Finished |

### Interactions with Other Systems

| 系统 | 交互方向 | 数据接口 | 说明 |
|------|----------|----------|------|
| **波次系统** | 难度曲线 -> 波次 | `get_wave_config(wave_number)` | 波次系统是主要消费者，负责在每波开始时拉取配置 |
| **敌人生成系统** | 波次 -> 敌人生成 | `enemy_mix`, `spawn_interval`, `spawn_budget` | 难度曲线不直接刷怪，只定义刷怪参数 |
| **敌人系统** | 难度曲线 -> 敌人 | `hp_multiplier`, `damage_multiplier`, `speed_multiplier` | 敌人系统在生成实例时应用倍率 |
| **升级选择系统** | 间接约束 | `upgrade_pause_duration`, `milestone_reward_bias` | 影响玩家多频繁进入升级决策窗口 |
| **地图系统** | 地图 -> 难度曲线 | `map_pressure_modifier` | 小地图或狭窄地图可提供全局压力修正 |
| **UI系统** | 难度曲线 -> UI | `is_milestone_wave`, `threat_level` | 用于提前提示危险波次 |

**接口所有权**:
- 难度曲线系统拥有 `WaveConfig` 的字段定义和默认值。
- 波次系统拥有“何时请求配置、何时开始/结束一波”的时序控制。
- 敌人生成系统拥有“如何把配置转成实际刷怪事件”的执行逻辑。

**WaveConfig 建议结构**:

```gdscript
class_name WaveConfig

var wave_number: int
var duration_sec: float
var spawn_budget: int
var spawn_interval_sec: float
var enemy_mix: Dictionary
var hp_multiplier: float
var damage_multiplier: float
var speed_multiplier: float
var elite_chance: float
var is_milestone: bool
var threat_level: int
var upgrade_pause_sec: float
```

---

## Formulas

### 1. 变量定义

| 变量 | 含义 | 默认值 / 范围 |
|------|------|----------------|
| `w` | 当前波次编号 | 主流程 `1-10` |
| `base_enemy_count` | 第 1 波基础敌人数 | `12` |
| `count_growth` | 每波基础数量增长率 | `0.18` |
| `base_hp_mult` | 第 1 波生命倍率 | `1.0` |
| `hp_growth` | 每波生命增长率 | `0.12` |
| `base_damage_mult` | 第 1 波攻击倍率 | `1.0` |
| `damage_growth` | 每波攻击增长率 | `0.10` |
| `base_speed_mult` | 第 1 波移速倍率 | `1.0` |
| `speed_growth` | 每 2 波移速增长率 | `0.03` |
| `milestone_bonus` | 里程碑波额外倍率 | `0.20` |
| `boss_bonus` | 第 10 波额外倍率 | `0.68` |
| `base_spawn_interval` | 第 1 波基础刷怪间隔 | `1.20s` |
| `spawn_interval_decay` | 每波刷怪间隔缩短值 | `0.07s` |
| `min_spawn_interval` | 最低刷怪间隔 | `0.35s` |

### 2. 基础敌人数公式

```text
enemy_count(w) = round(base_enemy_count * (1 + count_growth * (w - 1)))
```

默认示例：

```text
enemy_count(1) = round(12 * (1 + 0.18 * 0)) = 12
enemy_count(5) = round(12 * (1 + 0.18 * 4)) = 21
enemy_count(10) = round(12 * (1 + 0.18 * 9)) = 31
```

若为里程碑波，数量不直接暴涨，而是通过敌种和倍率增加压力，因此额外数量只加 `+10%`：

```text
milestone_enemy_count(w) = round(enemy_count(w) * 1.10)
```

### 3. 属性倍率公式

敌人生命倍率：

```text
hp_multiplier(w) = base_hp_mult + hp_growth * (w - 1)
```

敌人攻击倍率：

```text
damage_multiplier(w) = base_damage_mult + damage_growth * (w - 1)
```

敌人移速倍率按双波阶梯增长：

```text
speed_multiplier(w) = base_speed_mult + floor((w - 1) / 2) * speed_growth
```

里程碑波加成：

```text
if wave 3 or 6:
  hp_multiplier *= (1 + milestone_bonus)
  damage_multiplier *= (1 + milestone_bonus)

if wave 10:
  hp_multiplier *= (1 + boss_bonus)
  damage_multiplier *= (1 + boss_bonus)
  speed_multiplier *= 1.10
```

### 4. 刷怪间隔公式

```text
spawn_interval(w) = max(min_spawn_interval, base_spawn_interval - spawn_interval_decay * (w - 1))
```

默认示例：

```text
spawn_interval(1) = 1.20s
spawn_interval(4) = 0.99s
spawn_interval(8) = 0.71s
spawn_interval(10) = 0.57s
```

第 10 波额外乘以 `0.9`，形成更密集的高潮感。

### 5. 敌种解锁规则

敌种不是完全随机，而是按波段解锁：

| 波次 | 可出现敌种 |
|------|------------|
| 1-2 | 普通近战敌人 |
| 3-4 | 普通近战 + 快速敌人 |
| 5-6 | 普通近战 + 快速敌人 + 高血敌人 |
| 7-9 | 普通近战 + 快速敌人 + 高血敌人 + 远程/骚扰敌人 |
| 10+ | 全敌种池 + 精英权重提高 |

敌种权重示例：

```text
Wave 1: { basic_melee: 1.0 }
Wave 3: { basic_melee: 0.75, fast_enemy: 0.25 }
Wave 6: { basic_melee: 0.50, fast_enemy: 0.25, tank_enemy: 0.25 }
Wave 10: { basic_melee: 0.35, fast_enemy: 0.20, tank_enemy: 0.25, ranged_enemy: 0.20 }
```

### 6. 精英敌人概率公式

```text
elite_chance(w) = clamp(0.00 + 0.03 * (w - 4), 0.0, 0.25)
```

解释：
- 1-3 波不生成精英。
- 第 4 波开始有极低概率。
- 第 10 波可达到约 `18%`。
- 无尽模式最多不超过 `25%`，避免场面读不清。

### 7. 无尽模式增长公式

令：
- `d` = 无尽深度，玩家通过第 10 波后的第几轮加压，从 `1` 开始。

```text
endless_enemy_count(d) = round(enemy_count(10) * (1 + 0.10 * d))
endless_hp_multiplier(d) = hp_multiplier(10) * (1 + 0.08 * d)
endless_damage_multiplier(d) = damage_multiplier(10) * (1 + 0.06 * d)
endless_spawn_interval(d) = max(0.28, spawn_interval(10) - 0.03 * d)
```

无尽模式增长比主流程后段更平滑，避免第 11-12 波立刻断崖式失控。

### 8. 1-10 波示例表

| 波次 | 总敌人数 | 生命倍率 | 攻击倍率 | 移速倍率 | 刷怪间隔 | 备注 |
|------|----------|----------|----------|----------|----------|------|
| 1 | 12 | 1.00 | 1.00 | 1.00 | 1.20s | 教学波 |
| 2 | 14 | 1.12 | 1.10 | 1.00 | 1.13s | 轻微加压 |
| 3 | 17 | 1.49 | 1.44 | 1.03 | 1.06s | 小里程碑 |
| 4 | 18 | 1.36 | 1.30 | 1.03 | 0.99s | 引入快敌 |
| 5 | 21 | 1.48 | 1.40 | 1.06 | 0.92s | build 检测开始 |
| 6 | 25 | 1.92 | 1.92 | 1.06 | 0.85s | 中里程碑 |
| 7 | 25 | 1.72 | 1.60 | 1.09 | 0.78s | 敌群组合复杂化 |
| 8 | 27 | 1.84 | 1.70 | 1.09 | 0.71s | 中后期压迫 |
| 9 | 29 | 1.96 | 1.80 | 1.12 | 0.64s | 终局前检定 |
| 10 | 34 | 3.50 | 3.19 | 1.23 | 0.51s | 大里程碑 / Boss波 |

说明：
- 里程碑波采用“少量额外数量 + 明显属性加成 + 更复杂敌种”。
- 表中数值为第一版平衡基线，后续可通过 playtest 回调。

---

## Edge Cases

| 边界情况 | 处理方式 |
|----------|----------|
| 玩家在极短时间内清空当前波所有敌人 | 若该波刷怪预算未完成，则继续按计划刷新；不能因为清得快而提前结束该波 |
| 该波刷怪预算完成，但场上仍有大量残敌 | 停止新增刷怪，进入清场尾声阶段，等待玩家清完后再进入结算 |
| 地图空间不足导致刷怪点被占用 | 允许敌人生成系统延后或换点生成，但不得突破该波总刷怪预算 |
| 某波敌种配置引用了未实现的敌人类型 | 回退为同波段的基础敌种组合，并记录为设计错误待修复 |
| 里程碑波过难导致新手在固定波次频繁卡死 | 优先下调敌种权重或刷怪密度，不先砍掉成长反馈 |
| 精英敌人和高血敌人同时过多，导致场面失读 | 强制限制同屏精英数量上限，由敌人生成系统执行 |
| 无尽模式数值无限膨胀 | 对 `elite_chance`、`spawn_interval`、同屏数量设硬上限，保证可读性和性能 |
| 玩家在升级窗口期间切换到下一波 | 不允许。下一波只能在升级窗口关闭后启动，维持节奏清晰 |
| 玩家 build 非常强，导致第 10 波被秒清 | 仍然允许，这是成长回报的一部分；只要该波在一般 build 下仍具压力即可 |
| 玩家 build 极弱，导致第 4-5 波已明显无法推进 | 视为难度曲线前段过陡，需要下调前中期增长率 |

---

## Dependencies

### 上游依赖

难度曲线系统是 Foundation / Meta 层系统，原则上不依赖其他运行时系统，但依赖以下设计输入：

| 依赖项 | 类型 | 用途 |
|--------|------|------|
| **游戏概念文档** | 设计依赖 | 决定 10 波 MVP、成长节奏与目标时长 |
| **敌人系统的数据定义** | 软依赖 | 需要知道有哪些敌种可供配置 |
| **地图系统** | 软依赖 | 地图大小和塔位密度会影响压力修正 |

### 下游依赖

| 系统 | 依赖类型 | 数据接口 | 说明 |
|------|----------|----------|------|
| **波次系统** | 硬依赖 | `get_wave_config()` | 没有难度配置，波次系统无法定义每波内容 |
| **敌人生成系统** | 硬依赖 | `spawn_budget`, `enemy_mix`, `spawn_interval_sec` | 按配置执行刷怪 |
| **敌人系统** | 硬依赖 | `hp_multiplier`, `damage_multiplier`, `speed_multiplier` | 生成时应用属性倍率 |
| **UI系统** | 软依赖 | `is_milestone`, `threat_level` | 显示下一波提示和危险等级 |
| **升级选择系统** | 软依赖 | `upgrade_pause_sec` | 让升级窗口与波次节奏匹配 |

### 接口定义

```gdscript
class_name DifficultyCurveSystem

func get_wave_config(wave_number: int) -> WaveConfig
func get_endless_wave_config(loop_wave_number: int, endless_depth: int) -> WaveConfig
func is_milestone_wave(wave_number: int) -> bool
```

---

## Tuning Knobs

| 参数名 | 类型 | 默认值 | 安全范围 | 影响 |
|--------|------|--------|----------|------|
| `base_enemy_count` | int | 12 | 8-18 | 决定前两波是否轻松易懂 |
| `count_growth` | float | 0.18 | 0.10-0.25 | 决定每波数量增长速度 |
| `hp_growth` | float | 0.12 | 0.08-0.18 | 决定敌人是否越来越难清 |
| `damage_growth` | float | 0.10 | 0.06-0.15 | 决定容错空间下降速度 |
| `speed_growth` | float | 0.03 | 0.00-0.06 | 决定走位压力上升速度 |
| `milestone_bonus` | float | 0.20 | 0.10-0.30 | 控制第 3/6 波阶段跃迁感 |
| `boss_bonus` | float | 0.68 | 0.40-0.80 | 控制第 10 波高潮感 |
| `base_spawn_interval` | float | 1.20 | 0.90-1.40 | 决定前期场面密度 |
| `spawn_interval_decay` | float | 0.07 | 0.04-0.10 | 决定波次节奏压缩速度 |
| `min_spawn_interval` | float | 0.35 | 0.28-0.50 | 决定系统允许的最大刷新密度 |
| `elite_chance_growth` | float | 0.03 | 0.01-0.05 | 决定精英敌人出现频率 |
| `endless_count_growth` | float | 0.10 | 0.05-0.15 | 决定无尽模式场面扩张速度 |
| `endless_hp_growth` | float | 0.08 | 0.04-0.12 | 决定无尽模式血量膨胀速度 |

**调参原则**:
- 如果玩家反馈“前 3 波太无聊”，优先提高 `base_enemy_count` 或略微降低 `base_spawn_interval`。
- 如果玩家反馈“中期突然顶不住”，优先下调 `milestone_bonus` 或 `damage_growth`。
- 如果玩家反馈“后期只是怪更肉，不更有趣”，优先调整敌种权重，而不是继续堆 `hp_growth`。
- 如果性能先爆而玩法还没到高潮，优先提高属性倍率，少加数量。

**极端值说明**:
- `count_growth > 0.25` 会让第 7-10 波场面过度拥挤，影响性能与可读性。
- `damage_growth > 0.15` 会让容错下降过快，玩家容易感觉被秒杀。
- `min_spawn_interval < 0.28` 容易让刷怪系统和碰撞系统超预算。

---

## Acceptance Criteria

### 玩法目标

| ID | 验证项 | Pass 标准 |
|----|--------|-----------|
| AC-01 | 第 1-2 波新手体验 | 首次游玩玩家在不理解 build 的前提下，仍能稳定通过前 2 波 |
| AC-02 | 第 3 波阶段感知 | 玩家能明确感受到第 3 波与前两波不同，是第一次“认真打”的波次 |
| AC-03 | 第 5-6 波 build 检测 | 若玩家升级和塔位选择失衡，会在第 5-6 波明显感到压力 |
| AC-04 | 第 10 波高潮感 | 第 10 波必须显著强于第 9 波，且像一局 run 的自然高潮 |
| AC-05 | 无尽模式平滑衔接 | 第 11 波不能比第 10 波突然跳崖式变难，增长必须连续 |

### 数值验证

| ID | 验证项 | Pass 标准 |
|----|--------|-----------|
| AC-06 | 敌人数增长 | 1-10 波总敌人数单调递增，里程碑波允许小幅额外加成 |
| AC-07 | 属性增长 | 生命、攻击倍率在 1-10 波内整体递增，不允许出现倒退 |
| AC-08 | 刷怪节奏 | 刷怪间隔单调递减，但不低于 `min_spawn_interval` |
| AC-09 | 精英概率控制 | 主流程前 3 波不出现精英，第 10 波精英概率不超过 `20%` |
| AC-10 | 同屏压力控制 | 默认配置下同屏敌人数量应维持在目标性能预算内，不因单波配置失控 |

### 集成验证

| ID | 验证项 | Pass 标准 |
|----|--------|-----------|
| AC-11 | 波次系统接入 | 波次系统能够仅通过 `get_wave_config()` 启动完整 10 波流程 |
| AC-12 | 敌人生成系统接入 | 敌人生成系统能正确消费 `enemy_mix`, `spawn_budget`, `spawn_interval_sec` |
| AC-13 | UI提示接入 | UI 能正确标出里程碑波和威胁等级 |
| AC-14 | 平衡可调性 | 设计师只修改 tuning knobs，不改代码，也能完成一轮难度回调 |

### Playtest 判据

| ID | 验证项 | Pass 标准 |
|----|--------|-----------|
| AC-15 | 新手挫败点 | 大多数新手第一次失败应发生在第 4-7 波，而不是第 1-3 波 |
| AC-16 | 普通成功率 | 熟悉操作但不懂最优 build 的玩家，应有机会稳定打到第 8-10 波 |
| AC-17 | 强 build 爽感 | 高 synergy build 在第 8-10 波应明显展现清场能力，而不是只“勉强活着” |

---

## Open Questions

- 第 10 波是否做成单体 Boss 主导，还是“Boss + 怪潮混合”更符合本作节奏？
- 升级选择是固定每波后触发，还是允许经验满级时中断当前波次，需要和升级系统一起确认。**临时假设**：当前 `WaveConfig.upgrade_pause_sec` 的语义为"每波结束后的固定升级窗口时长"，若改为波中中断则该字段需重新定义。
- 地图尺寸和塔位密度是否需要作为难度曲线的全局修正项，待地图系统设计后再确认。
- 第 3 波和第 6 波是否需要额外的 UI 预警或音效强化，以帮助玩家感知“阶段切换”。
