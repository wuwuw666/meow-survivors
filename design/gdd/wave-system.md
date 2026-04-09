# 波次系统 (Wave System)

> **Status**: In Design  
> **Author**: [user + agents]  
> **Last Updated**: 2026-04-09  
> **Implements Pillar**: 成长的爽感（节奏推进）+ 策略有深度（防线阶段压力）

## Overview

波次系统（Wave System）是《喵族幸存者》局内节奏的调度器。  
它负责把一局 4-8 分钟的短局体验切成清晰的阶段，让玩家在“布防、补位、清怪、升级、下一波”之间形成稳定节奏。

在当前设计方向中，波次系统的职责不是“代替经验系统发升级”，而是：

- 推进敌潮节奏
- 控制每波压力曲线
- 提供短暂但明确的呼吸感
- 为经验升级和防线调整留出空间
- 把整局推向第 10 波 Boss 的高潮

**核心职责**：

- 启动与结束每一波
- 驱动敌人生成系统开始/停止生成
- 追踪当前波是否清场
- 在波与波之间提供很短的整理窗口
- 在第 10 波构建明确高潮
- 在玩家死亡时终止推进

**核心接口**：

- `start_wave() -> void`
- `get_current_wave() -> int`
- `is_wave_active() -> bool`
- `signal wave_started(wave_number: int)`
- `signal wave_cleared(wave_number: int)`
- `signal intermission_started(wave_number: int)`
- `signal boss_wave_started()`
- `signal game_over(wave_number: int)`

---

## Player Fantasy

波次系统带来的体验，不是“怪随机一直来”，而是：

- “这一波我守住了。”
- “我终于有一点点时间看下局势。”
- “下一波更强了，但我的线也更成型了。”
- “第 10 波来了，这就是整局的高潮。”

玩家应该感受到：

- 压力是逐波升级的
- 每波结束都有短促但真实的喘息
- 一局是不断累积成型，而不是混乱拖长

玩家不应该感受到：

- 波次存在感很弱，像无尽刷怪
- 波间停顿太长，破坏短局节奏
- 波间停顿太短，完全没有整理价值
- 升级和波次互相打架，不知道到底是谁在驱动成长

---

## Design Direction

### 波次系统服务“短局塔防成长”

当前项目已经明确：

- **MVP 一局目标时长：4-8 分钟**
- **经验升级是主要成长入口**
- **波次系统负责节奏、压力和高潮**

因此波次系统不应该承担“主要升级触发器”的职责。  
它可以与升级系统协作，但不能抢走经验成长的主轴。

### 波间整理窗口要短

波次结束后允许有一个简短整理窗口，但它的目的不是长时间停顿，而是：

- 让玩家意识到“这波结束了”
- 给玩家一点点观察与调整机会
- 给 UI 明确的节奏反馈
- 让下一波开始更有推动感

MVP 设计建议：

- 普通波整理时间：`1.0 - 2.0s`
- Boss 前提示时间：`2.0 - 3.0s`

---

## Detailed Design

### 规则 1：波次生命周期

当前版本采用简化状态机：

```text
Idle → Spawning → Clearing → Intermission → Idle
                           ↘
                            GameOver
```

状态定义：

| 状态 | 说明 |
|------|------|
| **Idle** | 等待下一波开始 |
| **Spawning** | 当前波正在生成敌人 |
| **Clearing** | 当前波已停止生成，等待场上残敌清完 |
| **Intermission** | 短暂整理窗口，准备下一波 |
| **GameOver** | 玩家死亡，本局结束 |

### 规则 2：开始一波

```gdscript
func start_wave() -> void:
    if state != State.Idle:
        return

    current_wave += 1
    state = State.Spawning
    wave_started.emit(current_wave)

    if current_wave == 10:
        boss_wave_started.emit()

    spawn_system.start_spawning(get_wave_config(current_wave))
```

设计说明：

- 波次系统负责开始一波
- 难度曲线系统负责给出这波配置
- 敌人生成系统负责执行落地生成

### 规则 3：Spawning → Clearing

当敌人生成系统发出 `spawning_finished` 时：

```gdscript
func _on_spawning_finished() -> void:
    state = State.Clearing
```

进入 `Clearing` 后：

- 不再生成新敌人
- 等待场上敌人全部清完
- 让玩家获得“这波已经收尾”的感知

### 规则 4：清场判定

```gdscript
if state == State.Clearing and alive_enemies == 0:
    _start_intermission()
```

MVP 建议：

- 可以加入 `0.5 - 1.0s` 的 leeway，防止敌人刚死就立刻切状态显得突兀
- 不建议让 Clearing 持续太久

### 规则 5：Intermission 是短整理，不是主升级阶段

```gdscript
func _start_intermission() -> void:
    state = State.Intermission
    wave_cleared.emit(current_wave)
    intermission_started.emit(current_wave)
    intermission_timer = get_intermission_duration(current_wave)
```

Intermission 的职责：

- 提示这波结束
- 给玩家短暂呼吸感
- 给系统机会刷新 UI、波次 Banner、Boss 提示
- 给玩家处理已经触发的经验升级选择

Intermission **不负责**：

- 作为主要升级来源
- 承担长时间结算
- 让玩家停留很久

### 规则 6：Intermission → 下一波

```gdscript
if state == State.Intermission:
    intermission_timer -= delta
    if intermission_timer <= 0:
        state = State.Idle
        call_deferred("start_wave")
```

普通波节奏建议：

- Wave 1-3：更从容，帮助熟悉节奏
- Wave 4-7：开始压缩呼吸感
- Wave 8-9：接近连续施压
- Wave 10：单独做 Boss 提示与高潮构建

### 规则 7：Boss 波是整局高潮

第 10 波必须在节奏上被明确标记出来：

- 开始前有更强提示
- 敌人生成方式和普通波不同
- 压力曲线明显抬升
- 结算反馈要让玩家知道“这就是一局的峰值”

Boss 波前推荐：

```text
Intermission 延长到 2-3s
显示 Boss 提示 UI
强化音画反馈
再进入 Wave 10
```

### 规则 8：经验升级与波次系统的关系

这是当前版本最重要的设计约束：

**经验升级是主成长入口，波次系统只是给成长留节奏空间。**

因此：

- 升级主要由经验系统触发
- 波次系统不要求“每波结束必须弹升级”
- 如果玩家在波末刚好升级，可以在 Intermission 或下一波早段完成选择
- 波次系统应该兼容升级暂停，但不依赖它

### 规则 9：玩家死亡处理

```gdscript
func _on_player_died() -> void:
    spawn_system.stop_spawning()
    state = State.GameOver
    game_over.emit(current_wave)
```

要求：

- 死亡后立即停止波次推进
- 不再进入下一波
- 交给结算系统和 UI 系统接管

### 规则 10：MVP 不以无尽模式为当前主目标

无尽模式可以作为以后扩展，但不应影响当前 MVP 文档主结构。

当前优先级：

- 先把 10 波短局做扎实
- 先验证 Boss 波高潮是否成立
- 先验证一局打完后是否有“再来一局”的动机

---

## Pressure Curve

### Wave 1-3：建立理解

- 让玩家学会补位和基础布防
- 给玩家第一次感受到“塔比角色更重要”
- Intermission 可以略长

### Wave 4-7：防线成型

- 开始要求玩家做更明确的升级和塔位决策
- 让辅助塔和覆盖关系开始有价值
- 让玩家感到“防线开始滚雪球”

### Wave 8-9：高压前奏

- 清场速度变得重要
- 错误的升级和布防会明显放大风险
- Intermission 压缩到非常短

### Wave 10：高潮验证

- 必须检验前面所有成长是否有效
- 要让玩家明确知道这波是结尾峰值

---

## Formulas

### 公式 1：整局时长估算

```text
run_duration =
    sum(spawn_duration_per_wave)
    + sum(clearing_duration_per_wave)
    + sum(intermission_duration_per_wave)
```

MVP 目标：

```text
4 - 8 分钟
```

### 公式 2：每波体感长度

```text
wave_feel_duration =
    spawn_duration
    + remaining_cleanup_time
    + short_intermission
```

设计原则：

- 单波不能太长，否则短局失焦
- 单波不能太短，否则防线成长来不及形成感知

### 公式 3：Intermission 参考值

```text
normal_wave_intermission = 1.2s ~ 1.8s
boss_prep_intermission = 2.0s ~ 3.0s
```

### 公式 4：波次价值判断

```text
wave_value = pressure_gain + growth_window + pacing_clarity
```

一波如果没有同时提供：

- 压力变化
- 成长空间
- 节奏清晰度

那这波就不是有效波次。

---

## Edge Cases

| 编号 | 边界情况 | 处理方式 |
|------|----------|----------|
| EC-01 | 刚清完最后一只怪又立刻触发升级暂停 | 允许进入 Intermission，但计时应兼容暂停 |
| EC-02 | 玩家在 Intermission 中死亡（理论上极少） | 立即切入 GameOver |
| EC-03 | 敌人生成结束但场上早已无敌人 | 直接进入短 Intermission |
| EC-04 | 场上残敌卡住导致长时间无法清场 | 设置 Clearing 超时保护，防止一局卡死 |
| EC-05 | 第 10 波前玩家刚好升级 | 允许先完成升级，再进入 Boss 波 |
| EC-06 | Intermission 过长导致体验拖沓 | 通过参数压缩，不允许超过短局节奏上限 |
| EC-07 | Intermission 过短导致玩家无感 | 必须至少提供可感知提示与最短整理时间 |

---

## Dependencies

### 上游依赖

| 系统 | 依赖类型 | 接口 | 说明 |
|------|----------|------|------|
| **难度曲线系统** | 硬依赖 | `get_wave_config(wave_number)` | 每波配置来源 |
| **敌人生成系统** | 硬依赖 | `start_spawning(config)`, `stop_spawning()` | 执行敌人生成 |
| **生命值系统** | 硬依赖 | `player_died`, `enemy_died` | 用于 GameOver 与清场 |

### 下游依赖

| 系统 | 依赖类型 | 接口 | 说明 |
|------|----------|------|------|
| **UI系统** | 软依赖 | `wave_started`, `wave_cleared`, `boss_wave_started` | 更新波次提示与节奏反馈 |
| **敌人生成系统** | 软依赖 | 接收波次配置 | 受波次驱动 |
| **结算系统** | 硬依赖 | `game_over(current_wave)` | 一局结束后接管 |
| **升级系统 / 经验系统** | 协作依赖 | 暂停、升级触发 | 波次为其留空间，但不主导其逻辑 |

---

## Tuning Knobs

| 参数名 | 默认值 | 安全范围 | 说明 |
|--------|--------|----------|------|
| `wave_count` | 10 | 8-12 | MVP 总波数 |
| `clearing_leeway_sec` | 0.7 | 0.3-1.5 | 清场切换缓冲 |
| `intermission_sec` | 1.5 | 1.0-2.0 | 普通波整理时间 |
| `boss_prep_sec` | 2.5 | 2.0-3.5 | Boss 波前准备时间 |
| `clearing_timeout_sec` | 20 | 10-60 | 卡场保护 |

---

## Acceptance Criteria

### 功能测试

| ID | 测试项 | Pass 标准 |
|----|--------|-----------|
| AC-WV-01 | 启动第一波 | 游戏开始后能进入 Wave 1 |
| AC-WV-02 | 正常清场切换 | 敌人清空后进入 Intermission |
| AC-WV-03 | Intermission 后推进下一波 | 短暂停顿后自动进入下一波 |
| AC-WV-04 | 第 10 波 Boss 提示 | Boss 波前有明显提示 |
| AC-WV-05 | 玩家死亡中断波次 | 死亡后停止生成并结束推进 |

### 节奏测试

| ID | 测试项 | Pass 标准 |
|----|--------|-----------|
| AC-WV-P01 | 单局时长 | 一局稳定落在 4-8 分钟 |
| AC-WV-P02 | 波间停顿感知 | 玩家能感觉到“这波结束了”，但不觉得拖 |
| AC-WV-P03 | Boss 波高潮成立 | 第 10 波明显比普通波更有终局感 |
| AC-WV-P04 | 短局重复意愿 | 一局结束后玩家愿意立刻再开一局 |

### 设计验证

| ID | 问题 | Pass 标准 |
|----|------|-----------|
| AC-WV-D01 | 波次是否服务塔阵成长 | 玩家觉得每波都在推动防线成型 |
| AC-WV-D02 | 升级主轴是否清晰 | 玩家能理解升级主要来自经验，而不是波末结算 |
| AC-WV-D03 | 节奏是否够短够紧 | 玩家不会把这一局感知成拖长的无尽战 |
